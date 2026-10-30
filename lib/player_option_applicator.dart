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
      // Who draws the subtitles: libmpv (libass) or the Flutter view, which
      // reads sub-text either way. Set here, a switch applies at once.
      'sub-ass': settings.libassSubtitles ? 'yes' : 'no',
      'sub-visibility': settings.libassSubtitles ? 'yes' : 'no',
      'secondary-sub-visibility': settings.libassSubtitles ? 'yes' : 'no',
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
      // YouTube cuts a long open-ended download every couple of megabytes,
      // and mpv's curl gives up after five cuts in a row: asked for in
      // pieces, each reply ends cleanly and none counts as a failure.
      'curl-max-request-size': '10MiB',
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
      // The video's own language: yt-dlp names its automatic captions
      // "<language>-orig"; an uploaded one in it is added once known.
      if (subtitles) 'sub-langs=${quote(settings.subtitleOriginal ? '.*-orig' : settings.subtitleLanguage.ytDlpLangs)}',
      if (subtitles && (settings.subtitleMode == SubtitleMode.always || settings.subtitleOriginal)) 'write-auto-subs=',
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
    // Dithering stays: it costs little and without it dark gradients band.
    'deband': 'no',
    'interpolation': 'no',
  };

  /// libmpv's own values of [fastRendering]'s options, read before they are
  /// first changed, so leaving 低资源占用优先 restores them.
  static final _mpvDefaults = Expando<Map<String, String>>();

  /// libmpv's own values of the free-form options, read before they are
  /// first set, so removing one from the settings puts it back.
  static final _customDefaults = Expando<Map<String, String>>();

  /// Sets [settings]' options on [player]. With [previous], the settings
  /// libmpv already has, only the options that differ are set: setting
  /// hwdec or the decoder options again restarts the video decoder, which
  /// a change of subtitle colour must not.
  static Future<List<String>> apply(Player player, PlayerSettings settings, {PlayerSettings? previous}) async {
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
    final before = previous == null ? null : optionsFor(previous);
    final customDefaults = _customDefaults[player] ??= {};
    for (final entry in options.entries) {
      if (before != null && (before[entry.key] ?? defaults[entry.key]) == entry.value) continue;
      try {
        if (settings.customOptions.containsKey(entry.key) && !customDefaults.containsKey(entry.key)) {
          customDefaults[entry.key] = await platform.getProperty(entry.key);
        }
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {
        failed.add(entry.key);
      }
    }
    // A free-form option taken out of the settings goes back to libmpv's
    // value, not only at the next start.
    for (final key in previous?.customOptions.keys ?? const <String>[]) {
      final value = customDefaults[key];
      if (options.containsKey(key) || value == null) continue;
      try {
        await platform.setProperty(key, value);
      } catch (_) {}
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
