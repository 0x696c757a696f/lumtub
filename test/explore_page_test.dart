import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/app/app_controller.dart';
import 'package:ytplus/app_preferences.dart';
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
    for (var turn = 0; turn < 4 && find.text('购物').evaluate().isEmpty; turn++) {
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    await tester.tap(find.text('购物'));
    await tester.pump();
    expect(controller.exploreTopicNow.label, '购物');
    expect(tester.takeException(), isNull);
  });

  test('has religious categories, including Catholic ones', () {
    final popular = exploreTopicsOf(ExploreSection.popular).map((t) => t.label);
    final live = exploreTopicsOf(ExploreSection.live).map((t) => t.label);
    expect(popular, containsAll(['宗教', '天主教', '圣经', '圣歌']));
    expect(live, containsAll(['弥撒', '玫瑰经']));
  });

  test('custom topics round-trip through the preferences', () {
    const prefs = AppPreferences(exploreCustomTopics: [CustomTopic('额我略圣歌', 'Gregorian chant', ExploreSection.popular), CustomTopic('朝拜圣体', 'Eucharistic adoration live', ExploreSection.live)]);
    final back = AppPreferences.fromJson(jsonDecode(jsonEncode(prefs.toJson())));
    expect(back.exploreCustomTopics.map((t) => (t.label, t.query, t.section)), [
      ('额我略圣歌', 'Gregorian chant', ExploreSection.popular),
      ('朝拜圣体', 'Eucharistic adoration live', ExploreSection.live),
    ]);
    final live = exploreTopicsOf(ExploreSection.live, back.exploreCustomTopics);
    expect(live.last.label, '朝拜圣体');
    expect(live.last.custom, isTrue);
    expect(exploreTopicsOf(ExploreSection.popular, back.exploreCustomTopics).where((t) => t.custom).single.query, 'Gregorian chant');
  });

  testWidgets('adds and removes a custom category', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = AppController()..ready = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ExplorePage(controller: controller),
    ))));
    await tester.pump();
    for (var turn = 0; turn < 20 && find.text('添加').evaluate().isEmpty; turn++) {
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    await tester.ensureVisible(find.text('添加'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('添加'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('添加分类'), findsOneWidget);
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), '额我略圣歌');
    await tester.enterText(fields.at(1), 'Gregorian chant');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.preferences.exploreCustomTopics.single.query, 'Gregorian chant');
    expect(controller.exploreTopicNow.label, '额我略圣歌');
    expect(controller.exploreTopicNow.query, 'Gregorian chant');

    await tester.ensureVisible(find.text('额我略圣歌').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.longPress(find.text('额我略圣歌').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.preferences.exploreCustomTopics, isEmpty);
    expect(controller.exploreTopicNow.label, '音乐');
    expect(tester.takeException(), isNull);
  });
}
