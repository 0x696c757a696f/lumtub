import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/ui/common.dart';

void main() {
  test('how long ago reads like YouTube', () {
    final now = DateTime(2026, 11, 10, 12);
    expect(formatAgo(now.subtract(const Duration(seconds: 20)), now: now), 'Just now');
    expect(formatAgo(now.subtract(const Duration(minutes: 1)), now: now), '1 minute ago');
    expect(formatAgo(now.subtract(const Duration(hours: 5)), now: now), '5 hours ago');
    expect(formatAgo(now.subtract(const Duration(days: 3)), now: now), '3 days ago');
    expect(formatAgo(now.subtract(const Duration(days: 14)), now: now), '2 weeks ago');
    expect(formatAgo(now.subtract(const Duration(days: 30)), now: now), '1 month ago');
    expect(formatAgo(now.subtract(const Duration(days: 365 * 15)), now: now), '15 years ago');
  });

  test('a listed video takes its approximate time, an upcoming one does not', () {
    final listed = VideoItem.fromJson({'id': 'abcdefghijk', 'title': 'A', 'timestamp': 1_700_000_000});
    expect(listed.published, DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000, isUtc: true).toLocal());
    final upcoming = VideoItem.fromJson({'id': 'abcdefghijk', 'title': 'A', 'timestamp': 1_700_000_000, 'live_status': 'is_upcoming'});
    expect(upcoming.published, isNull);
    final saved = VideoItem.fromJson({'id': 'abcdefghijk', 'title': 'A', 'published': '2026-01-02T03:04:05Z', 'timestamp': 1});
    expect(saved.published, DateTime.utc(2026, 1, 2, 3, 4, 5));
  });
}
