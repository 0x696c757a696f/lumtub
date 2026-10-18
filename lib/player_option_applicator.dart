import 'package:media_kit/media_kit.dart';

import 'player_settings.dart';

class PlayerOptionApplicator {
  static Map<String, String> optionsFor(PlayerSettings settings) => {
        'hwdec': settings.hwdec,
        'scale': settings.scale,
        'deband': settings.deband ? 'yes' : 'no',
        'interpolation': settings.interpolation ? 'yes' : 'no',
        'sub-scale': settings.subtitleScale.toStringAsFixed(1),
        'sub-pos': settings.subtitlePosition.toString(),
        'cache': settings.cacheMode,
        'cache-secs': settings.cacheSeconds.toString(),
        'demuxer-max-bytes': '${settings.cacheMemoryMb}MiB',
        ...settings.customOptions,
      };

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
