import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/frame_pressure.dart';
import 'package:lumtub/ui/motion.dart';

void main() {
  tearDown(FramePressure.reset);

  test('a few late frames change nothing; many in a row draw lighter', () {
    for (var i = 0; i < FramePressure.window; i++) {
      FramePressure.add(i % 10 == 0);
    }
    expect(FramePressure.on, isFalse);
    expect(Motion.of(const Duration(milliseconds: 200)), const Duration(milliseconds: 200));
    for (var i = 0; i < FramePressure.strainedAt; i++) {
      FramePressure.add(true);
    }
    expect(FramePressure.on, isTrue);
    expect(Motion.of(const Duration(milliseconds: 200)), Duration.zero);
  });

  test('stays on while frames are late, and for a while after', () {
    for (var i = 0; i < FramePressure.window; i++) {
      FramePressure.add(true);
    }
    expect(FramePressure.on, isTrue);
    // On time again at once: still held, so it does not flicker.
    for (var i = 0; i < FramePressure.window; i++) {
      FramePressure.add(false);
    }
    expect(FramePressure.on, isTrue);
  });
}
