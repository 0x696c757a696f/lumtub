import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/appearance_settings.dart';

void main() {
  testWidgets('invisible characters in names take no room and draw nothing', (tester) async {
    final loader = FontLoader(blankFont)..addFont(Future.value(ByteData.sublistView(File('assets/fonts/LumtubBlank-Regular.ttf').readAsBytesSync())));
    await loader.load();
    double width(String text) {
      final painter = TextPainter(text: TextSpan(text: text, style: const TextStyle(fontFamily: blankFont, fontSize: 20)), textDirection: TextDirection.ltr)..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    // A Hangul filler, as Korean channel names start with, a zero-width
    // space, an invisible separator and a byte order mark.
    for (final c in ['ㅤ', '​', '⁣', '﻿', 'ᅟ']) {
      expect(width(c), lessThan(0.01), reason: 'U+${c.codeUnitAt(0).toRadixString(16)}');
    }
    // Loading a font tells the text to lay out again on a later frame.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  });
}
