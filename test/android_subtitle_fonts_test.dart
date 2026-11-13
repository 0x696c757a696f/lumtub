import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/android_subtitle_fonts.dart';

void main() {
  setUp(() {
    AndroidSubtitleFonts.cjk = true;
    AndroidSubtitleFonts.families
      ..clear()
      ..addAll({'Arabic': 'Noto Naskh Arabic', 'Thai': 'Noto Sans Thai', 'Hebrew': 'Noto Sans Hebrew'});
  });

  test('a system font file name gives its family', () {
    expect(AndroidSubtitleFonts.familyOf('NotoNaskhArabic-Regular.ttf'), 'Noto Naskh Arabic');
    expect(AndroidSubtitleFonts.familyOf('NotoSansDevanagari-VF.ttf'), 'Noto Sans Devanagari');
  });

  test('Chinese, Japanese, Korean, Latin and Cyrillic share Noto Sans CJK, in the shapes of the language', () {
    expect(AndroidSubtitleFonts.familyFor('因此，首先\nSo first, the sandbox'), 'Noto Sans CJK SC');
    expect(AndroidSubtitleFonts.familyFor('因此', language: 'zh-Hant'), 'Noto Sans CJK TC');
    expect(AndroidSubtitleFonts.familyFor('そして最初に'), 'Noto Sans CJK JP');
    expect(AndroidSubtitleFonts.familyFor('안녕하세요 hello'), 'Noto Sans CJK KR');
    expect(AndroidSubtitleFonts.familyFor('Привет, мир'), 'Noto Sans CJK SC');
  });

  test('another script gets its own font, alone with digits and punctuation', () {
    expect(AndroidSubtitleFonts.familyFor('مرحبا بالعالم 2026!'), 'Noto Naskh Arabic');
    expect(AndroidSubtitleFonts.familyFor('สวัสดี'), 'Noto Sans Thai');
  });

  test('text no one font draws, or a script whose font is missing, is left to Flutter', () {
    expect(AndroidSubtitleFonts.familyFor('مرحبا\n你好'), isNull);
    expect(AndroidSubtitleFonts.familyFor('สวัสดี hello'), isNull);
    expect(AndroidSubtitleFonts.familyFor('नमस्ते'), isNull, reason: 'no Devanagari font was found');
    AndroidSubtitleFonts.cjk = false;
    expect(AndroidSubtitleFonts.familyFor('hello'), isNull);
  });

  test('the folder links the CJK font and the plain face of each script, nothing else', () async {
    final root = Directory.systemTemp.createTempSync('fonts');
    addTearDown(() => root.deleteSync(recursive: true));
    final system = Directory('${root.path}/system')..createSync();
    for (final name in ['NotoSansCJK-Regular.ttc', 'NotoNaskhArabic-Regular.ttf', 'NotoNaskhArabic-Bold.ttf', 'NotoNaskhArabicUI-Regular.ttf', 'NotoSansThai-Regular.ttf', 'NotoColorEmoji.ttf', 'Roboto-Regular.ttf']) {
      File('${system.path}/$name').writeAsStringSync('x');
    }
    final folder = await AndroidSubtitleFonts.prepare('${root.path}/subs', system: system.path);
    expect(folder, '${root.path}/subs');
    expect(Directory(folder!).listSync().map((f) => f.path.split('/').last).toSet(), {'NotoSansCJK-Regular.ttc', 'NotoNaskhArabic-Regular.ttf', 'NotoSansThai-Regular.ttf'});
    expect(AndroidSubtitleFonts.families, {'Arabic': 'Noto Naskh Arabic', 'Thai': 'Noto Sans Thai'});
    File('${system.path}/NotoSansCJK-Regular.ttc').deleteSync();
    expect(await AndroidSubtitleFonts.prepare('${root.path}/subs', system: system.path), isNull, reason: 'without the CJK font libass gets nothing');
  });
}
