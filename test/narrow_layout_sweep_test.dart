import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/app/video_list_loader.dart';
import 'package:lumtub/l10n/l10n.dart';
import 'package:lumtub/models.dart';
import 'dart:io';

import 'package:lumtub/app/library_controller.dart';
import 'package:lumtub/library_store.dart';
import 'package:lumtub/ui/learning/learning_page.dart';
import 'package:lumtub/ui/pages/channel_page.dart';
import 'package:lumtub/ui/pages/downloads_page.dart';
import 'package:lumtub/ui/pages/explore_page.dart';
import 'package:lumtub/ui/pages/library_pages.dart';
import 'package:lumtub/ui/pages/settings_page.dart';
import 'package:lumtub/ui/pages/video_pages.dart';
import 'package:lumtub/ui/pages/youtube_playlist_page.dart';
import 'package:lumtub/device.dart';
import 'package:lumtub/ui/common.dart';
import 'package:lumtub/ui/theme.dart';
import 'package:lumtub/ui/video_card.dart';
import 'package:lumtub/video_repository.dart';

/// Text that a row squeezed: a word stood on end a letter or two per line
/// (a phone's playlist heading, 2026-11-25), or a name cut to a few letters
/// beside its buttons.
List<String> squeezedTexts(WidgetTester tester) {
  final found = <String>[];
  void visit(RenderObject object) {
    if (object is RenderParagraph && object.hasSize && object.attached) {
      // Laid out but not shown, such as a page slid away.
      final text = object.text.toPlainText().trim();
      final line = object.getMinIntrinsicHeight(double.infinity);
      final width = object.size.width;
      if (text.length >= 6 && line > 0 && width > 0) {
        final lines = object.size.height / line;
        final oneLine = object.getMaxIntrinsicWidth(double.infinity);
        if (lines >= 2.5 && width < 3 * line) found.add('on end: "$text" ${width.toStringAsFixed(0)} wide');
        if (object.didExceedMaxLines && width < 3.2 * line && oneLine > width * 1.5) found.add('cut short: "$text" ${width.toStringAsFixed(0)} wide');
      }
    }
    object.visitChildren(visit);
  }

  visit(tester.binding.rootElement!.renderObject!);
  return found;
}

