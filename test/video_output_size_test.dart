import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/video_output_size.dart';

void main() {
  test('fits the video into the largest box, never above its own size', () {
    const video = Size(3840, 2160);
    expect(VideoOutputSize.target(video, const [Size(1240, 698), Size(320, 180)]), (1240, 698));
    expect(VideoOutputSize.target(video, const [Size(1000, 1000)]), (1000, 562));
    expect(VideoOutputSize.target(video, const [Size(3840, 2400)]), isNull);
    expect(VideoOutputSize.target(video, const []), isNull);
    expect(VideoOutputSize.target(Size.zero, const [Size(100, 100)]), isNull);
  });

  test('covers the box when the picture is zoomed or stretched', () {
    final (w, h) = VideoOutputSize.target(const Size(1920, 800), const [Size(1280, 720)], cover: true)!;
    expect(h, greaterThanOrEqualTo(720));
    expect(w / h, closeTo(1920 / 800, 0.01));
    expect(VideoOutputSize.target(const Size(1280, 720), const [Size(1920, 1080)], cover: true), isNull);
  });

  test('applies the size once things settle, and the video size when hidden', () async {
    final applied = <(int?, int?)>[];
    final size = VideoOutputSize((w, h) async => applied.add((w, h)), delay: const Duration(milliseconds: 10));
    Future<void> settle() => Future.delayed(const Duration(milliseconds: 50));
    final page = Object();
    size.video = const Size(3840, 2160);
    size.show(page, const Size(800, 600));
    size.show(page, const Size(1280, 720));
    await settle();
    expect(applied, [(1280, 720)]);
    size.show(page, const Size(1280, 720));
    await settle();
    expect(applied, [(1280, 720)]);
    size.hide(page);
    await settle();
    expect(applied, [(1280, 720), (null, null)]);
  });
}
