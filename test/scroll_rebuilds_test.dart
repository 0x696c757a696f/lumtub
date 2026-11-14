import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/app/home_feed.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/recommendations.dart';
import 'package:lumtub/ui/video_card.dart';

VideoItem _video(int i) => VideoItem(id: 'v$i'.padRight(11, '0'), title: 'Video $i', channel: 'Channel $i', channelId: 'UC$i', url: 'u');

void main() {
  testWidgets('cards are not built again while the grid scrolls', (tester) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final items = [for (var i = 0; i < 300; i++) _video(i)];
    final controller = AppController()..ready = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VideoActions(
      controller: controller,
      child: CustomScrollView(slivers: [SliverVideoGrid(items: items, onOpen: (_) {})]),
    ))));
    await tester.pump();
    final built = Set<Element>.identity();
    void mark(Element element) {
      built.add(element);
      element.visitChildren(mark);
    }
    tester.binding.rootElement!.visitChildren(mark);
    var again = 0;
    widgets.debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is VideoCard && !built.add(element)) again++;
    };
    addTearDown(() => widgets.debugOnRebuildDirtyWidget = null);
    await tester.fling(find.byType(CustomScrollView), const Offset(0, -600), 2000);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    widgets.debugOnRebuildDirtyWidget = null;
    expect(again, 0);
  });

  test('the end of a feed with nothing more to show changes nothing as it scrolls', () async {
    final feed = HomeFeed(NotInterested(null));
    await feed.refresh(HomeFeedSources(
      history: const [],
      related: (_) async => const [],
      channelUploads: (_) async => const [],
      search: (_) async => [for (var i = 0; i < 6; i++) _video(i)],
    ));
    await feed.loadMore();
    var notified = 0;
    feed.addListener(() => notified++);
    final items = feed.items;
    for (var i = 0; i < 20; i++) {
      await feed.loadMore();
    }
    expect(notified, 0);
    expect(identical(feed.items, items), isTrue);
  });
}
