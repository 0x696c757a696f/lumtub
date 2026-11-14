import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/chip_strip.dart';
import 'package:lumtub/ui/fitting_segments.dart';

const _tabs = ['Humanities', 'Social sciences', 'Natural sciences', 'Engineering & technology', 'Medicine', 'Frontier research'];

Future<void> _show(WidgetTester tester, double width, {String selected = 'Frontier research'}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(fontFamily: 'Segments Sans'),
    home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: FittingSegments<String>(values: _tabs, label: (s) => s, selected: selected, onSelected: (_) {}))),
  ));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _expectWhole(WidgetTester tester, String tab, double width) {
  final rect = tester.getRect(find.text(tab));
  expect(rect.left, greaterThanOrEqualTo(0), reason: tab);
  expect(rect.right, lessThanOrEqualTo(width), reason: tab);
  final paragraph = tester.renderObject<RenderParagraph>(find.text(tab));
  expect(paragraph.didExceedMaxLines, isFalse, reason: tab);
  expect(paragraph.size.height, lessThan(30), reason: '$tab on one line');
}

void main() {
  setUpAll(() async {
    // A real face, so labels measure as they do in the app.
    final bytes = File('assets/fonts/NotoSansSC-Regular.ttf').readAsBytesSync();
    await (FontLoader('Segments Sans')..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  testWidgets('a wide window shows one segment per tab, every label whole on one line', (tester) async {
    await _show(tester, 1280);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final tab in _tabs) {
      _expectWhole(tester, tab, 1280 - 16);
    }
  });

  for (final width in [360.0, 600.0, 1000.0]) {
    testWidgets('at $width wide the tabs scroll as text, the selected one in view', (tester) async {
      await _show(tester, width);
      expect(find.byType(SegmentedButton<String>), findsNothing);
      expect(find.byType(ChipStrip), findsOneWidget);
      expect(tester.takeException(), isNull);
      _expectWhole(tester, 'Frontier research', width);
    });
  }
}
