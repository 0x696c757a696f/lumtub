import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/app/library_controller.dart';
import 'package:lumtub/app/video_list_loader.dart';
import 'package:lumtub/library_store.dart';
import 'package:lumtub/list_order.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/ui/app_icons.dart';
import 'package:lumtub/ui/common.dart';
import 'package:lumtub/ui/pages/channel_page.dart';
import 'package:lumtub/ui/pages/library_pages.dart';
import 'package:lumtub/ui/theme.dart';
import 'package:lumtub/ui/video_card.dart';
import 'package:lumtub/video_repository.dart';
import 'package:lumtub/youtube_account.dart';
import 'package:material_ui/material_ui.dart';

import 'tooltip_finder.dart';

void main() {
  const channel = ChannelRef('UCuAXFkgsw1L7xaCfnd5JJOw', 'Rick Astley');
  final videos = [
    for (var i = 0; i < 6; i++)
      VideoItem(id: 'video${i}xxxxx', title: '视频 $i', channel: 'Rick Astley', url: 'https://www.youtube.com/watch?v=video${i}xxxxx', duration: 200, channelId: channel.id),
  ];

  late AppController controller;
  late LibraryController library;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('lumtub_pages');
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
    expect(find.text('No followed channels yet'), findsOneWidget);
  });

  testWidgets('subscriptions show followed channels and their feed', (tester) async {
    library.toggleFollow(channel);
    library.feed = videos;
    for (final width in [1280.0, 600.0]) {
      await pump(tester, SubscriptionsPage(controller: controller), width: width);
      expect(find.text('Rick Astley'), findsWidgets);
      expect(find.text('视频 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    unawaited(library.flush());
  });

  testWidgets('many subscriptions fit in one row; picking one narrows the feed', (tester) async {
    for (var i = 0; i < 100; i++) {
      library.toggleFollow(ChannelRef('UC${'$i'.padLeft(22, '0')}', '频道 $i'));
    }
    library.toggleFollow(channel);
    library.feed = videos;
    // A wide window lists the channels in a column on the left.
    await pump(tester, SubscriptionsPage(controller: controller));
    expect(tester.getTopLeft(find.text('Rick Astley').first).dx, lessThan(100));
    expect(find.text('Show all 101'), findsOneWidget);

    await pump(tester, SubscriptionsPage(controller: controller), width: 900);
    final strip = find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.horizontal);
    Finder inStrip(String text) => find.descendant(of: strip, matching: find.text(text));
    // The channel that just posted comes right after 全部, in the same row.
    final rick = tester.getTopLeft(inStrip('Rick Astley'));
    expect(tester.getTopLeft(find.text('All')).dx, lessThan(rick.dx));
    expect(find.text('视频 0'), findsOneWidget);

    await tester.tap(find.text('频道 3'));
    await tester.pump();
    expect(find.text('视频 0'), findsNothing);
    expect(find.text('No recent videos from this channel'), findsOneWidget);
    await tester.tap(inStrip('Rick Astley'));
    await tester.pump();
    expect(find.text('New from Rick Astley'), findsOneWidget);
    expect(find.text('视频 0'), findsOneWidget);

    // A mouse wheel scrolls the row sideways.
    final pointer = TestPointer(1, PointerDeviceKind.mouse)..hover(tester.getCenter(strip));
    final before = tester.getTopLeft(inStrip('频道 3')).dx;
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await tester.pump();
    expect(tester.getTopLeft(inStrip('频道 3')).dx, lessThan(before));

    // The full list searches by name and narrows the page to the pick.
    await tester.tap(find.text('Show all 101'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '频道 42');
    await tester.pump();
    expect(find.widgetWithText(ListTile, '频道 7'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, '频道 42'));
    await tester.pumpAndSettle();
    expect(find.text('New from 频道 42'), findsOneWidget);
    expect(tester.takeException(), isNull);
    unawaited(library.flush());
  });

  test('imported subscriptions keep their pictures', () {
    final ref = YouTubeAccountApi.parseSubscription({
      'snippet': {
        'title': 'Rick Astley',
        'resourceId': {'channelId': channel.id},
        'thumbnails': {'default': {'url': 'https://yt3.ggpht.com/a=s88'}, 'medium': {'url': 'https://yt3.ggpht.com/a=s240'}},
      },
    })!;
    expect(ref.avatar, 'https://yt3.ggpht.com/a=s240');
    expect(ChannelRef.fromJson(ref.toJson())!.avatar, ref.avatar);
    library.toggleFollow(channel);
    library.followAll([ref]);
    expect(library.channels.single.avatar, ref.avatar);
    unawaited(library.flush());
  });

  testWidgets('playlists list favorites first and open a playlist', (tester) async {
    library.toggleFavorite(videos.first);
    final playlist = library.createPlaylist('周末歌单');
    for (final video in videos.take(3)) {
      library.addToPlaylist(playlist, video);
    }
    await pump(tester, PlaylistsPage(controller: controller));
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('周末歌单'), findsOneWidget);
    expect(find.text('3 videos'), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.openPlaylistId = playlist.id;
    await pump(tester, PlaylistDetailPage(controller: controller));
    expect(find.text('Play all'), findsOneWidget);
    expect(find.text('视频 2'), findsOneWidget);
    expect(byTooltip('Rename'), findsOneWidget);

    controller.openPlaylistId = AppController.favoritesPlaylistId;
    await pump(tester, PlaylistDetailPage(controller: controller));
    expect(byTooltip('Rename'), findsNothing);
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
    expect(find.text('Search videos in this channel'), findsOneWidget);
    await tester.tap(find.text('Follow'));
    await tester.pump();
    expect(library.isFollowing(channel.id), isTrue);
    expect(tester.takeException(), isNull);
    // Cancels the delayed save, which the test clock would never run.
    unawaited(library.flush());
  });

  testWidgets("on a phone the channel's tabs are one row that stays at the top while the videos scroll", (tester) async {
    debugTouchFirst = true;
    addTearDown(() => debugTouchFirst = null);
    controller.channel = channel;
    controller.channelVideos = VideoListLoader(() => Listing(() => Stream.fromIterable([for (final v in videos) jsonEncode(v.toJson())])))..loadMore();
    addTearDown(controller.channelVideos!.dispose);
    await pump(tester, ChannelPage(controller: controller), width: 412);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    final tab = find.text(ChannelTab.videos.label);
    expect(tab, findsOneWidget);
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -600));
    await tester.pump();
    expect(tester.getTopLeft(tab).dy, inInclusiveRange(0, 52));
    expect(tester.takeException(), isNull);
    unawaited(library.flush());
  });

  testWidgets('groups can be dragged into order or sorted by name', (tester) async {
    library.toggleFollow(channel);
    for (final name in ['Music', 'Learning', 'News']) {
      library.addGroup(name, {channel.id});
    }
    await pump(tester, SubscriptionsPage(controller: controller));
    double chipX(String name) => tester.getTopLeft(find.text('$name · 1')).dx;
    expect(chipX('Music'), lessThan(chipX('Learning')));

    await tester.tap(find.text('Manage groups'));
    await tester.pumpAndSettle();
    // Drag Music below News.
    final handle = find.byIcon(AppIcons.dotsSixVertical).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect([for (final g in library.channelGroups) g.name], ['Learning', 'News', 'Music']);
    expect(controller.preferences.groupOrder, GroupOrder.manual);

    await tester.tap(byTooltip('Group order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name').last);
    await tester.pumpAndSettle();
    expect(controller.preferences.groupOrder, GroupOrder.name);
    // Sorting by name shows the groups that way and leaves the dragged
    // order stored for later.
    expect([for (final g in controller.orderedGroups) g.name], ['Learning', 'Music', 'News']);
    expect([for (final g in library.channelGroups) g.name], ['Learning', 'News', 'Music']);
    expect(tester.takeException(), isNull);
    unawaited(library.flush());
  });

  testWidgets('channels on the subscriptions page follow the order picked', (tester) async {
    for (final name in ['Banana', 'apple', 'Cherry']) {
      library.toggleFollow(ChannelRef('UC${name.toLowerCase().padRight(22, 'x')}', name));
    }
    await pump(tester, SubscriptionsPage(controller: controller), width: 900);
    await tester.tap(byTooltip('Channel order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name').last);
    await tester.pumpAndSettle();
    expect(controller.preferences.channelOrder, ChannelOrder.name);
    await pump(tester, SubscriptionsPage(controller: controller), width: 900);
    double x(String name) => tester.getTopLeft(find.text(name).first).dx;
    expect(x('apple'), lessThan(x('Banana')));
    expect(x('Banana'), lessThan(x('Cherry')));
    expect(tester.takeException(), isNull);
    unawaited(library.flush());
  });

  testWidgets('a playlist sorts its videos, turns around and takes a dragged order', (tester) async {
    final playlist = library.createPlaylist('周末歌单');
    for (final (i, length) in [30, 300, 120].indexed) {
      library.addToPlaylist(playlist, VideoItem(id: 'video${i}xxxxx', title: '视频 $i', channel: 'Rick Astley', url: 'https://www.youtube.com/watch?v=video${i}xxxxx', duration: length, channelId: channel.id));
    }
    controller.openPlaylistId = playlist.id;
    await pump(tester, PlaylistDetailPage(controller: controller));
    double y(String title) {
      final at = tester.getTopLeft(find.text(title));
      return at.dy * 10000 + at.dx;
    }
    expect(y('视频 0'), lessThan(y('视频 1')));

    await tester.tap(byTooltip('Video order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Length'));
    await tester.pumpAndSettle();
    await pump(tester, PlaylistDetailPage(controller: controller));
    expect(y('视频 1'), lessThan(y('视频 2')));
    expect(y('视频 2'), lessThan(y('视频 0')));

    await tester.tap(byTooltip('Video order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reverse order'));
    await tester.pumpAndSettle();
    await pump(tester, PlaylistDetailPage(controller: controller));
    expect(y('视频 0'), lessThan(y('视频 2')));

    await tester.tap(byTooltip('Video order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrange by dragging…'));
    await tester.pumpAndSettle();
    // Shown: 0, 2, 1. Move 1 to the top and save.
    await tester.tap(byTooltip('Move to top').last);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect([for (final v in playlist.items) v.title], ['视频 1', '视频 0', '视频 2']);
    expect(controller.videoOrder(playlist.id), VideoOrder.added);
    expect(controller.isReversed(playlist.id), isFalse);
    expect(tester.takeException(), isNull);
    unawaited(library.flush());
  });

  testWidgets('playlists can be sorted by name or dragged into order', (tester) async {
    for (final name in ['b', 'A', 'c']) {
      library.createPlaylist(name);
    }
    await pump(tester, PlaylistsPage(controller: controller));
    await tester.tap(byTooltip('Playlist order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name').last);
    await tester.pumpAndSettle();
    expect([for (final p in controller.orderedPlaylists) p.name], ['A', 'b', 'c']);

    await tester.tap(byTooltip('Playlist order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrange by dragging…'));
    await tester.pumpAndSettle();
    await tester.tap(byTooltip('Move to top').last);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect([for (final p in library.playlists) p.name], ['c', 'A', 'b']);
    expect(controller.preferences.playlistOrder, PlaylistOrder.manual);
    expect(tester.takeException(), isNull);
    unawaited(library.flush());
  });
}
