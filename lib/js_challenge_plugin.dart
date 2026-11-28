import 'dart:io';

import 'package:flutter/services.dart';

import 'app_directories.dart';
import 'app_log.dart';
import 'native_core.dart';

/// Lumtub's yt-dlp plugin (python/lumtub_jsc.py): yt-dlp solves YouTube's
/// JavaScript challenges with the QuickJS inside the core library, in its
/// own process, and keeps the preprocessed player between videos. Used on
/// Android and iOS, where no Deno runs, and on computers ahead of Deno;
/// yt-dlp finds the core through the LUMTUB_CORE environment variable.
class JsChallengePlugin {
  JsChallengePlugin._();

  /// On a computer, the plugin folder and the core's path once [prepare]
  /// set them up; every yt-dlp run is given them (ProcessTree.start).
  static (String, String)? desktop;

  /// Sets up [desktop] under [folder]. Off on phones, which add the plugin
  /// themselves, and under tests.
  static Future<void> prepare(String folder) async {
    if (Platform.isAndroid || Platform.isIOS || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    final core = NativeCore.path;
    if (core == null) return;
    final plugins = await install(folder);
    if (plugins != null) desktop = (plugins, core);
  }

  static const asset = 'python/lumtub_jsc.py';

  /// Writes the plugin under [folder] in the layout --plugin-dirs expects
  /// and gives back the folder to pass, or null when it could not be.
  static Future<String?> install(String folder) async {
    try {
      final root = Directory('$folder${Platform.pathSeparator}yt-dlp-plugins');
      final file = File([root.path, 'lumtub', 'yt_dlp_plugins', 'extractor', 'lumtub_jsc.py']
          .join(Platform.pathSeparator));
      final source = await rootBundle.loadString(asset);
      if (!await file.exists() || await file.readAsString() != source) {
        await writeFileAtomic(file, source);
      }
      return root.path;
    } catch (e) {
      logWarn('Could not set up the yt-dlp challenge plugin: $e');
      return null;
    }
  }
}
