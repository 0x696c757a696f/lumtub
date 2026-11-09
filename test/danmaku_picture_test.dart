import 'dart:ffi' hide Size;
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

  test("Unicode emoji YouTube sent pictures of are drawn from them, skin tones whole", () {
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
    final bitmap = (await tester.runAsync(() => painter.draw(parts, osdHeight: 1080, paid: false)))!;
    addTearDown(bitmap.free);
    expect(bitmap.height, (52 * 1.25).ceil());
    expect(bitmap.width, greaterThanOrEqualTo(units.floor()));
    final pixels = bitmap.pixels.asTypedList(bitmap.width * bitmap.height * 4);
    var white = 0, dark = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      if (pixels[i + 3] == 255 && pixels[i] > 240 && pixels[i + 1] > 240 && pixels[i + 2] > 240) white++;
      if (pixels[i + 3] > 40 && pixels[i] < 30 && pixels[i + 1] < 30 && pixels[i + 2] < 30) dark++;
    }
    expect(white, greaterThan(50), reason: 'the white fill');
    expect(dark, greaterThan(50), reason: 'the dark outline');
    // Twice the size for a 2160-line OSD.
    final big = (await tester.runAsync(() => painter.draw(parts, osdHeight: 2160, paid: true)))!;
    addTearDown(big.free);
    expect(big.height, (52 * 1.25 * 2).ceil());
  });
}
