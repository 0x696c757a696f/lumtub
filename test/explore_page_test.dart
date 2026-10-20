import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/app/app_controller.dart';
import 'package:ytplus/explore_topics.dart';
import 'package:ytplus/search_options.dart';
import 'package:ytplus/ui/pages/explore_page.dart';

void main() {
  test('popular topics keep the most viewed filter; live ones sort by viewers', () {
    expect(exploreParams(ExploreSection.popular, SearchUploadDate.month), 'CAMSBAgEEAE%253D');
    expect(exploreParams(ExploreSection.live, SearchUploadDate.month), 'CAMSAkAB');
  });

  testWidgets('switches between popular and live categories', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = AppController()..ready = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ExplorePage(controller: controller),
    ))));
    expect(find.text('本月'), findsOneWidget);
    expect(find.text('音乐 · 本月观看最多'), findsOneWidget);

    await tester.tap(find.text('本周'));
    await tester.pump();
    expect(controller.explorePeriod, SearchUploadDate.week);

    await tester.tap(find.text('直播').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.exploreSection, ExploreSection.live);
    expect(find.text('本月'), findsNothing);
    expect(find.text('全部直播 · 按观看人数排列'), findsOneWidget);

    await tester.pump();
    // The strip scrolls to categories past the window's edge.
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('购物'));
    await tester.pump();
    expect(controller.exploreTopicNow.label, '购物');
    expect(tester.takeException(), isNull);
  });
}
