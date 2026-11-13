import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
  await tester.pumpAndSettle();
}

void _expectSelectedInside(WidgetTester tester, double width) {
  final box = tester.getRect(find.text('Frontier research'));
  expect(box.left, greaterThanOrEqualTo(0));
  expect(box.right, lessThanOrEqualTo(width));
}

void main() {
  setUpAll(() async {
    // A real face, so labels measure as they do in the app.
    final bytes = File('assets/fonts/NotoSansSC-Regular.ttf').readAsBytesSync();
    await (FontLoader('Segments Sans')..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  for (final width in [720.0, 800.0, 960.0, 1000.0, 1280.0]) {
    testWidgets('at $width wide every tab is shown whole, without scrolling', (tester) async {
      await _show(tester, width);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(tester.takeException(), isNull);
      for (final tab in _tabs) {
        final rect = tester.getRect(find.text(tab));
        expect(rect.right, lessThanOrEqualTo(width - 16), reason: tab);
        expect(tester.renderObject<RenderParagraph>(find.text(tab)).didExceedMaxLines, isFalse, reason: tab);
      }
    });
  }

  for (final width in [360.0, 600.0]) {
    testWidgets('at $width wide the row scrolls to the selected tab', (tester) async {
      await _show(tester, width);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
      _expectSelectedInside(tester, width);
    });
  }
}