void main() {
  setUpAll(loadTranslations);
  tearDown(() => setLanguage(AppLanguage.en));

  const channel = ChannelRef('UC0123456789abcdefghijkl', 'Discerning Hearts® Catholic Podcasts');
  const playlist = PlaylistResult(id: 'PL0123456789abcdefghijklmn', title: 'A Time of Lectio Divina for the Discerning Heart', channel: 'Discerning Hearts®');
  final videos = [
    for (var i = 0; i < 3; i++)
      VideoItem(id: 'video${i}xxxxx', title: 'Wednesday of the 34th Week in Ordinary Time $i', channel: channel.name, url: 'https://www.youtube.com/watch?v=video${i}xxxxx', duration: 900, channelId: channel.id),
  ];

  final pages = <String, Widget Function(AppController)>{
    'home': (c) => HomeFeedPage(controller: c, onFocusSearch: () {}),
    'explore': (c) => ExplorePage(controller: c),
    'subscriptions': (c) => SubscriptionsPage(controller: c),
    'history': (c) => HistoryPage(controller: c),
    'playlists': (c) => PlaylistsPage(controller: c),
    'saved playlist': (c) {
      final list = c.library!.createPlaylist('Lectio Divina per i cuori che discernono');
      for (final video in videos) {
        c.library!.addToPlaylist(list, video);
      }
      c.openPlaylistId = list.id;
      return PlaylistDetailPage(controller: c);
    },
    'downloads': (c) => DownloadsPage(controller: c),
    'learning': (c) => LearningHome(controller: c),
    'settings': (c) => SettingsPage(controller: c),
    'channel': (c) => ChannelHeader(controller: c, channel: channel, onBack: () {}),
    'followed channel': (c) {
      c.library!.toggleFollow(channel);
      return ChannelHeader(controller: c, channel: channel, onBack: () {});
    },
    'youtube playlist': (c) {
      c.youtubePlaylist = playlist;
      c.youtubePlaylistVideos = VideoListLoader(() => Listing(() => const Stream.empty()))
        ..items = videos
        ..hasMore = false;
      return YoutubePlaylistPage(controller: c);
    },
  };

  // Every language on a common phone at large text; a few long ones on
  // the narrowest phones too.
  final cases = [
    for (final file in Directory('assets/l10n').listSync().whereType<File>())
      if (file.path.endsWith('.json')) (file.uri.pathSegments.last.replaceAll('.json', ''), 360.0, 1.3),
    ('en', 360.0, 1.3),
    for (final language in ['it', 'de', 'fi', 'ru', 'ta', 'el', 'ar', 'zh-Hans'])
      for (final (width, scale) in [(320.0, 1.0), (390.0, 1.0)]) (language, width, scale),
  ];
  for (final (language, width, scale) in cases) {
    {
      testWidgets('pages fit a phone $width wide at text ×$scale in $language', (tester) async {
        setLanguage(AppLanguage(language));
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final problems = <String>[];
        for (final MapEntry(key: name, value: page) in pages.entries) {
          final dir = Directory.systemTemp.createTempSync('lumtub_sweep');
          final library = LibraryController(LibraryStore(File('${dir.path}/library.json')));
          final controller = AppController()..library = library;
          await tester.pumpWidget(MaterialApp(
            theme: buildAppTheme(Colors.red, Brightness.light),
            builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
            home: Scaffold(body: VideoActions(controller: controller, child: page(controller))),
          ));
          await tester.pump(const Duration(milliseconds: 600));
          final error = tester.takeException();
          if (error != null) problems.add('$name: $error');
          problems.addAll([for (final text in squeezedTexts(tester)) '$name: $text']);
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            await library.flush();
            dir.deleteSync(recursive: true);
          });
        }
        expect(problems.toSet().toList(), isEmpty);
      });
    }
  }

  // Twice the text, the most the font size setting offers, on every kind
  // of screen the app runs on: phones and tablets by touch, a TV by remote,
  // desktop windows from small to full HD.
  final screens = <(String, Size, {bool touch, bool tv})>[
    ('phone', const Size(360, 780), touch: true, tv: false),
    ('tablet', const Size(800, 1280), touch: true, tv: false),
    ('tablet sideways', const Size(1280, 800), touch: true, tv: false),
    ('TV', const Size(960, 540), touch: false, tv: true),
    ('small window', const Size(800, 600), touch: false, tv: false),
    ('desktop', const Size(1920, 1080), touch: false, tv: false),
  ];
  for (final language in ['en', 'de', 'ru', 'ar', 'ja', 'zh-Hans']) {
    for (final (kind, size, :touch, :tv) in screens) {
      testWidgets('pages fit a $kind at text ×2.0 in $language', (tester) async {
        setLanguage(AppLanguage(language));
        debugTouchFirst = touch;
        Device.tv = tv;
        addTearDown(() {
          debugTouchFirst = null;
          Device.tv = false;
        });
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final problems = <String>[];
        for (final MapEntry(key: name, value: page) in pages.entries) {
          final dir = Directory.systemTemp.createTempSync('lumtub_sweep');
          final library = LibraryController(LibraryStore(File('${dir.path}/library.json')));
          final controller = AppController()..library = library;
          await tester.pumpWidget(MaterialApp(
            theme: buildAppTheme(Colors.red, Brightness.light),
            builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
            home: Scaffold(body: VideoActions(controller: controller, child: page(controller))),
          ));
          await tester.pump(const Duration(milliseconds: 600));
          final error = tester.takeException();
          if (error != null) problems.add('$name: $error');
          problems.addAll([for (final text in squeezedTexts(tester)) '$name: $text']);
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            await library.flush();
            dir.deleteSync(recursive: true);
          });
        }
        expect(problems.toSet().toList(), isEmpty);
      });
    }
  }
}
