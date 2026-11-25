import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/danmaku.dart';

void main() {
  test('danmaku settings come back as saved, within their ranges', () {
    const set = DanmakuSettings(enabled: true, opacity: 0.6, size: 50, seconds: 10, area: 1, paid: false);
    expect(DanmakuSettings.fromJson(jsonDecode(jsonEncode(set.toJson()))), set);
    final wild = DanmakuSettings.fromJson({'opacity': 5, 'size': 1, 'seconds': 100, 'area': 0, 'version': 2});
    expect((wild.opacity, wild.size, wild.seconds, wild.area), (1.0, 24.0, 20.0, 0.25));
    expect(DanmakuSettings.fromJson(null), const DanmakuSettings());
    expect(DanmakuSettings.fromJson({'enabled': true, 'seconds': 8}).seconds, 16, reason: 'the old, too fast default is not kept');
    expect(DanmakuSettings.fromJson({'seconds': 12, 'version': 3}).seconds, 16, reason: 'nor the 12 s one after it');
    expect(DanmakuSettings.fromJson({'seconds': 10, 'version': 3}).seconds, 10, reason: 'a speed someone chose is kept');
    expect(DanmakuSettings.fromJson({'seconds': 12, 'version': 4}).seconds, 12);
    expect(DanmakuSettings.fromJson({'size': 44, 'version': 2}).size, 52, reason: 'the old, too small default is not kept');
    expect(DanmakuSettings.fromJson({'size': 60, 'version': 2}).size, 60, reason: 'a size someone chose is kept');
    expect(DanmakuSettings.fromJson({'size': 90, 'version': 3}).size, 90);
  });

  test('the layout gets its settings in the names lumtub_core reads', () {
    final json = jsonDecode(const DanmakuSettings(seconds: 6).layoutJson) as Map;
    expect(json['duration_ms'], 6000);
    expect(json.keys, containsAll(['font_size', 'area', 'opacity', 'font']));
  });

  test('a live batch keeps the gaps its messages were sent with', () {
    final timing = LiveDanmakuTiming();
    // Fetched at wall 10 000 ms, clock 0: sent 4 s, 2 s and 1 s earlier.
    final first = timing.starts([6000000, 8000000, 9000000], 0, 10000);
    expect(first[1] - first[0], 2000);
    expect(first[2] - first[1], 1000);
    expect(first.every((t) => t >= 0), isTrue);
    // The next fetch 4 s later: still in order after the first batch.
    final next = timing.starts([12000000], 4000, 14000).single;
    expect(next, greaterThan(first.last));
    expect(next - first.last, 3000);
    // Far too late, or without a time: at once.
    expect(timing.starts([1000, null], 5000, 60000), [5000, 5000]);
  });

  test('the replay clock moves evenly between mpv\'s position reports', () {
    var wall = 0.0;
    final clock = ReplayClock(elapsedMs: () => wall);
    // mpv reports every 100 ms, a little late or early; frames every 1/60 s.
    var reported = 10000.0;
    var last = clock.at(reported, playing: true, rate: 1);
    expect(last, 10000);
    final steps = <double>[];
    for (var frame = 1; frame <= 600; frame++) {
      wall = frame * 1000 / 60;
      if (frame % 6 == 0) reported = 10000 + wall + (frame % 12 == 0 ? 20 : -20);
      final shown = clock.at(reported, playing: true, rate: 1);
      steps.add(shown - last);
      last = shown;
    }
    expect(steps.every((step) => step > 0), isTrue, reason: 'never still, never back');
    final after = steps.skip(60);
    expect(after.reduce(math.max) - after.reduce(math.min), lessThan(12), reason: 'steps of about one frame each');
    expect((last - (10000 + wall)).abs(), lessThan(40), reason: 'it keeps with the video');
  });

  test('the replay clock jumps on a seek and stands still while paused', () {
    var wall = 0.0;
    final clock = ReplayClock(elapsedMs: () => wall);
    clock.at(5000, playing: true, rate: 1);
    wall = 100;
    expect(clock.at(60000, playing: true, rate: 1), 60000);
    wall = 200;
    expect(clock.at(60000, playing: true, rate: 1), closeTo(60100, 1));
    wall = 300;
    expect(clock.at(60150, playing: false, rate: 1), 60150);
    wall = 900;
    expect(clock.at(60150, playing: false, rate: 1), 60150);
    wall = 1000;
    expect(clock.at(60150, playing: true, rate: 2), 60150);
    wall = 1100;
    expect(clock.at(60150, playing: true, rate: 2), closeTo(60350, 1), reason: 'at twice the speed');
  });
}
