import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/ui/video_card.dart';

void main() {
  test('thumbnails decode at the card size, in steps, between 160 and 480', () {
    expect(thumbnailDecodeWidth(300, 1), 320);
    expect(thumbnailDecodeWidth(301, 1), 320);
    expect(thumbnailDecodeWidth(300, 1.25), 400);
    expect(thumbnailDecodeWidth(100, 1), 160);
    expect(thumbnailDecodeWidth(600, 2), 480);
  });

  test('a larger thumbnail size chosen in Settings decodes larger', () {
    final before = VideoItem.thumbnailFile;
    addTearDown(() => VideoItem.thumbnailFile = before);
    VideoItem.thumbnailFile = 'maxresdefault';
    expect(thumbnailDecodeWidth(600, 2), 1200);
    expect(thumbnailDecodeWidth(900, 2), 1280);
    expect(thumbnailDecodeWidth(600, 2, largest: 480), 480);
    VideoItem.thumbnailFile = 'mqdefault';
    expect(thumbnailDecodeWidth(600, 2), 320);
  });
}
