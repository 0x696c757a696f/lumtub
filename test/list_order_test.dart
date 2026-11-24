import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/app/library_controller.dart';
import 'package:lumtub/app_preferences.dart';
import 'package:lumtub/library_store.dart';
import 'package:lumtub/list_order.dart';
import 'package:lumtub/models.dart';

VideoItem video(String id, {String title = '', int? duration, DateTime? published, String? channelId}) =>
    VideoItem(id: id, title: title, channel: '', url: 'https://www.youtube.com/watch?v=$id', duration: duration, published: published, channelId: channelId);

String channelId(int i) => 'UC${'$i'.padLeft(22, '0')}';

void main() {
  test('names sort by letters, ignoring case, and numbers by value', () {
    final names = ['part 10', 'Part 2', 'apple', 'Banana', 'part 02', 'part 1', '学习', 'Zoo'];
    final sorted = [for (final n in names) NameKey(n)]..sort();
    expect([for (final k in sorted) k.text], ['apple', 'Banana', 'part 1', 'Part 2', 'part 02', 'part 10', 'Zoo', '学习']);
    // A number too long for any integer type still compares.
    expect(NameKey('a 99999999999999999999999').compareTo(NameKey('a 100000000000000000000000')), lessThan(0));
  });

  test('groups by name, size and newest video; custom keeps the stored order', () {
    final music = ChannelGroup('Music', {channelId(1), channelId(2), channelId(3)});
    final learning = ChannelGroup('learning', {channelId(4)});
    final news = ChannelGroup('News', {channelId(5), channelId(6)});
    final groups = [music, learning, news];
    expect(orderGroups(groups, GroupOrder.manual), same(groups));
    expect(orderGroups(groups, GroupOrder.name), [learning, music, news]);
    expect(orderGroups(groups, GroupOrder.size), [music, news, learning]);
    final rank = {channelId(6): 0, channelId(4): 1, channelId(2): 2};
    expect(orderGroups(groups, GroupOrder.recent, rank: rank), [news, learning, music]);
    // A group with no videos in the feed goes last.
    final empty = ChannelGroup('Empty');
    expect(orderGroups([empty, ...groups], GroupOrder.recent, rank: rank).last, empty);
  });

  test('channels by newest video (live first), name, follow date and watch count', () {
    final channels = [for (var i = 0; i < 5; i++) ChannelRef(channelId(i), 'Channel ${5 - i}')];
    final rank = {channelId(3): 0, channelId(1): 1, channelId(4): 2};
    final recent = orderChannels(channels, ChannelOrder.recent, rank: rank, live: {channelId(0)});
    expect([for (final c in recent) c.id], [channelId(0), channelId(3), channelId(1), channelId(4), channelId(2)]);
    expect([for (final c in orderChannels(channels, ChannelOrder.name)) c.name], ['Channel 1', 'Channel 2', 'Channel 3', 'Channel 4', 'Channel 5']);
    expect(orderChannels(channels, ChannelOrder.followed).first, channels.last);
    final history = [video('a', channelId: channelId(2)), video('b', channelId: channelId(2)), video('c', channelId: channelId(4))];
    final watched = orderChannels(channels, ChannelOrder.watched, watched: countByChannel(history));
    expect([for (final c in watched) c.id].take(2), [channelId(2), channelId(4)]);
  });

  test('playlists by name, date made and size; YouTube copies after own lists', () {
    final old = LocalPlaylist(id: 1000.toRadixString(36), name: 'b', items: [video('1')]);
    final fresh = LocalPlaylist(id: 2000.toRadixString(36), name: 'A', items: [video('1'), video('2')]);
    final remote = LocalPlaylist(id: '${remotePlaylistPrefix}PL1', name: 'c', items: [video('1'), video('2'), video('3')]);
    final lists = [old, remote, fresh];
    expect(orderPlaylists(lists, PlaylistOrder.name), [fresh, old, remote]);
    expect(orderPlaylists(lists, PlaylistOrder.created), [fresh, old, remote]);
    expect(orderPlaylists(lists, PlaylistOrder.size), [remote, fresh, old]);
  });

  test('videos by upload date and length put unknown values last; equal keys stay in order', () {
    final a = video('a', title: 'b', duration: 60, published: DateTime(2024));
    final b = video('b', title: 'A', published: DateTime(2025));
    final c = video('c', title: 'c', duration: 600);
    final d = video('d', title: 'd', duration: 60, published: DateTime(2024));
    final items = [a, b, c, d];
    expect(orderVideos(items, VideoOrder.added), same(items));
    expect(orderVideos(items, VideoOrder.published), [b, a, d, c]);
    expect(orderVideos(items, VideoOrder.duration), [c, a, d, b]);
    expect(orderVideos(items, VideoOrder.title), [b, a, c, d]);
  });

  test('the chosen orders are saved with the preferences', () {
    const prefs = AppPreferences(
      groupOrder: GroupOrder.name,
      channelOrder: ChannelOrder.watched,
      playlistOrder: PlaylistOrder.size,
      videoOrders: {'favorites': VideoOrder.duration},
    );
    final back = AppPreferences.fromJson(prefs.toJson());
    expect(back.groupOrder, GroupOrder.name);
    expect(back.channelOrder, ChannelOrder.watched);
    expect(back.playlistOrder, PlaylistOrder.size);
    expect(back.videoOrders, {'favorites': VideoOrder.duration});
    final fresh = AppPreferences.fromJson({'groupOrder': 'nonsense', 'videoOrders': {'x': 'nonsense', 'y': 'title'}});
    expect(fresh.groupOrder, GroupOrder.manual);
    expect(fresh.channelOrder, ChannelOrder.recent);
    expect(fresh.videoOrders, {'y': VideoOrder.title});
  });

  group('library', () {
    late LibraryController library;
    late AppController controller;
    setUp(() {
      final dir = Directory.systemTemp.createTempSync('lumtub_order');
      addTearDown(() => dir.deleteSync(recursive: true));
      library = LibraryController(LibraryStore(File('${dir.path}/library.json')));
      controller = AppController()..library = library;
    });

    test('dragged order is kept; entries added meanwhile stay, removed ones go', () {
      final a = library.addGroup('a');
      final b = library.addGroup('b');
      final c = library.addGroup('c');
      final before = library.revision;
      library.arrangeGroups([c, a, b]);
      expect(library.channelGroups, [c, a, b]);
      expect(library.revision, greaterThan(before));
      // The same order again changes nothing.
      final now = library.revision;
      library.arrangeGroups([c, a, b]);
      expect(library.revision, now);
      final d = library.addGroup('d');
      library.removeGroup(a);
      library.arrangeGroups([b, a, c]);
      expect(library.channelGroups, [b, c, d]);
    });

    test('sorted lists are worked out once until something changes', () {
      library.addGroup('b');
      library.addGroup('a');
      controller.preferences = controller.preferences.copyWith(groupOrder: GroupOrder.name);
      final first = controller.orderedGroups;
      expect([for (final g in first) g.name], ['a', 'b']);
      expect(controller.orderedGroups, same(first));
      library.addGroup('0');
      expect([for (final g in controller.orderedGroups) g.name], ['0', 'a', 'b']);
    });

    test('a playlist sorted by length plays in that order', () async {
      final playlist = library.createPlaylist('p');
      for (final (i, length) in [30, 300, 120].indexed) {
        library.addToPlaylist(playlist, video('v$i', duration: length));
      }
      controller.preferences = controller.preferences.copyWith(videoOrders: {playlist.id: VideoOrder.duration});
      expect([for (final v in controller.orderedVideos(playlist.id, playlist.items)) v.duration], [300, 120, 30]);
      await controller.arrangeVideos(playlist.id, [playlist.items[2], playlist.items[0], playlist.items[1]]);
      expect(controller.videoOrder(playlist.id), VideoOrder.added);
      expect([for (final v in playlist.items) v.duration], [120, 30, 300]);
    });
  });

  test('sorting 20,000 entries stays quick', () {
    final channels = [for (var i = 0; i < 20000; i++) ChannelRef(channelId(i), 'Channel ${(i * 7919) % 20000}')];
    final history = [for (var i = 0; i < 5000; i++) video('h$i', channelId: channelId((i * 31) % 20000))];
    final feed = [for (var i = 0; i < 20000; i++) video('f$i', channelId: channelId((i * 13) % 20000))];
    final videos = [for (var i = 0; i < 20000; i++) video('v$i', title: 'Video ${(i * 7919) % 20000}', duration: (i * 37) % 3600, published: DateTime(2020).add(Duration(hours: (i * 101) % 50000)))];
    final timer = Stopwatch()..start();
    final times = <String, int>{};
    void time(String name, void Function() run) {
      timer.reset();
      run();
      times[name] = timer.elapsedMilliseconds;
    }

    time('channels by newest', () => orderChannels(channels, ChannelOrder.recent, rank: rankInFeed(feed)));
    time('channels by name', () => orderChannels(channels, ChannelOrder.name));
    time('channels by watch count', () => orderChannels(channels, ChannelOrder.watched, watched: countByChannel(history)));
    time('videos by title', () => orderVideos(videos, VideoOrder.title));
    time('videos by date', () => orderVideos(videos, VideoOrder.published));
    time('videos by length', () => orderVideos(videos, VideoOrder.duration));
    // ignore: avoid_print
    print('Sorting 20,000 entries, ms: $times');
    for (final ms in times.values) {
      expect(ms, lessThan(500));
    }
  });
}
