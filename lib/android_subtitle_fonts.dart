import 'dart:io';

import 'app_log.dart';

/// Fonts for subtitles drawn by libmpv (libass) on Android.
///
/// Android's libmpv has no fontconfig, so libass sees only the fonts in
/// `sub-fonts-dir` and draws everything in the one `sub-font` names: it
/// does not fall back to another font for a character that one lacks. So
/// the folder holds links to the system's own fonts, Noto Sans CJK for
/// Chinese, Japanese, Korean, Latin, Greek and Cyrillic and one font for
/// each other script, and the font is picked by the script of the text on
/// screen. Text no one of them can draw whole, such as Arabic over Chinese,
/// is left to Flutter's subtitle view, which falls back by itself.
class AndroidSubtitleFonts {
  AndroidSubtitleFonts._();

  static const _system = '/system/fonts';

  /// The system font for each script outside Noto Sans CJK, by the start
  /// of its file name, in order of preference.
  static const _scriptFiles = {
    'Arabic': ['NotoNaskhArabic-', 'NotoSansArabic-'],
    'Hebrew': ['NotoSansHebrew-'],
    'Thai': ['NotoSansThai-'],
    'Lao': ['NotoSansLao-'],
    'Khmer': ['NotoSansKhmer-'],
    'Myanmar': ['NotoSansMyanmar-'],
    'Devanagari': ['NotoSansDevanagari-'],
    'Bengali': ['NotoSansBengali-'],
    'Gujarati': ['NotoSansGujarati-'],
    'Gurmukhi': ['NotoSansGurmukhi-'],
    'Tamil': ['NotoSansTamil-'],
    'Telugu': ['NotoSansTelugu-'],
    'Kannada': ['NotoSansKannada-'],
    'Malayalam': ['NotoSansMalayalam-'],
    'Sinhala': ['NotoSansSinhala-'],
    'Oriya': ['NotoSansOriya-'],
    'Ethiopic': ['NotoSansEthiopic-'],
    'Georgian': ['NotoSansGeorgian-'],
    'Armenian': ['NotoSansArmenian-'],
  };

  /// The characters of each script in [_scriptFiles].
  static final _scripts = {
    'Arabic': RegExp(r'[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]'),
    'Hebrew': RegExp(r'[֐-׿יִ-ﭏ]'),
    'Thai': RegExp(r'[฀-๿]'),
    'Lao': RegExp(r'[຀-໿]'),
    'Khmer': RegExp(r'[ក-៿]'),
    'Myanmar': RegExp(r'[က-႟]'),
    'Devanagari': RegExp(r'[ऀ-ॿ]'),
    'Bengali': RegExp(r'[ঀ-৿]'),
    'Gujarati': RegExp(r'[઀-૿]'),
    'Gurmukhi': RegExp(r'[਀-੿]'),
    'Tamil': RegExp(r'[஀-௿]'),
    'Telugu': RegExp(r'[ఀ-౿]'),
    'Kannada': RegExp(r'[ಀ-೿]'),
    'Malayalam': RegExp(r'[ഀ-ൿ]'),
    'Sinhala': RegExp(r'[඀-෿]'),
    'Oriya': RegExp(r'[଀-୿]'),
    'Ethiopic': RegExp(r'[ሀ-᎟]'),
    'Georgian': RegExp(r'[Ⴀ-ჿ]'),
    'Armenian': RegExp(r'[԰-֏]'),
  };

  static final _letter = RegExp(r'[\p{L}]', unicode: true);
  static final _kana = RegExp(r'[぀-ヿ]');
  static final _hangul = RegExp(r'[가-힯ᄀ-ᇿ㄰-㆏]');

  /// The family for each script whose font was found, filled by [prepare].
  static final families = <String, String>{};

  /// Whether Noto Sans CJK was found.
  static bool cjk = false;

  /// Makes [folder] hold links to the system fonts libass may use and
  /// returns it; null when Android has no Noto Sans CJK.
  static Future<String?> prepare(String folder, {String system = _system}) async {
    try {
      final names = [for (final f in Directory(system).listSync()) f.path.split(RegExp(r'[/\\]')).last]..sort();
      final dir = Directory(folder);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      void link(String name) {
        try {
          Link('$folder/$name').createSync('$system/$name');
        } on FileSystemException {
          File('$system/$name').copySync('$folder/$name');
        }
      }

      final cjkFile = names.where((n) => n.startsWith('NotoSansCJK-Regular.tt')).firstOrNull;
      cjk = cjkFile != null;
      if (!cjk) return null;
      link(cjkFile!);
      families.clear();
      for (final MapEntry(key: script, value: prefixes) in _scriptFiles.entries) {
        for (final prefix in prefixes) {
          // The plain face, not the narrower UI one nor a bold or serif one.
          final file = names.where((n) => n.startsWith(prefix) && RegExp(r'-(Regular|VF)\.[ot]tf$').hasMatch(n)).firstOrNull;
          if (file == null) continue;
          link(file);
          families[script] = familyOf(file);
          break;
        }
      }
      return folder;
    } catch (e) {
      logWarn('Could not gather the system fonts for subtitles: $e');
      return null;
    }
  }

  /// "NotoNaskhArabic-Regular.ttf" is the family "Noto Naskh Arabic".
  static String familyOf(String file) => file.split('-').first.replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ');

  /// The one family that draws all of [text], for subtitles whose language
  /// is [language]; null when no one family can.
  static String? familyFor(String text, {String language = ''}) {
    final needed = {
      for (final MapEntry(key: script, value: pattern) in _scripts.entries)
        if (pattern.hasMatch(text)) script,
    };
    // The CJK font also has Latin, Greek and Cyrillic; a script font has
    // none of them, so a line mixing the two cannot be drawn in one.
    var other = text;
    for (final pattern in _scripts.values) {
      other = other.replaceAll(pattern, '');
    }
    final rest = _letter.hasMatch(other);
    if (needed.length > 1 || (needed.length == 1 && rest)) return null;
    if (needed.length == 1) return families[needed.first];
    if (!cjk) return null;
    // Han characters are drawn in the shapes of the language read.
    if (_kana.hasMatch(text) || language.startsWith('ja')) return 'Noto Sans CJK JP';
    if (_hangul.hasMatch(text) || language.startsWith('ko')) return 'Noto Sans CJK KR';
    if (RegExp(r'^zh-(Hant|TW|HK|MO)').hasMatch(language)) return 'Noto Sans CJK TC';
    return 'Noto Sans CJK SC';
  }
}
