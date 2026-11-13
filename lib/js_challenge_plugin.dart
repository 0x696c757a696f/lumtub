import 'dart:io';

import 'package:flutter/services.dart';

import 'app_log.dart';

/// Lumtub's yt-dlp plugin (python/lumtub_jsc.py): yt-dlp solves YouTube's
/// JavaScript challenges with the QuickJS inside the core library, in its
/// own process, and keeps the preprocessed player between videos. Used on
/// Android and iOS, where no Deno runs; yt-dlp finds the core through the
/// LUMTUB_CORE environment variable.
class JsChallengePlugin {
  JsChallengePlugin._();

  static const asset = 'python/lumtub_jsc.py';

  /// Writes the plugin under [folder] in the layout --plugin-dirs expects
  /// and gives back the folder to pass, or null when it could not be.
  static Future<String?> install(String folder) async {
    try {
      final root = Directory('$folder${Platform.pathSeparator}yt-dlp-plugins');
      final file = File([root.path, 'lumtub', 'yt_dlp_plugins', 'extractor', 'lumtub_jsc.py'].join(Platform.pathSeparator));
      final source = await rootBundle.loadString(asset);
      if (!file.existsSync() || file.readAsStringSync() != source) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(source, flush: true);
      }
      return root.path;
    } catch (e) {
      logWarn('Could not set up the yt-dlp challenge plugin: $e');
      return null;
    }
  }
}
