import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/feed_reason.dart';
import 'package:lumtub/ui/video_card.dart';

void main() {
  test('a reason keeps its kind and full text; one saved before kinds is text alone', () {
    final reason = FeedReason.of(ReasonKind.following, 'Associated Press you follow');
    expect(FeedReason.read(reason), (ReasonKind.following, 'Associated Press you follow'));
    expect(FeedReason.read('Recommended by YouTube'), (null, 'Recommended by YouTube'));
  });

  testWidgets('the tag shows the kind in a word, the full reason on hover', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: ReasonTag(FeedReason.of(ReasonKind.related, 'Viewers of "Identity" also watched'))))));
    expect(find.text('Related'), findsOneWidget);
    expect(find.byTooltip('Viewers of "Identity" also watched'), findsOneWidget);
  });
}
