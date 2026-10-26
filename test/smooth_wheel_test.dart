import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/appearance_settings.dart';
import 'package:lumtub/ui/motion.dart';
import 'package:lumtub/ui/smooth_wheel.dart';

void main() {
  ui.PointerDataPacket wheel(double dy, {ui.PointerDeviceKind kind = ui.PointerDeviceKind.mouse, int at = 1000}) => ui.PointerDataPacket(data: [
        ui.PointerData(timeStamp: Duration(milliseconds: at), change: ui.PointerChange.hover, kind: kind, signalKind: ui.PointerSignalKind.scroll, physicalX: 10, physicalY: 20, scrollDeltaY: dy),
      ]);
  double sum(List<ui.PointerDataPacket> sent) => sent.expand((p) => p.data).fold(0.0, (total, d) => total + d.scrollDeltaY);
  bool followUp(ui.PointerData d) => SmoothWheel.isFollowUp(PointerScrollEvent(timeStamp: d.timeStamp, scrollDelta: Offset(0, d.scrollDeltaY)));

  testWidgets('a notch glides in pieces that add up to it', (tester) async {
    final sent = <ui.PointerDataPacket>[];
    final wheel_ = SmoothWheel.to(sent.add);
    wheel_.receive(wheel(120));
    expect(sent, hasLength(1));
    expect(sent.single.data.single.scrollDeltaY, inExclusiveRange(0, 60));
    expect(followUp(sent.single.data.single), isFalse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(sent.length, greaterThan(2));
    expect(sum(sent), closeTo(120, 0.001));
    expect(sent.skip(1).every((p) => followUp(p.data.single)), isTrue);
    expect(sent.every((p) => p.data.single.physicalX == 10 && p.data.single.physicalY == 20), isTrue);
  });

  testWidgets('a notch during a glide adds to what is left; turning back drops it', (tester) async {
    final sent = <ui.PointerDataPacket>[];
    final smooth = SmoothWheel.to(sent.add);
    smooth.receive(wheel(100));
    await tester.pump(const Duration(milliseconds: 50));
    smooth.receive(wheel(100, at: 1050));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(sum(sent), closeTo(200, 0.001));
    expect(sent.where((p) => !followUp(p.data.single)), hasLength(2));

    sent.clear();
    smooth.receive(wheel(100, at: 2000));
    await tester.pump(const Duration(milliseconds: 50));
    final before = sum(sent);
    smooth.receive(wheel(-100, at: 2050));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(sum(sent), closeTo(before - 100, 0.001));
  });

  testWidgets('touchpads and reduced motion pass straight through', (tester) async {
    final sent = <ui.PointerDataPacket>[];
    final smooth = SmoothWheel.to(sent.add);
    smooth.receive(wheel(120, kind: ui.PointerDeviceKind.trackpad));
    expect(sum(sent), 120);
    Motion.update(MotionPreference.reduced);
    sent.clear();
    smooth.receive(wheel(120));
    expect(sum(sent), 120);
    Motion.update(MotionPreference.full);
  });

  testWidgets('a list scrolls smoothly by the notch', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(home: ListView(controller: controller, children: [for (var i = 0; i < 100; i++) SizedBox(height: 50, child: Text('$i'))])));
    final dispatcher = tester.binding.platformDispatcher;
    final smooth = SmoothWheel.to(dispatcher.onPointerDataPacket!);
    final ratio = tester.view.devicePixelRatio;
    smooth.receive(ui.PointerDataPacket(data: [
      ui.PointerData(viewId: tester.view.viewId, change: ui.PointerChange.hover, kind: ui.PointerDeviceKind.mouse, signalKind: ui.PointerSignalKind.scroll, physicalX: 100 * ratio, physicalY: 100 * ratio, scrollDeltaY: 120 * ratio),
    ]));
    await tester.pump();
    expect(controller.offset, inExclusiveRange(0, 60));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, closeTo(120, 0.01));
  });
}
