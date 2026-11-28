import 'dart:io';

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/app/library_controller.dart';
import 'package:lumtub/appearance_settings.dart';
import 'package:lumtub/device.dart';
import 'package:lumtub/l10n/l10n.dart';
import 'package:lumtub/library_store.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/ui/accessibility.dart';
import 'package:lumtub/ui/common.dart';
import 'package:lumtub/ui/learning/learning_page.dart';
import 'package:lumtub/ui/pages/downloads_page.dart';
import 'package:lumtub/ui/pages/explore_page.dart';
import 'package:lumtub/ui/pages/library_pages.dart';
import 'package:lumtub/ui/pages/settings_page.dart';
import 'package:lumtub/ui/pages/video_pages.dart';
import 'package:lumtub/ui/theme.dart';
import 'package:lumtub/ui/video_card.dart';
import 'package:material_ui/material_ui.dart';

const _video = VideoItem(
    id: 'abcdefghijk',
    title: 'How lighthouses are built',
    channel: 'Coast Stories',
    url: 'u',
    duration: 185,
    viewCount: 12000);
const _live = VideoItem(
    id: 'live0000000',
    title: 'Harbour camera',
    channel: 'Port Authority',
    url: 'u',
    liveStatus: 'is_live',
    membersOnly: true);

void main() {
  setUpAll(loadTranslations);
  tearDown(() {
    setLanguage(AppLanguage.en);
    videoLayout = VideoLayout.grid;
    debugTouchFirst = null;
  });

  Widget host(Widget child,
          {double scale = 1, Size size = const Size(1280, 800), AppController? controller}) =>
      MaterialApp(
        theme: buildAppTheme(Colors.blue, Brightness.light),
        builder: (context, page) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: page!),
        home: Scaffold(body: VideoActions(controller: controller ?? AppController(), child: child)),
      );

  testWidgets('a video card is one stop that says what the eye reads on it', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
            width: 320,
            height: 300,
            child: VideoCard(item: _video, onOpen: () {}, reason: 'Popular')))));
    final data =
        tester.getSemantics(find.bySemanticsLabel(RegExp('^How lighthouses'))).getSemanticsData();
    expect(
        data.label,
        allOf(contains('How lighthouses are built'), contains('Coast Stories'),
            contains('Length 3:05'), contains('views')));
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.hasAction(SemanticsAction.longPress), isTrue);
    expect(data.customSemanticsActionIds, isNotEmpty, reason: 'the menu is offered as an action');
    // Its pieces are not stops of their own.
    expect(find.bySemanticsLabel('How lighthouses are built'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a live members-only card says so in words, not only in colour', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 320, height: 300, child: VideoCard(item: _live, onOpen: () {})))));
    final label = tester.getSemantics(find.bySemanticsLabel(RegExp('^Harbour camera'))).label;
    expect(label, allOf(contains('Live now'), contains('Members only')));
    semantics.dispose();
  });

  testWidgets('a list row and a compact tile are single stops too', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(Column(children: [
      VideoRow(item: _video, onOpen: () {}, layout: VideoLayout.list),
      SizedBox(width: 400, child: CompactVideoTile(item: _video, onOpen: () {})),
    ])));
    expect(find.bySemanticsLabel(RegExp('^How lighthouses are built, Coast Stories')),
        findsNWidgets(2));
    semantics.dispose();
  });

  for (final layout in VideoLayout.values) {
    for (final (width, height, scale, tv) in [
      (360.0, 780.0, 2.0, false),
      (800.0, 1280.0, 2.0, false),
      (960.0, 540.0, 2.0, true),
      (1280.0, 800.0, 2.0, false),
      (1920.0, 1080.0, 2.0, false),
      (1280.0, 800.0, 1.0, false)
    ]) {
      testWidgets('video ${layout.name} at text ×$scale, $width wide${tv ? ' on a TV' : ''}, fits',
          (tester) async {
        videoLayout = layout;
        Device.tv = tv;
        addTearDown(() => Device.tv = false);
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(host(
          scale: scale,
          CustomScrollView(slivers: [
            SliverVideoGrid(
                items: const [_video, _live, _video, _live],
                onOpen: (_) {},
                watched: const {'abcdefghijk': 'yesterday'},
                reasons: const {'live0000000': 'Popular'})
          ]),
        ));
        expect(tester.takeException(), isNull);
      });
    }
  }

  final pages = <String, Widget Function(AppController)>{
    'home': (c) => HomeFeedPage(controller: c, onFocusSearch: () {}),
    'explore': (c) => ExplorePage(controller: c),
    'subscriptions': (c) => SubscriptionsPage(controller: c),
    'history': (c) => HistoryPage(controller: c),
    'playlists': (c) => PlaylistsPage(controller: c),
    'downloads': (c) => DownloadsPage(controller: c),
    'learning': (c) => LearningHome(controller: c),
    'settings': (c) => SettingsPage(controller: c),
  };
  for (final MapEntry(key: name, value: page) in pages.entries) {
    for (final brightness in Brightness.values) {
      testWidgets('the $name page names its buttons and keeps text readable, ${brightness.name}',
          (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final dir = Directory.systemTemp.createTempSync('lumtub_a11y');
        final library = LibraryController(LibraryStore(File('${dir.path}/library.json')));
        final controller = AppController()..library = library;
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(Colors.blue, brightness),
          home: Scaffold(body: VideoActions(controller: controller, child: page(controller))),
        ));
        await tester.pump(const Duration(milliseconds: 600));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await library.flush();
          dir.deleteSync(recursive: true);
        });
        semantics.dispose();
      });
    }
  }

  testWidgets('video cards meet the label guideline and, on touch, the tap target ones',
      (tester) async {
    final semantics = tester.ensureSemantics();
    debugTouchFirst = true;
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(CustomScrollView(slivers: [
      SliverVideoGrid(items: const [_video, _live], onOpen: (_) {})
    ])));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    semantics.dispose();
  });

  test('right-to-left subtitle lines are said right to left', () {
    expect(Accessibility.rightToLeft('مرحبا بالعالم'), isTrue);
    expect(Accessibility.rightToLeft('שלום'), isTrue);
    expect(Accessibility.rightToLeft('12 مرحبا'), isTrue);
    expect(Accessibility.rightToLeft('Hello مرحبا'), isFalse);
    expect(Accessibility.rightToLeft('你好'), isFalse);
    expect(Accessibility.rightToLeft(''), isFalse);
  });

  test('spoken parts leave empty ones out', () {
    expect(spokenParts(['a', null, ' ', 'b']), 'a, b');
  });
}
