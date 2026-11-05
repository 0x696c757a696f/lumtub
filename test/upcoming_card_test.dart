import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/ui/upcoming_card.dart';

void main() {
  test('counts down to the start', () {
    expect(startsIn(null), 'Starting soon');
    expect(startsIn(const Duration(seconds: -30)), 'Starting soon');
    expect(startsIn(const Duration(seconds: 42)), 'Starts in 42 s');
    expect(startsIn(const Duration(minutes: 12, seconds: 5)), 'Starts in 12 min 5 s');
    expect(startsIn(const Duration(hours: 2, minutes: 13, seconds: 50)), 'Starts in 2 h 13 min');
    expect(startsIn(const Duration(days: 3, hours: 4, minutes: 1)), 'Starts in 3 d 4 h');
  });

  test('details carry the scheduled start of an upcoming stream only', () {
    final upcoming = VideoDetails.fromJson({'title': 't', 'live_status': 'is_upcoming', 'release_timestamp': 1761580800});
    expect(upcoming.scheduledStart, DateTime.fromMillisecondsSinceEpoch(1761580800 * 1000));
    expect(upcoming.localized('其他标题', '').scheduledStart, upcoming.scheduledStart);
    expect(VideoDetails.fromJson({'title': 't', 'live_status': 'was_live', 'release_timestamp': 1761580800}).scheduledStart, isNull);
  });

  testWidgets('shows the countdown and the start time over the player', (tester) async {
    var retried = 0;
    final start = DateTime.now().add(const Duration(hours: 2, minutes: 5, seconds: 30));
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 640,
          height: 360,
          child: UpcomingCard(thumbnail: MemoryImage(kTransparentPng), start: start, onRetry: () => retried++),
        ),
      ),
    ));
    expect(find.text('Upcoming live'), findsOneWidget);
    expect(find.text('Starts in 2 h 5 min'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Starts (?!in )')), findsOneWidget);
    await tester.tap(find.text('Try now'));
    expect(retried, 1);
    await tester.pumpWidget(const SizedBox());
  });
}

final kTransparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
