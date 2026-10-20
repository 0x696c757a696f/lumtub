import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/app/app_controller.dart';
import 'package:ytplus/app/library_controller.dart';
import 'package:ytplus/app/video_list_loader.dart';
import 'package:ytplus/library_store.dart';
import 'package:ytplus/models.dart';
import 'package:ytplus/ui/pages/channel_page.dart';
import 'package:ytplus/ui/pages/library_pages.dart';
import 'package:ytplus/ui/theme.dart';
import 'package:ytplus/ui/video_card.dart';
import 'package:ytplus/video_repository.dart';

void main() {
  const channel = ChannelRef('UCuAXFkgsw1L7xaCfnd5JJOw', 'Rick Astley');
  final videos = [
    for (var i = 0; i < 6; i++)
      VideoItem(id: 'video${i}xxxxx', title: '视频 $i', channel: 'Rick Astley', url: 'https://www.youtube.com/watch?v=video${i}xxxxx', duration: 200, channelId: channel.id),
  ];

  late AppController controller;
  late LibraryController library;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('ytplus_pages');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = LibraryStore(File('${dir.path}/library.json'));
    library = LibraryController(store);
    controller = AppController()..library = library;
  });

  Future<void> pump(WidgetTester tester, Widget page, {double width = 1280}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Colors.red, Brightness.light),
      home: Scaffold(body: VideoActions(controller: controller, child: page)),
    ));
    await tester.pump();
  }

  testWidgets('subscriptions explain how to follow a channel', (tester) async {
    await pump(tester, SubscriptionsPage(controller: controller));
    expect(find.text('还没有关注频道'), findsOneWidget);
  });

  testWidgets('subscriptions show followed channels and their feed', (tester) async {
    library.toggleFollow(channel);
    library.feed = videos;
    for (final width in [1280.0, 600.0]) {
      await pump(tester, SubscriptionsPage(controller: controller), width: width);
      expect(find.widgetWithText(ActionChip, 'Rick Astley'), findsOneWidget);
      expect(find.text('视频 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    unawaited(library.flush());
  });

  testWidgets('many subscriptions fit in one row with a searchable full list', (tester) async {
    for (var i = 0; i < 100; i++) {
      library.toggleFollow(ChannelRef('UC${'$i'.padLeft(22, '0')}', '频道 $i'));
    }
    library.toggleFollow(channel);
    library.feed = videos;
    await pump(tester, SubscriptionsPage(controller: controller));
    // The channel that just posted comes first; the rest wait in the list.
    final chips = find.byType(ActionChip);
    expect(find.descendant(of: chips.at(1), matching: find.text('Rick Astley')), findsOneWidget);
    expect(tester.getTopLeft(chips.at(2)).dy, tester.getTopLeft(chips.at(1)).dy);
    expect(find.text('视频 0'), findsOneWidget);

    await tester.tap(find.text('全部 101 个'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '频道 42');
    await tester.pump();
    expect(find.widgetWithText(ListTile, '频道 42'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '频道 7'), findsNothing);
    expect(tester.takeException(), isNull);
    unawaited(library.flush());
  });

  testWidgets('playlists list favorites first and open a playlist', (tester) async {
    library.toggleFavorite(videos.first);
    final playlist = library.createPlaylist('稍后观看');
    for (final video in videos.take(3)) {
      library.addToPlaylist(playlist, video);
    }
    await pump(tester, PlaylistsPage(controller: controller));
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('稍后观看'), findsOneWidget);
    expect(find.text('3 个视频'), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.openPlaylistId = playlist.id;
    await pump(tester, PlaylistDetailPage(controller: controller));
    expect(find.text('播放全部'), findsOneWidget);
    expect(find.text('视频 2'), findsOneWidget);
    expect(find.byTooltip('重命名'), findsOneWidget);

    controller.openPlaylistId = AppController.favoritesPlaylistId;
    await pump(tester, PlaylistDetailPage(controller: controller));
    expect(find.byTooltip('重命名'), findsNothing);
    expect(find.text('视频 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Cancels the delayed save, which the test clock would never run.
    unawaited(library.flush());
  });

  testWidgets('channel page lists uploads and follows the channel', (tester) async {
    controller.channel = channel;
    controller.channelVideos = VideoListLoader(() => Listing(() => Stream.fromIterable([for (final v in videos) jsonEncode(v.toJson())])))..loadMore();
    addTearDown(controller.channelVideos!.dispose);
    await pump(tester, ChannelPage(controller: controller));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('Rick Astley'), findsWidgets);
    expect(find.text('视频 5'), findsOneWidget);
    expect(find.text('搜索频道内的视频'), findsOneWidget);
    await tester.tap(find.text('关注'));
    await tester.pump();
    expect(library.isFollowing(channel.id), isTrue);
    expect(tester.takeException(), isNull);
    // Cancels the delayed save, which the test clock would never run.
    unawaited(library.flush());
  });
}
