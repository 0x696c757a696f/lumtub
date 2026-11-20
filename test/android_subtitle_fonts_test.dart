import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/android_subtitle_fonts.dart';
import 'package:lumtub/libass_layout.dart';

void main() {
  setUp(() {
    AndroidSubtitleFonts.cjk = true;
    AndroidSubtitleFonts.latin = 'Roboto';
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

  test('accented letters Noto Sans CJK lacks get the Latin font, as whole lines', () {
    expect(AndroidSubtitleFonts.familyFor('historia świętego, dzisiaj świętej\nalbo raczej w sumie błogosławionej'), 'Roboto');
    expect(AndroidSubtitleFonts.familyFor('Nadwrażliwość'), 'Roboto');
    expect(AndroidSubtitleFonts.familyFor('Nadwraz\u0307liwos\u0301c\u0301'), 'Roboto', reason: 'decomposed accents too');
    expect(AndroidSubtitleFonts.familyFor('Dobrý den, příteli'), 'Roboto');
    expect(AndroidSubtitleFonts.familyFor('Привіт, їжак'), 'Roboto');
    expect(AndroidSubtitleFonts.familyFor('Xin chào thế giới'), 'Noto Sans CJK SC', reason: 'Noto Sans SC has Vietnamese');
    expect(AndroidSubtitleFonts.familyFor('café, naïve, Müller · lǜ'), 'Noto Sans CJK SC');
    expect(AndroidSubtitleFonts.familyFor('圣人的短篇故事\nhistoria świętego'), isNull, reason: 'no one font has both');
    AndroidSubtitleFonts.latin = null;
    expect(AndroidSubtitleFonts.familyFor('błogosławionej'), isNull);
  });

  test('the main and the second subtitle each need only a font of their own', () {
    expect(AndroidSubtitleFonts.forLines(['w sensie, no bo w takim świecie żyli.', '因为那就是他们生活的世界。']), (drawable: true, main: 'Roboto'));
    expect(AndroidSubtitleFonts.forLines(['因为那就是他们生活的世界。', 'w takim świecie żyli']), (drawable: true, main: 'Noto Sans CJK SC'));
    expect(AndroidSubtitleFonts.forLines(['مرحبا بالعالم', '你好，世界']), (drawable: true, main: 'Noto Naskh Arabic'));
    expect(AndroidSubtitleFonts.forLines(['Dobrý den, příteli', 'สวัสดี']), (drawable: true, main: 'Roboto'));
    expect(AndroidSubtitleFonts.forLines(['', '你好']), (drawable: true, main: null), reason: 'no main line: its font stays');
    expect(AndroidSubtitleFonts.forLines(['圣人的短篇故事 historia świętego', '']), (drawable: false, main: null));
    expect(AndroidSubtitleFonts.forLines(['hello', 'مرحبا 你好']), (drawable: false, main: 'Noto Sans CJK SC'));
    expect(AndroidSubtitleFonts.forLines(['hello', 'नमस्ते']).drawable, isFalse, reason: 'no Devanagari font was found');
    // The second subtitle's copy holds the main lines after a blank line.
    const copy = '早上好。亲爱的朋友们。\n\u00a0\nDzień dobry moi drodzy.';
    expect(AndroidSubtitleFonts.forLines(['Dzień dobry moi drodzy.', copy]).drawable, isFalse);
    expect(AndroidSubtitleFonts.forLines(['Dzień dobry moi drodzy.', secondCopyOwnText(copy)]), (drawable: true, main: 'Roboto'));
  });

  test('another script gets its own font, alone with digits and punctuation', () {
    expect(AndroidSubtitleFonts.familyFor('مرحبا بالعالم 2026!'), 'Noto Naskh Arabic');
    expect(AndroidSubtitleFonts.familyFor('สวัสดี'), 'Noto Sans Thai');
  });

  test('text no one font draws, or a script whose font is missing, is left to Flutter', () {
    expect(AndroidSubtitleFonts.familyFor('مرحبا\n你好'), isNull);
    expect(AndroidSubtitleFonts.familyFor('สวัสดี hello'), isNull);
    expect(AndroidSubtitleFonts.familyFor('नमस्ते'), isNull, reason: 'no Devanagari font was found');
    expect(AndroidSubtitleFonts.familyFor('བཀྲ་ཤིས་བདེ་ལེགས'), isNull, reason: 'no font here has Tibetan');
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
    expect(Directory(folder!).listSync().map((f) => f.path.split(RegExp(r'[/\\]')).last).toSet(), {'NotoSansCJK-Regular.ttc', 'Roboto-Regular.ttf', 'NotoNaskhArabic-Regular.ttf', 'NotoSansThai-Regular.ttf'});
    expect(AndroidSubtitleFonts.families, {'Arabic': 'Noto Naskh Arabic', 'Thai': 'Noto Sans Thai'});
    expect(AndroidSubtitleFonts.latin, 'Roboto');
    File('${system.path}/NotoSansCJK-Regular.ttc').deleteSync();
    expect(await AndroidSubtitleFonts.prepare('${root.path}/subs', system: system.path), isNull, reason: 'without the CJK font libass gets nothing');
  });

  test("on iOS the folder links the app's own fonts, Korean in Noto Sans KR", () async {
    final root = Directory.systemTemp.createTempSync('fonts');
    addTearDown(() => root.deleteSync(recursive: true));
    final flutter = Directory('${root.path}/flutter')..createSync();
    final bundled = Directory('${root.path}/bundled')..createSync();
    File('${flutter.path}/NotoSansSC-Regular.ttf').writeAsStringSync('x');
    for (final name in ['NotoSansKR-Regular.otf', 'NotoSans-Regular.ttf', 'NotoSansArabic-Regular.ttf', 'NotoSansThai-Regular.ttf', 'SOURCES.md']) {
      File('${bundled.path}/$name').writeAsStringSync('x');
    }
    final android = AndroidSubtitleFonts.cjkFamilies;
    addTearDown(() => AndroidSubtitleFonts.cjkFamilies = android);
    final folder = await AndroidSubtitleFonts.prepareIos('${root.path}/subs', flutterFonts: flutter.path, bundled: bundled.path);
    expect(Directory(folder!).listSync().map((f) => f.path.split(RegExp(r'[/\\]')).last).toSet(), {'NotoSansSC-Regular.ttf', 'NotoSansKR-Regular.otf', 'NotoSans-Regular.ttf', 'NotoSansArabic-Regular.ttf', 'NotoSansThai-Regular.ttf'});
    expect(File('$folder/NotoSansKR-Regular.otf').readAsStringSync(), 'x');
    expect(AndroidSubtitleFonts.families, {'Arabic': 'Noto Sans Arabic', 'Thai': 'Noto Sans Thai'});
    expect(AndroidSubtitleFonts.familyFor('안녕하세요 hello'), 'Noto Sans KR');
    expect(AndroidSubtitleFonts.familyFor('そして最初に'), 'Noto Sans SC');
    expect(AndroidSubtitleFonts.familyFor('因此 so'), 'Noto Sans SC');
    expect(AndroidSubtitleFonts.familyFor('สวัสดี'), 'Noto Sans Thai');
    expect(AndroidSubtitleFonts.familyFor('błogosławionej'), 'Noto Sans');
    File('${flutter.path}/NotoSansSC-Regular.ttf').deleteSync();
    expect(await AndroidSubtitleFonts.prepareIos('${root.path}/subs', flutterFonts: flutter.path, bundled: bundled.path), isNull);
  });
}
