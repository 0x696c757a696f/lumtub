import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/appearance_settings.dart';
import 'package:lumtub/ui/video_card.dart';

void main() {
  tearDown(() => compactCards = false);

  test('compact mode puts two cards in a row on a phone', () {
    for (final width in [320.0, 360.0, 390.0, 412.0]) {
      compactCards = false;
      expect(gridLayoutFor(width - 32).columns, 1, reason: '$width');
      compactCards = true;
      expect(gridLayoutFor(width - 32).columns, 2, reason: '$width');
    }
  });

  test('compact mode on a wide window keeps its own card width', () {
    compactCards = true;
    expect(gridLayoutFor(1200).columns, ((1200 + gridGap) / (videoCardMinWidth * 0.8 + gridGap)).floor());
  });
}
