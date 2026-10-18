import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/main.dart';

void main() {
  testWidgets('shows component setup before the player is ready', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const YtPlusApp());
    expect(find.text('YTPlus'), findsOneWidget);
    expect(find.text('观看历史'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
