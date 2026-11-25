import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;

import 'app_log.dart';
import 'appearance_settings.dart' show downloadedCjkFamilies;
import 'packs.dart';

/// Noto Sans JP, KR and TC as data packs (packs/fonts-noto-sans-*.json),
/// for a system with no face for that language: a Linux without Noto Sans
/// CJK, and libass on iOS, which draws only in the app's own fonts.
/// Windows, macOS and Android have a face for each, so Japanese kanji are
/// never drawn as Chinese ones there to begin with; nothing is downloaded
/// for them.
class CjkFontPacks {
  CjkFontPacks._();

  /// The pack for each set of character forms (see cjkFormOf).
  static const ids = {'ja': 'fonts-noto-sans-jp', 'ko': 'fonts-noto-sans-kr', 'zh-Hant': 'fonts-noto-sans-tc'};

  /// The family inside each pack's font, under which Flutter loads it too.
  static const families = {'ja': 'Noto Sans JP', 'ko': 'Noto Sans KR', 'zh-Hant': 'Noto Sans TC'};

  /// fontconfig's name for each language.
  static const _fontconfigLanguages = {'ja': 'ja', 'ko': 'ko', 'zh-Hant': 'zh-tw'};

  /// The font file in each installed pack, by forms.
  static Map<String, File> installedFiles(PackManager packs) => {
        for (final MapEntry(key: forms, value: id) in ids.entries)
          if (packs.installedOf(id) case final installed?)
            if (installed.pack.files.firstOrNull case final file?)
              if (installed.file(file.path).existsSync()) forms: installed.file(file.path),
      };

  static final _known = <String, bool>{};

  /// Whether this system needs the pack for [forms]: on Linux when
  /// fontconfig knows no face for the language; on iOS for libass, except
  /// Korean, whose face the app bundles.
  static Future<bool> needed(String forms) async {
    if (Platform.isIOS) return forms != 'ko';
    if (!Platform.isLinux) return false;
    if (_known[forms] case final known?) return known;
    var has = true;
    try {
      final result = await Process.run('fc-list', [':lang=${_fontconfigLanguages[forms]}', 'family']);
      has = result.exitCode != 0 || '${result.stdout}'.trim().isNotEmpty;
    } catch (e) {
      logDebug(() => 'Could not ask fontconfig for $forms fonts: $e');
    }
    return _known[forms] = !has;
  }

  /// Loads the installed packs' fonts into Flutter, once each, and names
  /// them in [downloadedCjkFamilies]; true when one was new.
  static Future<bool> load(PackManager packs) async {
    var added = false;
    for (final MapEntry(key: forms, value: file) in installedFiles(packs).entries) {
      final family = families[forms]!;
      if (downloadedCjkFamilies[forms] == family) continue;
      try {
        final bytes = await file.readAsBytes();
        await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        downloadedCjkFamilies[forms] = family;
        added = true;
        logInfo('Loaded the downloaded font $family');
      } catch (e) {
        logWarn('Could not load the downloaded font $family: $e');
      }
    }
    return added;
  }

  /// Makes [folder] hold links to the installed packs' fonts and [extra],
  /// for libass's sub-fonts-dir on Linux; null when there are none.
  static String? linkFolder(PackManager packs, String folder, {List<File> extra = const []}) {
    final files = [...installedFiles(packs).values, ...extra];
    if (files.isEmpty) return null;
    try {
      final dir = Directory(folder);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      for (final file in files) {
        Link('$folder/${file.uri.pathSegments.last}').createSync(file.path);
      }
      return folder;
    } catch (e) {
      logWarn('Could not gather the downloaded fonts: $e');
      return null;
    }
  }
}
