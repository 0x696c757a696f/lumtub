import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/danmaku.dart';

void main() {
  test('danmaku settings come back as saved, within their ranges', () {
    const set = DanmakuSettings(enabled: true, opacity: 0.6, size: 50, seconds: 10, area: 1, paid: false);
    expect(DanmakuSettings.fromJson(jsonDecode(jsonEncode(set.toJson()))), set);
    final wild = DanmakuSettings.fromJson({'opacity': 5, 'size': 1, 'seconds': 100, 'area': 0, 'version': 2});
    expect((wild.opacity, wild.size, wild.seconds, wild.area), (1.0, 24.0, 20.0, 0.25));
    expect(DanmakuSettings.fromJson(null), const DanmakuSettings());
    expect(DanmakuSettings.fromJson({'enabled': true, 'seconds': 8}).seconds, 12, reason: 'the old, too fast default is not kept');
  });

  test('the layout gets its settings in the names lumtub_core reads', () {
    final json = jsonDecode(const DanmakuSettings(seconds: 6).layoutJson) as Map;
    expect(json['duration_ms'], 6000);
    expect(json.keys, containsAll(['font_size', 'area', 'opacity']));
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
}
