import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/video_card.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<TestGesture> hover(WidgetTester tester, String text, double width) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
            child: SizedBox(
                width: width,
                child: TitleText(text, maxLines: 2, style: const TextStyle(fontSize: 14)))),
      ),
    ));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(TitleText)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return mouse;
  }

  testWidgets('a cut title shows itself whole on hover', (tester) async {
    final long = List.filled(40, 'word').join(' ');
    final mouse = await hover(tester, long, 120);
    expect(find.byType(Tooltip), findsOneWidget);
    expect(find.text(long), findsNWidgets(2));
    await mouse.removePointer();
  });

  testWidgets('a title that fits gets no tooltip', (tester) async {
    final mouse = await hover(tester, 'Short', 400);
    expect(find.text('Short'), findsOneWidget);
    await mouse.removePointer();
  });

  testWidgets('a long press on a cut title opens nothing', (tester) async {
    final long = List.filled(40, 'word').join(' ');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Center(
              child: SizedBox(
                  width: 120,
                  child: TitleText(long, maxLines: 2, style: const TextStyle(fontSize: 14))))),
    ));
    await tester.longPress(find.byType(TitleText));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(long), findsOneWidget);
  });
}
