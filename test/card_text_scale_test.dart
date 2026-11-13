import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/video_card.dart';

void main() {
  test('cards grow with the text size, so two title lines are never cut', () {
    final normal = gridLayoutFor(1200);
    final larger = gridLayoutFor(1200, textScale: 1.3);
    expect(larger.columns, normal.columns);
    // Two title lines of 14 px at 1.38 and the 24 px channel line.
    expect(larger.itemHeight - normal.itemHeight, closeTo((2 * 14 * 1.38 + 24) * 0.3, 1));
  });
}
