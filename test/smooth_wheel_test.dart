import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/appearance_settings.dart';
import 'package:lumtub/ui/motion.dart';
import 'package:lumtub/ui/smooth_wheel.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Widget list(ScrollController controller, {int count = 100, Widget? rail}) => MaterialApp(
        home: SmoothWheel(
          child: ListView(controller: controller, children: [
            if (rail != null) rail,
            for (var i = 0; i < count; i++) SizedBox(height: 50, child: Text('$i')),
          ]),
        ),
      );

  Future<void> wheel(WidgetTester tester, Offset delta, {Offset at = const Offset(100, 300), PointerDeviceKind kind = PointerDeviceKind.mouse}) async {
    final pointer = TestPointer(1, kind);
    await tester.sendEventToBinding(pointer.hover(at));
    await tester.sendEventToBinding(pointer.scroll(delta));
  }

  testWidgets('a wheel notch eases the list to where it sends it', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(list(controller));
    await wheel(tester, const Offset(0, 120));
    expect(controller.offset, 0);
    final seen = <double>[];
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(controller.offset);
    }
    expect(seen.first, lessThan(120));
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
    expect(seen.where((o) => o > 0 && o < 120).length, greaterThan(3));
    expect(controller.offset, 120);
  });

  testWidgets('notches in a row add up rather than start over', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(list(controller));
    await wheel(tester, const Offset(0, 100));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 50));
    final midway = controller.offset;
    expect(midway, inExclusiveRange(0, 100));
    await wheel(tester, const Offset(0, 100));
    expect(controller.offset, midway);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.offset, greaterThan(midway));
    await wheel(tester, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(controller.offset, 300);

    // Turning back starts from where the list is.
    await wheel(tester, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(controller.offset, 200);
  });

  testWidgets('stops at the ends', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(list(controller, count: 20));
    final end = controller.position.maxScrollExtent;
    for (var i = 0; i < 5; i++) {
      await wheel(tester, const Offset(0, 200));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(controller.offset, end);
    await wheel(tester, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('touchpads, and 减少动画 chosen in Lumtub, move at once', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(list(controller));
    await wheel(tester, const Offset(0, 120), kind: PointerDeviceKind.trackpad);
    await tester.pump();
    expect(controller.offset, 120);

    SmoothWheel.enabled = false;
    addTearDown(() => SmoothWheel.enabled = true);
    await wheel(tester, const Offset(0, 120));
    await tester.pump();
    expect(controller.offset, 240);
  });

  testWidgets("glides in 低占用模式 and with the system's reduced animations", (tester) async {
    final controller = ScrollController();
    Motion.update(MotionPreference.reduced);
    addTearDown(() => Motion.update(MotionPreference.full));
    await tester.pumpWidget(list(controller));
    await wheel(tester, const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.offset, inExclusiveRange(0, 120));
    await tester.pumpAndSettle();
    expect(controller.offset, 120);
  });

  testWidgets('a late frame shows the list where it should be by then', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(list(controller));
    await wheel(tester, const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 16));
    // One frame 300 ms late: the glide is over by then.
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.offset, 120);
    await tester.pumpAndSettle();
    expect(controller.offset, 120);
  });

  testWidgets('a quick spin keeps its pace: no step jumps far ahead of the last', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(list(controller, count: 400));
    final steps = <double>[];
    var last = 0.0;
    for (var notch = 0; notch < 8; notch++) {
      await wheel(tester, const Offset(0, 100));
      for (var f = 0; f < 3; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        steps.add(controller.offset - last);
        last = controller.offset;
      }
    }
    await tester.pumpAndSettle();
    expect(controller.offset, 800);
    // After the first notch, a notch carries on at the speed the list has
    // rather than surging: each frame's step stays near the one before.
    for (var i = 4; i < steps.length; i++) {
      expect(steps[i], lessThan(steps[i - 1] * 1.6 + 2), reason: 'steps $steps');
      expect(steps[i], greaterThan(0));
    }
  });

  testWidgets('a sideways row inside the page eases on its own', (tester) async {
    final page = ScrollController();
    final row = ScrollController();
    final rail = SizedBox(
      height: 100,
      child: ListView(controller: row, scrollDirection: Axis.horizontal, children: [for (var i = 0; i < 30; i++) SizedBox(width: 100, child: Text('r$i'))]),
    );
    await tester.pumpWidget(list(page, rail: rail));
    await wheel(tester, const Offset(150, 0), at: const Offset(100, 50));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 50));
    expect(row.offset, inExclusiveRange(0, 150));
    await tester.pumpAndSettle();
    expect(row.offset, 150);
    expect(page.offset, 0);

    // With shift held a vertical notch goes sideways.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await wheel(tester, const Offset(0, 100), at: const Offset(100, 10));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 50));
    expect(row.offset, inExclusiveRange(150, 250));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(row.offset, 250);
    expect(page.offset, 0);

    // A vertical notch over the row still scrolls the page.
    await wheel(tester, const Offset(0, 100), at: const Offset(100, 50));
    await tester.pumpAndSettle();
    expect(page.offset, 100);
    expect(row.offset, 250);
  });
}
