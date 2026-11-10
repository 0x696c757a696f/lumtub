import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/skip_silence.dart';

void main() {
  test('silence raises the speed and its end restores the chosen one', () {
    final s = SilenceSkipper()..enable(1.5);
    expect(s.onMetadata('{"lavfi.silence_start":"3.2"}'), 4.0);
    expect(s.boosted, isTrue);
    expect(s.onMetadata('{"lavfi.silence_start":"3.2"}'), isNull);
    expect(s.onMetadata('{"lavfi.silence_end":"5.0","lavfi.silence_duration":"1.8"}'), 1.5);
    expect(s.boosted, isFalse);
    expect(s.onMetadata('{"lavfi.silence_end":"5.0"}'), isNull);
  });

  test('plain listings and unrelated metadata', () {
    final s = SilenceSkipper()..enable(1.0);
    expect(s.onMetadata(''), isNull);
    expect(s.onMetadata('{}'), isNull);
    expect(s.onMetadata('lavfi.silence_start=1.0'), 4.0);
    expect(s.onMetadata('lavfi.silence_end=2.0'), 1.0);
  });

  test('does nothing when disabled or already at least as fast', () {
    final off = SilenceSkipper();
    expect(off.onMetadata('lavfi.silence_start=1'), isNull);
    final fast = SilenceSkipper()..enable(4.0);
    expect(fast.onMetadata('lavfi.silence_start=1'), isNull);
  });

  test('disabling during silence gives the chosen speed back', () {
    final s = SilenceSkipper()..enable(2.0);
    s.onMetadata('lavfi.silence_start=1');
    expect(s.disable(), 2.0);
    expect(s.enabled, isFalse);
    expect(s.disable(), isNull);
    expect(s.onMetadata('lavfi.silence_start=1'), isNull);
  });

  test("its own speed changes are not the viewer's", () {
    final s = SilenceSkipper()..enable(1.25);
    s.onMetadata('lavfi.silence_start=1');
    expect(s.observeRate(4.0), isFalse);
    s.onMetadata('lavfi.silence_end=2');
    expect(s.observeRate(4.0), isFalse);
    expect(s.observeRate(1.25), isTrue);
    expect(s.userRate, 1.25);
  });

  test('a speed chosen during silence replaces the one to return to', () {
    final s = SilenceSkipper()..enable(1.0);
    s.onMetadata('lavfi.silence_start=1');
    expect(s.observeRate(2.0), isTrue);
    expect(s.userRate, 2.0);
    expect(s.boosted, isFalse);
    expect(s.onMetadata('lavfi.silence_end=2'), isNull);
  });

  test("a new video starts out of silence; speeds are the viewer's while off", () {
    final s = SilenceSkipper()..enable(1.0);
    s.onMetadata('lavfi.silence_start=1');
    s.reset(1.75);
    expect(s.boosted, isFalse);
    expect(s.userRate, 1.75);
    final off = SilenceSkipper();
    expect(off.observeRate(4.0), isTrue);
    expect(off.userRate, 4.0);
  });

  test('the filter is labelled for af add and af-metadata', () {
    expect(SilenceSkipper.filter, '@lumtub_silence:lavfi=[silencedetect=n=-30dB:d=0.5]');
    expect(SilenceSkipper.property, 'af-metadata/lumtub_silence');
  });
}
