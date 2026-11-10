import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/timestamp_link.dart';

void main() {
  test('links to the current second', () {
    expect(timestampLink('dQw4w9WgXcQ', const Duration(seconds: 83, milliseconds: 900)), 'https://youtu.be/dQw4w9WgXcQ?t=83');
    expect(timestampLink('dQw4w9WgXcQ', const Duration(hours: 1, seconds: 5)), 'https://youtu.be/dQw4w9WgXcQ?t=3605');
  });

  test('gives no link at the start, for live streams or other ids', () {
    expect(timestampLink('dQw4w9WgXcQ', Duration.zero), isNull);
    expect(timestampLink('dQw4w9WgXcQ', const Duration(milliseconds: 900)), isNull);
    expect(timestampLink('dQw4w9WgXcQ', const Duration(seconds: 30), live: true), isNull);
    expect(timestampLink('local-file', const Duration(seconds: 30)), isNull);
  });
}
