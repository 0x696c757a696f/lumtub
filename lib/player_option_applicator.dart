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
      'autosync': settings.autosync == 0 ? 'no' : settings.autosync.toString(),
      'af': settings.audioFilter,
      for (final (key, _) in pictureProperties) key: (settings.picture[key] ?? 0).toString(),
      'audio-delay': (settings.audioDelayMs / 1000).toString(),
      'scale': settings.scale,
      'deband': settings.deband ? 'yes' : 'no',
      'interpolation': settings.interpolation ? 'yes' : 'no',
      'video-sync': settings.videoSync.mpvValue,
      'sub-scale': settings.subtitleScale.toStringAsFixed(1),
      'sub-pos': settings.subtitlePosition.toString(),
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
      'cache-secs': settings.cacheSeconds.toString(),
      'demuxer-max-bytes': '${settings.cacheMemoryMb}MiB',
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
  static Future<List<String>> apply(Player player, PlayerSettings settings) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return const [];
    final failed = <String>[];
    for (final entry in optionsFor(settings).entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {
        failed.add(entry.key);
      }
    }
    return failed;
  }
}
