import 'dart:convert';

import 'package:media_kit/media_kit.dart';

import 'player_settings.dart';

class PlayerOptionApplicator {
  static Map<String, String> optionsFor(PlayerSettings settings) {
    final subtitles = settings.subtitleMode != SubtitleMode.off;
    final language = settings.subtitleLanguage;
    return {
      'hwdec': settings.hwdec,
      'hwdec-codecs': settings.hwdecCodecs,
      'd3d11va-zero-copy': settings.d3d11vaZeroCopy ? 'yes' : 'no',
      'vd-lavc-dr': settings.directRendering,
      // Not 'no': mpv reads that as -1, which inverts the audio clock
      // smoothing and makes the picture run ahead of the sound.
      'autosync': settings.autosync.toString(),
      'af': settings.audioFilter,
      for (final (key, _) in pictureProperties) key: (settings.picture[key] ?? 0).toString(),
      'audio-delay': (settings.audioDelayMs / 1000).toString(),
      'scale': settings.scale,
      'deband': settings.deband ? 'yes' : 'no',
      'interpolation': settings.interpolation ? 'yes' : 'no',
      // 低资源占用优先 also scales the picture the cheapest way, as mpv's
      // fast profile does: a 4K frame shrunk to a window is most of the GPU
      // work after decoding.
      if (settings.strategy == PlaybackStrategy.lowResource) ...fastRendering,
      'video-sync': settings.videoSync.mpvValue,
      'sub-scale': settings.subtitleScale.toStringAsFixed(1),
      'sub-font': settings.subtitleFont.isEmpty ? 'sans-serif' : settings.subtitleFont,
      'sub-color': PlayerSettings.mpvColor(settings.subtitleColor, settings.subtitleOpacity),
      'sub-pos': settings.subtitlePosition.toString(),
      // The secondary subtitle (libass) sits just above the main one.
      'secondary-sub-pos': (settings.subtitlePosition - 8).clamp(0, 100).toString(),
      'sub-border-size': settings.subtitleBorder.toStringAsFixed(1),
      'sub-border-style': settings.subtitleBackground ? 'background-box' : 'outline-and-shadow',
      'sub-bold': settings.subtitleBold ? 'yes' : 'no',
      // Tracks yt-dlp lists are added as "auto": mpv selects one only when
      // its language is in slang.
      'slang': subtitles ? language.mpvLangs : '',
      // Without sub-langs mpv's ytdl_hook asks yt-dlp for every manual
      // subtitle; automatic captions must be requested by name.
      'ytdl-raw-options': ytdlRawOptions(settings),
      'cache': settings.cacheMode,
      // media_kit turns on mpv's disk cache, which libmpv here cannot create
      // ("Failed to create file cache" for every video); the cache is memory.
      'cache-on-disk': 'no',
      // media_kit's 5 s gives up on a slow proxy before it answers.
      'network-timeout': '20',
      'cache-secs': settings.cacheSeconds.toString(),
      'demuxer-max-bytes': '${settings.cacheMemoryMb}MiB',
      // What was played is kept for seeking back; mpv keeps 50 MiB, which
      // goes on top of the forward cache above.
      'demuxer-max-back-bytes': '${(settings.cacheMemoryMb ~/ 4).clamp(16, 50)}MiB',
      'volume-max': settings.volumeMax.toString(),
      'audio-device': settings.audioDevice,
      'loop-file': settings.playOrder == PlayOrder.singleCycle ? 'inf' : 'no',
      ...settings.customOptions,
    };
  }

  /// Options mpv's ytdl_hook passes to yt-dlp. [infoJson] is a file from an
  /// earlier extraction: yt-dlp then picks formats and subtitles from it
  /// without asking YouTube again.
  static String ytdlRawOptions(PlayerSettings settings, {String? infoJson, String? proxy}) {
    final subtitles = settings.subtitleMode != SubtitleMode.off;
    // mpv's %length% quoting keeps a comma or equals sign, as a path may
    // have, from splitting the option.
    String quote(String value) => value.contains(RegExp('[,=%]')) || value.startsWith(RegExp(r'["\[]')) ? '%${utf8.encode(value).length}%$value' : value;
    return [
      if (subtitles) 'sub-langs=${quote(settings.subtitleLanguage.ytDlpLangs)}',
      if (subtitles && settings.subtitleMode == SubtitleMode.always) 'write-auto-subs=',
      if (infoJson != null) 'load-info-json=${quote(infoJson)}',
      // Also for SOCKS proxies, which ytdl_hook does not take from http-proxy.
      if (proxy != null) 'proxy=${quote(proxy)}',
    ].join(',');
  }

  /// Returns unsupported or rejected options without interrupting the player.
  /// What 低资源占用优先 changes beyond the user's own options.
  static const fastRendering = {
    'scale': 'bilinear',
    'dscale': 'bilinear',
    'cscale': 'bilinear',
    'correct-downscaling': 'no',
    'linear-downscaling': 'no',
    'sigmoid-upscaling': 'no',
    'dither': 'no',
    'deband': 'no',
    'interpolation': 'no',
  };

  /// libmpv's own values of [fastRendering]'s options, read before they are
  /// first changed, so leaving 低资源占用优先 restores them.
  static final _mpvDefaults = Expando<Map<String, String>>();

  static Future<List<String>> apply(Player player, PlayerSettings settings) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return const [];
    final failed = <String>[];
    var defaults = _mpvDefaults[player];
    if (defaults == null) {
      defaults = {};
      for (final key in fastRendering.keys) {
        try {
          defaults[key] = await platform.getProperty(key);
        } catch (_) {}
      }
      _mpvDefaults[player] = defaults;
    }
    final options = optionsFor(settings);
    for (final entry in defaults.entries) {
      options.putIfAbsent(entry.key, () => entry.value);
    }
    for (final entry in options.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {
        failed.add(entry.key);
      }
    }
    return failed;
  }
}

/// The average time to draw a frame, from frame timings such as
/// `draw=240/13.1ms/29.9ms`, when it takes more than 60% of a frame's time
/// at [fps]; null while drawing keeps up or too few frames were drawn.
double? drawBusy(String frames, double fps) {
  final match = RegExp(r'draw=(\d+)/([\d.]+)ms').firstMatch(frames);
  if (match == null || fps <= 0) return null;
  final count = int.parse(match[1]!);
  final average = double.parse(match[2]!);
  return count >= 50 && average > 600 / fps ? average : null;
}

/// The next quality below [height] among [available], for playback that
/// keeps dropping frames; null at 360p or when there is none.
int? stepDownHeight(int height, Iterable<int> available) {
  int? lower;
  for (final h in available) {
    if (h >= 360 && h < height && (lower == null || h > lower)) lower = h;
  }
  return lower;
}
