import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/appearance_settings.dart';

Future<void> _load(String family, String path) async {
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await loader.load();
}

double _width(String text, String family) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: TextStyle(fontFamily: family, fontFamilyFallback: const [bundledFont], fontSize: 100)),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

void main() {
  setUpAll(() async {
    await _load(bundledFont, 'assets/fonts/NotoSansSC-Regular.ttf');
    await _load(quotesFont, 'assets/fonts/LumtubQuotes-Regular.ttf');
  });

  test('Western curly quotes are proportional, the rest still comes from the CJK face', () {
    expect(_width('’', bundledFont), closeTo(100, 1));
    expect(_width('’', quotesFont), closeTo(27.9, 1));
    expect(_width('“”', quotesFont), closeTo(95, 1));
    expect(_width('dall’attacca 中文', quotesFont), closeTo(_width('dall’attacca 中文', bundledFont) - 72.1, 1));
  });
}
