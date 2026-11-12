import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/player_settings.dart';
import 'package:lumtub/ui/common.dart';
import 'package:lumtub/ui/pages/watch_page.dart';
import 'package:lumtub/ui/video_card.dart';

void main() {
  testWidgets("a phone's title folds to two lines, and 更多 holds the other actions", (tester) async {
    debugTouchFirst = true;
    addTearDown(() => debugTouchFirst = null);
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const title = 'A long title that goes on and on about what the video is, more than two lines on a phone held upright for sure';
    final controller = AppController()
      ..ready = true
      ..playing = const VideoItem(id: 'abcdefghijk', title: title, channel: 'Channel', url: 'https://www.youtube.com/watch?v=abcdefghijk', viewCount: 232000);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VideoActions(controller: controller, child: debugPhoneIntro(controller)))));
    Text titleText() => tester.widget<Text>(find.text(title));
    expect(titleText().maxLines, 2);
    await tester.tap(find.text(title));
    await tester.pump();
    expect(titleText().maxLines, isNull);
    expect(find.text('Like'), findsOneWidget);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Open in browser'), findsOneWidget);
    for (final order in PlayOrder.values) {
      expect(find.text(order.label), findsWidgets);
    }
  });
}
