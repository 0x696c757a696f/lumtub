import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/app/app_controller.dart';
import 'package:ytplus/app/home_feed.dart';
import 'package:ytplus/models.dart';
import 'package:ytplus/recommendations.dart';
import 'package:ytplus/ui/pages/video_pages.dart';
import 'package:ytplus/ui/video_card.dart';

void main() {
  testWidgets('home shows 为你推荐 with 换一批', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final feed = HomeFeed(NotInterested(null));
    await feed.refresh(HomeFeedSources(
      history: const [],
      related: (_) async => const [],
      channelUploads: (_) async => const [],
      search: (_) async => [
        for (var i = 0; i < 6; i++) VideoItem(id: 'video$i'.padRight(11, '0'), title: '推荐视频 $i', channel: '频道 $i', channelId: 'UC$i', url: 'u'),
      ],
    ));
    final controller = AppController()
      ..ready = true
      ..homeFeed = feed;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VideoActions(controller: controller, child: HomeFeedPage(controller: controller, onFocusSearch: () {})))));
    await tester.pump();
    expect(find.text('为你推荐'), findsOneWidget);
    expect(find.text('换一批'), findsOneWidget);
    expect(find.text('推荐视频 0'), findsOneWidget);
    await tester.tap(find.text('换一批'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
