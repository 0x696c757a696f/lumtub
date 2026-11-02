import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/danmaku.dart';

void main() {
  test('danmaku settings come back as saved, within their ranges', () {
    const set = DanmakuSettings(enabled: true, opacity: 0.6, size: 50, seconds: 10, area: 1, paid: false);
    expect(DanmakuSettings.fromJson(jsonDecode(jsonEncode(set.toJson()))), set);
    final wild = DanmakuSettings.fromJson({'opacity': 5, 'size': 1, 'seconds': 100, 'area': 0});
    expect((wild.opacity, wild.size, wild.seconds, wild.area), (1.0, 24.0, 16.0, 0.25));
    expect(DanmakuSettings.fromJson(null), const DanmakuSettings());
  });

  test('the layout gets its settings in the names lumtub_core reads', () {
    final json = jsonDecode(const DanmakuSettings(seconds: 6).layoutJson) as Map;
    expect(json['duration_ms'], 6000);
    expect(json.keys, containsAll(['font_size', 'area', 'opacity']));
  });
}
