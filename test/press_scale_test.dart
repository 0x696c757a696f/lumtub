import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/motion.dart';
import 'package:lumtub/ui/press_scale.dart';

void main() {
  tearDown(() => Motion.reduced = false);

  const card = ValueKey('card');
  var builds = 0;
  var taps = 0;
  var longPresses = 0;

  Widget app() => MaterialApp(
        home: Center(
          child: PressScale(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              onLongPress: () => longPresses++,
              child: Builder(builder: (context) {
                builds++;
                return const SizedBox(key: card, width: 200, height: 100);
              }),
            ),
          ),
        ),
      );

  setUp(() {
    builds = 0;
    taps = 0;
    longPresses = 0;
  });

  double width(WidgetTester tester) => tester.getRect(find.byKey(card)).width;

  testWidgets('sinks while held and springs back on release, without building the card again', (tester) async {
    await tester.pumpWidget(app());
    expect(width(tester), 200);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(card)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(width(tester), lessThan(200));
    expect(width(tester), greaterThan(200 * PressScale.scale));
    await tester.pump(Ease.press);
    expect(width(tester), closeTo(200 * PressScale.scale, 0.01));

    await gesture.up();
    await tester.pump();
    await tester.pump(Ease.press);
    expect(width(tester), 200);
    expect(taps, 1);
    expect(builds, 1);
  });

  testWidgets('a long press still reaches the card, and a drag lets go', (tester) async {
    await tester.pumpWidget(app());
    final long = await tester.startGesture(tester.getCenter(find.byKey(card)));
    await tester.pump();
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(longPresses, 1);
    expect(width(tester), closeTo(200 * PressScale.scale, 0.01));
    await long.up();
    await tester.pumpAndSettle();
    expect(taps, 0);

    final drag = await tester.startGesture(tester.getCenter(find.byKey(card)));
    await tester.pump();
    await tester.pump(Ease.press);
    expect(width(tester), lessThan(200));
    await drag.moveBy(const Offset(0, 40));
    await tester.pump();
    await tester.pump(Ease.press);
    expect(width(tester), 200);
    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets('stays still with animations reduced', (tester) async {
    Motion.reduced = true;
    await tester.pumpWidget(app());
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(card)));
    await tester.pump();
    await tester.pump(Ease.press);
    expect(width(tester), 200);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
