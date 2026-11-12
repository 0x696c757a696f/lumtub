import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/app/home_feed.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/recommendations.dart';
import 'package:lumtub/ui/pages/video_pages.dart';
import 'package:lumtub/ui/video_card.dart';

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
    expect(find.text('For you'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('推荐视频 0'), findsOneWidget);
    await tester.tap(find.text('Shuffle'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('下拉刷新 puts new videos first and marks where the ones seen before begin', (tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var round = 0;
    HomeFeedSources sources() => HomeFeedSources(
          history: const [],
          related: (_) async => const [],
          channelUploads: (_) async => const [],
          search: (_) async => [
            for (var i = 0; i < 3; i++) VideoItem(id: 'r${round}v$i'.padRight(11, '0'), title: '第 $round 轮 $i', channel: '频道 $i', channelId: 'UC$i', url: 'u'),
          ],
        );
    final feed = HomeFeed(NotInterested(null));
    await feed.refresh(sources());
    final before = feed.items.map((item) => item.id).toList();
    expect(feed.seenFrom, isNull);
    round = 1;
    await feed.refresh(sources(), ahead: true);
    final ids = feed.items.map((item) => item.id).toList();
    expect(ids.first, startsWith('r1'));
    expect(feed.seenFrom, before.first);
    expect(ids.sublist(ids.indexOf(feed.seenFrom!)), before);
    final controller = AppController()
      ..ready = true
      ..homeFeed = feed;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VideoActions(controller: controller, child: HomeFeedPage(controller: controller, onFocusSearch: () {})))));
    await tester.pump();
    final marker = find.text('You were here last time · Tap to refresh');
    expect(marker, findsOneWidget);
    expect(tester.getTopLeft(find.text('第 1 轮 0')).dy, lessThan(tester.getTopLeft(marker).dy));
    expect(tester.getTopLeft(find.text('第 0 轮 0')).dy, greaterThan(tester.getTopLeft(marker).dy));
    feed.shuffle();
    expect(feed.seenFrom, isNull);
  });
}
