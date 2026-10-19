import 'package:media_kit/media_kit.dart';

import 'player_settings.dart';

class PlayerOptionApplicator {
  static Map<String, String> optionsFor(PlayerSettings settings) {
    final subtitles = settings.subtitleMode != SubtitleMode.off;
    final language = settings.subtitleLanguage;
    return {
      'hwdec': settings.hwdec,
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
      'ytdl-raw-options': subtitles
          ? ['sub-langs=${language.ytDlpLangs}', if (settings.subtitleMode == SubtitleMode.always) 'write-auto-subs='].join(',')
          : '',
      'cache': settings.cacheMode,
      'cache-secs': settings.cacheSeconds.toString(),
      'demuxer-max-bytes': '${settings.cacheMemoryMb}MiB',
      'volume-max': settings.volumeMax.toString(),
      'audio-device': settings.audioDevice,
      'loop-file': settings.playOrder == PlayOrder.singleCycle ? 'inf' : 'no',
      ...settings.customOptions,
    };
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
