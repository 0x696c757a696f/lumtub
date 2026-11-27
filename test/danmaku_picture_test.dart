import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/danmaku_picture.dart';

void main() {
  test('only messages with emoji become pictures', () {
    expect(danmakuParts('just text 中文', const {}), isNull);
    expect(danmakuParts('hi :wave:', const {}), isNull, reason: 'a shortcut without a picture stays text');
    final parts = danmakuParts('hi :wave: there 😂👍🏽!', const {':wave:': 'https://example.com/wave.png'})!;
    expect(parts.map((p) => switch (p) { DanmakuText(:final text) => 'T($text)', DanmakuEmojiPicture(:final url) => 'P($url)', DanmakuEmojiGlyph(:final emoji) => 'E($emoji)' }), [
      'T(hi )',
      'P(https://example.com/wave.png)',
      'T( there )',
      'E(😂)',
      'E(👍🏽)',
      'T(!)',
    ]);
  });

  test('Unicode emoji YouTube sent pictures of are drawn from them, skin tones whole', () {
    final parts = danmakuParts('🫛 and 👍🏽 👍', const {'🫛': 'https://e/pea', '👍': 'https://e/up', '👍🏽': 'https://e/up-tone'})!;
    expect(parts.map((p) => switch (p) { DanmakuText(:final text) => 'T($text)', DanmakuEmojiPicture(:final url) => 'P($url)', DanmakuEmojiGlyph(:final emoji) => 'E($emoji)' }), [
      'P(https://e/pea)',
      'T( and )',
      'P(https://e/up-tone)',
      'T( )',
      'P(https://e/up)',
    ]);
  });

  testWidgets('a message is drawn as an outlined line as tall as its lane', (tester) async {
    final painter = DanmakuPainter(font: 'Noto Sans CJK SC', size: 52, opacity: 1);
    final parts = danmakuParts('ok 😂', const {})!;
    final units = painter.measure(parts, 1920, 1080);
    expect(units, greaterThan(52));
    Future<(int, int, Uint8List)> rgba(double osdHeight, bool paid) async {
      final (image, pad) = (await painter.image(parts, osdHeight: osdHeight, paid: paid))!;
      expect(pad, greaterThan(0));
      final data = (await image.toByteData())!;
      final size = (image.width, image.height);
      image.dispose();
      return (size.$1, size.$2, data.buffer.asUint8List());
    }

    final (width, height, pixels) = (await tester.runAsync(() => rgba(1080, false)))!;
    expect(height, (52 * 1.25).ceil());
    expect(width, greaterThanOrEqualTo(units.floor()));
    var white = 0, dark = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      if (pixels[i + 3] == 255 && pixels[i] > 240 && pixels[i + 1] > 240 && pixels[i + 2] > 240) white++;
      if (pixels[i + 3] > 40 && pixels[i] < 30 && pixels[i + 1] < 30 && pixels[i + 2] < 30) dark++;
    }
    expect(white, greaterThan(50), reason: 'the white fill');
    expect(dark, greaterThan(50), reason: 'the dark outline');
    // Twice the size for a picture 2160 pixels high.
    final (_, bigHeight, gold) = (await tester.runAsync(() => rgba(2160, true)))!;
    expect(bigHeight, (52 * 1.25 * 2).ceil());
    // Paid messages are gold (FFC838).
    var golden = 0;
    for (var i = 0; i < gold.length; i += 4) {
      if (gold[i + 3] == 255 && gold[i] > 230 && gold[i + 1] > 150 && gold[i + 2] < 100) golden++;
    }
    expect(golden, greaterThan(50));
  });
}
