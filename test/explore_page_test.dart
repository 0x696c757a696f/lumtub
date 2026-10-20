import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/app/app_controller.dart';
import 'package:ytplus/app_preferences.dart';
import 'package:ytplus/explore_topics.dart';
import 'package:ytplus/faith_topics.dart';
import 'package:ytplus/models.dart';
import 'package:ytplus/recommendations.dart';
import 'package:ytplus/search_options.dart';
import 'package:ytplus/ui/pages/explore_page.dart';

Future<AppController> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = AppController()..ready = true;
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ExplorePage(controller: controller),
  ))));
  await tester.pump();
  return controller;
}

/// Scrolls the zone strip with its arrow until [label] is in view.
Future<void> _reveal(WidgetTester tester, String label) async {
  bool inView() {
    final found = find.text(label);
    if (found.evaluate().isEmpty) return false;
    final rect = tester.getRect(found.last);
    return rect.left > 40 && rect.right < 1240;
  }

  for (var turn = 0; turn < 20 && !inView(); turn++) {
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  expect(inView(), isTrue, reason: '$label is in view');
}

void main() {
  test('each mode asks YouTube for its own order and filters', () {
    expect(exploreParams(ExploreMode.popular, period: SearchUploadDate.month), 'CAMSBAgEEAE%253D');
    expect(exploreParams(ExploreMode.liveViewers), 'CAMSAkAB');
    // Newest first, videos only.
    expect(exploreParams(ExploreMode.latest), 'CAISAhAB');
    // Long: views, this year, videos, over 20 minutes.
    expect(exploreParams(ExploreMode.long), 'CAMSBggFEAEYAg%253D%253D');
    final hdr = base64.decode(searchParams(quality: SearchQuality.hdr)!.replaceAll('%253D', '='));
    expect(hdr, [0x12, 3, 0xC8, 0x01, 1]);
    final uhd = base64.decode(exploreParams(ExploreMode.liveViewers, quality: SearchQuality.uhd).replaceAll('%253D', '='));
    expect(uhd, [0x08, 3, 0x12, 4, 0x40, 1, 0x70, 1]);
  });

  test('宗教与信仰 has four tabs of zones, with Christianity split twice', () {
    expect(ExploreSection.faithTabs.map((s) => s.label), ['宗教传统', '宗教学术', '文化艺术', '宗教直播']);
    final christian = faithTraditionTopics.first;
    expect(christian.label, '基督宗教');
    expect(christian.subs.map((s) => s.label), ['天主教', '东正教', '新教', '东方正统教会', '其他基督宗教']);
    final catholic = christian.subs.first;
    expect(catholic.subs.map((s) => s.label), containsAll(['教宗讲话', '梵蒂冈新闻', '弥撒', '圣事', '圣人传记', '修会生活', '教会音乐']));
    expect(christian.subs[2].subs.map((s) => s.label), containsAll(['路德宗', '改革宗', '圣公会', '卫理宗', '浸信会', '五旬节派', '福音派']));
    expect(faithTraditionTopics.map((t) => t.label), containsAll(['伊斯兰教', '佛教', '道教与中国传统信仰', '印度教', '犹太教', '其他宗教']));
    expect(faithStudyTopics.map((t) => t.label), containsAll(['宗教历史', '宗教哲学', '比较宗教学', '宗教与社会', '无神论与宗教批评', '宗教对话']));
    expect(faithLiveTopics, hasLength(10));
    for (final section in ExploreSection.values) {
      final topics = exploreTopicsOf(section);
      expect(topics.map((t) => t.key).toSet(), hasLength(topics.length), reason: section.name);
      for (final topic in topics) {
        expect(topic.query, isNotEmpty);
        for (final sub in topic.subs) {
          expect([sub.query, for (final leaf in sub.subs) leaf.query], everyElement(isNotEmpty));
        }
      }
    }
    // Faith has its own entry now, not a zone among the videos.
    expect(popularTopics.map((t) => t.label), isNot(contains('宗教信仰')));
    expect(ExploreMode.of(ExploreSection.faith).first, ExploreMode.curated);
    expect(ExploreMode.of(ExploreSection.popular), isNot(contains(ExploreMode.curated)));
    expect(ExploreMode.of(ExploreSection.faithLive), [ExploreMode.liveViewers, ExploreMode.liveLatest, ExploreMode.liveUpcoming, ExploreMode.liveReplay]);
    // Upcoming and past streams come from the newest videos.
    expect(exploreParams(ExploreMode.liveUpcoming), 'CAISAhAB');
    expect(exploreParams(ExploreMode.curated), 'EgIQAQ%253D%253D');
  });

  test('宗教与信仰 leaves out bait and keeps a channel to three videos', () {
    expect(looksLikeBait('Atheist DESTROYS pastor in debate'), isTrue);
    expect(looksLikeBait('震惊！神父说出真相'), isTrue);
    expect(looksLikeBait('WHAT THE CHURCH WILL NOT TELL YOU'), isTrue);
    expect(looksLikeBait('You must see this!!!'), isTrue);
    expect(looksLikeBait('Holy Mass from St Peter\'s Basilica'), isFalse);
    expect(looksLikeBait('天主教的七件圣事'), isFalse);
    expect(looksLikeBait('EWTN Daily Mass'), isFalse);
    final keep = faithFilter();
    VideoItem video(int i, String channel) => VideoItem(id: 'v$i'.padRight(11, '0'), title: 'Mass $i', channel: channel, url: '');
    final kept = [for (var i = 0; i < 6; i++) video(i, i < 5 ? 'a' : 'b')].where(keep).map((v) => v.channel).toList();
    expect(kept, ['a', 'a', 'a', 'b']);
  });

  test('arranges zones in the saved order and leaves hidden ones out', () {
    const topics = [ExploreTopic('A', Icons.abc, 'a'), ExploreTopic('B', Icons.abc, 'b'), ExploreTopic('C', Icons.abc, 'c'), ExploreTopic('D', Icons.abc, 'd')];
    expect(arrangeTopics(topics, ['C', 'A'], {'B'}).map((t) => t.label), ['C', 'A', 'D']);
    expect(arrangeTopics(topics, const [], {'A', 'B', 'C', 'D'}).map((t) => t.label), ['A']);
  });

  test('custom zones, order and hidden zones round-trip through the preferences', () {
    const prefs = AppPreferences(
      exploreCustomTopics: [CustomTopic('额我略圣歌', 'Gregorian chant', ExploreSection.popular), CustomTopic('朝拜圣体', 'Eucharistic adoration live', ExploreSection.live)],
      exploreOrder: {'popular': ['宗教信仰', 'custom:额我略圣歌']},
      exploreHidden: {'popular': ['游戏']},
    );
    final back = AppPreferences.fromJson(jsonDecode(jsonEncode(prefs.toJson())));
    expect(back.exploreCustomTopics.map((t) => (t.label, t.query, t.section)), [
      ('额我略圣歌', 'Gregorian chant', ExploreSection.popular),
      ('朝拜圣体', 'Eucharistic adoration live', ExploreSection.live),
    ]);
    expect(back.exploreOrder, {'popular': ['宗教信仰', 'custom:额我略圣歌']});
    expect(back.exploreHidden, {'popular': ['游戏']});
    final live = exploreTopicsOf(ExploreSection.live, back.exploreCustomTopics);
    expect(live.last.label, '朝拜圣体');
    expect(live.last.custom, isTrue);
  });

  test('为你推荐 ranks videos like the history above others', () {
    VideoItem video(String id, String title, String channel, {int? views}) =>
        VideoItem(id: id.padRight(11, '0'), title: title, channel: channel, channelId: 'UC$channel'.padRight(24, '0'), url: '', viewCount: views);
    final taste = TasteProfile.from(history: [
      for (var i = 0; i < 5; i++) video('h$i', 'Catholic Mass Gregorian chant $i', 'chant'),
      video('x', 'Cooking pasta', 'food'),
    ]);
    final liked = AppController.exploreScore(taste, video('a', 'Gregorian chant for prayer', 'chant'));
    final other = AppController.exploreScore(taste, video('b', 'Football highlights', 'sport', views: 10000000));
    expect(liked, greaterThan(other));
  });

  testWidgets('switches halves, zones, sub-categories and modes', (tester) async {
    final controller = await _open(tester);
    expect(find.text('知识教育 · 本月观看最多'), findsOneWidget);

    await tester.tap(find.text('历史'));
    await tester.pump();
    expect(controller.exploreQuery, '历史 纪录片');
    expect(find.text('知识教育 · 历史 · 本月观看最多'), findsOneWidget);

    await tester.tap(find.text('最新'));
    await tester.pump();
    expect(controller.exploreMode, ExploreMode.latest);
    expect(controller.exploreSub, 2);

    await _reveal(tester, '游戏');
    await tester.tap(find.text('游戏'));
    await tester.pump();
    expect(controller.exploreSub, 0);
    await tester.tap(find.text('攻略'));
    await tester.pump();
    expect(controller.exploreQuery, '游戏攻略');
    expect(controller.exploreMode, ExploreMode.latest);

    await tester.tap(find.text('直播').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.exploreSection, ExploreSection.live);
    expect(controller.exploreMode, ExploreMode.liveViewers);
    expect(find.text('全部直播 · 按观看人数排列'), findsOneWidget);
    expect(find.text('本月'), findsNothing);

    await _reveal(tester, '电台助眠');
    await tester.tap(find.text('电台助眠'));
    await tester.pump();
    await tester.tap(find.text('Lo-Fi'));
    await tester.pump();
    expect(controller.exploreQuery, 'lofi hip hop radio');
    expect(tester.takeException(), isNull);
  });

  testWidgets('宗教与信仰: tabs, three levels, filters and stream states', (tester) async {
    final controller = await _open(tester);
    await tester.tap(find.text('宗教与信仰'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.exploreSection, ExploreSection.faith);
    expect(controller.exploreMode, ExploreMode.curated);
    expect(controller.exploreTopicNow.label, '基督宗教');
    expect(find.text('宗教学术'), findsOneWidget);

    await tester.tap(find.text('天主教'));
    await tester.pump();
    expect(find.text('全部天主教'), findsOneWidget);
    await tester.tap(find.text('弥撒'));
    await tester.pump();
    expect(controller.exploreQuery, 'Holy Mass 弥撒');
    expect(find.text('基督宗教 · 天主教 · 弥撒 · 相关度高的完整内容，少标题党，每个频道最多 3 个'), findsOneWidget);

    await tester.tap(find.text('类型'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('纪录片').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.exploreQuery, 'Holy Mass 弥撒 documentary 纪录片');

    // Another sub-category starts on all of it.
    await tester.tap(find.text('新教'));
    await tester.pump();
    expect(controller.exploreLeaf, 0);
    expect(find.text('福音派'), findsOneWidget);

    await tester.tap(find.text('宗教学术'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.exploreSection, ExploreSection.faithStudy);
    expect(controller.exploreMode, ExploreMode.curated);
    expect(controller.exploreTopicNow.label, '精选专题');

    await tester.tap(find.text('宗教直播'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.exploreMode, ExploreMode.liveViewers);
    expect(find.text('类型'), findsNothing);
    await tester.tap(find.text('即将开播'));
    await tester.pump();
    expect(controller.exploreMode, ExploreMode.liveUpcoming);
    expect(controller.exploreQuery, 'Holy Mass live 弥撒 直播');

    await tester.tap(find.text('视频').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.exploreSection, ExploreSection.popular);
    expect(controller.exploreMode, ExploreMode.popular);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds and removes a custom zone', (tester) async {
    final controller = await _open(tester);
    await _reveal(tester, '添加');
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
    expect(controller.exploreQuery, 'Gregorian chant');

    await _reveal(tester, '额我略圣歌');
    await tester.longPress(find.text('额我略圣歌').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.preferences.exploreCustomTopics, isEmpty);
    expect(controller.exploreTopicNow.label, '知识教育');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pins and hides zones from the manage dialog', (tester) async {
    final controller = await _open(tester);
    await _reveal(tester, '管理');
    await tester.tap(find.text('管理'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('管理视频分区'), findsOneWidget);

    // Hide the first zone, then pin 科学探索 to the front.
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    final faith = find.ancestor(of: find.text('科学探索'), matching: find.byType(ListTile));
    await tester.ensureVisible(faith);
    await tester.pump();
    await tester.tap(find.descendant(of: faith, matching: find.byTooltip('置顶')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump(const Duration(milliseconds: 300));

    final topics = controller.exploreTopicsFor(ExploreSection.popular);
    expect(topics.first.label, '科学探索');
    expect(topics.map((t) => t.label), isNot(contains('知识教育')));
    expect(controller.preferences.exploreHidden['popular'], ['知识教育']);
    // The zone shown was hidden, so the strip starts over on its first.
    expect(controller.exploreTopicNow.label, '科学探索');
    expect(tester.takeException(), isNull);
  });
}
