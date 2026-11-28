import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/appearance_settings.dart';
import 'package:material_ui/material_ui.dart';

const _latin = 'Accented Latin';

Future<void> _load(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await loader.load();
}

double _width(String text, List<String> families) {
  final painter = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
            fontFamily: families.first,
            fontFamilyFallback: families.skip(1).toList(),
            fontSize: 1000)),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

void main() {
  setUpAll(() async {
    await _load(bundledFont, 'assets/fonts/NotoSansSC-Regular.ttf');
    await _load(_latin, 'ios/packaging/subtitle-fonts/NotoSans-Regular.ttf');
  });

  test(
      'accented letters the bundled face lacks come whole from the next font, not as a letter plus a lone accent',
      () {
    for (final letter in ['ś', 'ż', 'ć', 'ł', 'ę', 'ś', 'ż', 'ę']) {
      expect(_width(letter, [bundledFont, _latin]), closeTo(_width(letter, [_latin]), 1),
          reason: letter);
    }
  });

  test('letters the bundled face has still come from it', () {
    for (final text in ['a', 'é', 'ü', 'ǚ', 'ế', '中']) {
      expect(_width(text, [bundledFont, _latin]), closeTo(_width(text, [bundledFont]), 1),
          reason: text);
    }
  });
}
