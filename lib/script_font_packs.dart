import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;

import 'android_subtitle_fonts.dart';
import 'app_log.dart';
import 'appearance_settings.dart' show downloadedScriptFamilies;
import 'packs.dart';

/// Noto fonts for the scripts of [AndroidSubtitleFonts] (Arabic, Hindi,
/// Thai, Tibetan, Mongolian and so on) as one data pack
/// (packs/fonts-noto-scripts.json), for a Linux whose fontconfig knows no
/// font for a script a subtitle is written in. Windows, macOS and Android
/// have one for each; iOS bundles them.
class ScriptFontPack {
  ScriptFontPack._();

  static const id = 'fonts-noto-scripts';

  static final _missing = <String, bool>{};

  /// Whether fontconfig knows no font with [sample], a character of
  /// [script]; asked once per script.
  static Future<bool> missing(String script, int sample) async {
    if (!Platform.isLinux) return false;
    if (_missing[script] case final known?) return known;
    var has = true;
    try {
      final result = await Process.run('fc-list', [':charset=${sample.toRadixString(16)}', 'family']);
      has = result.exitCode != 0 || '${result.stdout}'.trim().isNotEmpty;
    } catch (e) {
      logDebug(() => 'Could not ask fontconfig for $script fonts: $e');
    }
    return _missing[script] = !has;
  }

  /// The installed pack's font file for each script.
  static Map<String, File> installedFiles(PackManager packs) {
    final installed = packs.installedOf(id);
    if (installed == null) return const {};
    return {
      for (final file in installed.pack.files)
        if (AndroidSubtitleFonts.scriptOfFile(file.path.split('/').last) case final script?)
          if (installed.file(file.path).existsSync()) script: installed.file(file.path),
    };
  }

  /// The family of a font file of the pack.
  static String familyOf(File file) => AndroidSubtitleFonts.familyOf(file.uri.pathSegments.last);

  /// Loads [file] into Flutter under its family and adds it to
  /// [downloadedScriptFamilies]; true when it was not there yet.
  static Future<bool> load(File file) async {
    final family = familyOf(file);
    if (downloadedScriptFamilies.contains(family)) return false;
    try {
      final bytes = await file.readAsBytes();
      await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      downloadedScriptFamilies.add(family);
      logInfo('Loaded the downloaded font $family');
      return true;
    } catch (e) {
      logWarn('Could not load the downloaded font $family: $e');
      return false;
    }
  }
}
