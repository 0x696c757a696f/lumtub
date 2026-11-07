import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/pages/watch_page.dart';

void main() {
  test('small windows get subtitles in proportion, readable and not oversized', () {
    double px(double width, double height) => 32 * smallSubtitleScale(Size(width, height));
    expect(px(320, 180), 13, reason: 'a tiny window keeps a readable size');
    expect(px(640, 360), closeTo(19.8, 0.01));
    expect(px(1280, 720), 32, reason: 'never past the full-size text');
    expect(px(1920, 1080), 32);
  });
}
