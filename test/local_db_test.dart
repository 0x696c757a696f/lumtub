import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_directories.dart';
import 'package:lumtub/app_log.dart';
import 'package:lumtub/library_store.dart';
import 'package:lumtub/local_db.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/video_repository.dart';

void main() {
  final skip = LocalDb.enabled ? false : 'needs lumtub_core (LUMTUB_CORE_DLL)';
  late Directory root;
  late AppDirectories directories;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lumtub_db');
    directories = AppDirectories.at(root);
    await directories.data.create(recursive: true);
    await AppLog.open(directories.logs);
  });
  tearDown(() async {
    await AppLog.current?.flush();
    AppLog.current = null;
    await root.delete(recursive: true);
  });

  VideoItem video(int i) => VideoItem(id: 'v${i.toString().padLeft(10, '0')}', title: '视频 $i', channel: 'Channel', url: 'https://www.youtube.com/watch?v=$i', duration: 60 + i);
  File libraryFile() => File('${directories.data.path}${Platform.pathSeparator}library.json');
  File database() => File('${directories.data.path}${Platform.pathSeparator}lumtub.db');

  Future<LibraryStore> openLibrary() async {
    final store = LibraryStore(libraryFile());
    await store.load();
    return store;
  }

  test('the library is kept in lumtub.db across a restart', () async {
    final store = await openLibrary();
    store.toggleFavorite(video(1));
    store.toggleFavorite(video(2));
    store.toggleWatchLater(video(3));
    final mix = store.createPlaylist('Mix');
    store.addToPlaylist(mix, video(4));
    store.addToPlaylist(mix, video(5));
    store.toggleFollow(const ChannelRef('UCaaaaaaaaaaaaaaaaaaaaaa', 'A', null));
    store.channelGroups.add(ChannelGroup('Music', {'UCaaaaaaaaaaaaaaaaaaaaaa'}));
    store.liveVideos['v1'] = ('UCaaaaaaaaaaaaaaaaaaaaaa', 'is_live');
    store.setProgress(video(1).id, const Duration(seconds: 30), const Duration(seconds: 100));
    store.setProgress(video(2).id, const Duration(seconds: 99), const Duration(seconds: 100));
    await store.save();
    expect(database().existsSync(), isTrue);
    expect(libraryFile().existsSync(), isFalse);

    final again = await openLibrary();
    expect(again.favorites.map((item) => item.id), [video(2).id, video(1).id]);
    expect(again.favorites.last.title, '视频 1');
    expect(again.favorites.last.duration, 61);
    expect(again.watchLater.single.id, video(3).id);
    expect(again.playlists.single.name, 'Mix');
    expect(again.playlists.single.items.map((item) => item.id), [video(4).id, video(5).id]);
    expect(again.channels.single.name, 'A');
    expect(again.channelGroups.single.channels, {'UCaaaaaaaaaaaaaaaaaaaaaa'});
    expect(again.liveVideos['v1'], ('UCaaaaaaaaaaaaaaaaaaaaaa', 'is_live'));
    expect(again.progressOf(video(1).id)!.position, const Duration(seconds: 30));
    expect(again.progressOf(video(2).id)!.finished, isTrue);

    // Changes and removals reach the database too.
    again.toggleFavorite(video(2));
    again.playlists.clear();
    await again.save();
    final third = await openLibrary();
    expect(third.favorites.map((item) => item.id), [video(1).id]);
    expect(third.playlists, isEmpty);
  }, skip: skip);

  test('a library.json from an earlier version is read in once and left as it was', () async {
    final old = {
      'version': 1,
      'favorites': [video(7).toJson()],
      'watchLater': <Object>[],
      'playlists': [
        {'id': 'p1', 'name': 'Old', 'items': [video(8).toJson()]},
      ],
      'channels': [
        {'id': 'UCbbbbbbbbbbbbbbbbbbbbbb', 'name': 'B'},
      ],
      'groups': <Object>[],
      'progress': {
        video(7).id: [12, 120],
      },
    };
    final text = jsonEncode(old);
    await libraryFile().writeAsString(text);
    final store = await openLibrary();
    expect(store.favorites.single.id, video(7).id);
    expect(store.playlists.single.items.single.id, video(8).id);
    expect(store.progressOf(video(7).id)!.position, const Duration(seconds: 12));
    expect(await libraryFile().readAsString(), text);

    // The database is what counts now: the old file is not read again.
    await libraryFile().writeAsString(jsonEncode({...old, 'favorites': <Object>[]}));
    final again = await openLibrary();
    expect(again.favorites.single.id, video(7).id);
    expect(again.channels.single.id, 'UCbbbbbbbbbbbbbbbbbbbbbb');
  }, skip: skip);

  test('a damaged database is set aside and the old file read again', () async {
    await libraryFile().writeAsString(jsonEncode({'favorites': [video(9).toJson()]}));
    await database().writeAsString('not a database, only some text that is long enough to have a header');
    final store = await openLibrary();
    expect(store.favorites.single.id, video(9).id);
    final kept = directories.data.listSync().map((entry) => entry.uri.pathSegments.last).where((name) => name.startsWith('lumtub.db.broken-'));
    expect(kept, isNotEmpty);
    final again = await openLibrary();
    expect(again.favorites.single.id, video(9).id);
  }, skip: skip);

  test('the watch history is kept in lumtub.db, newest first', () async {
    Future<HistoryStore> open() async {
      final store = HistoryStore(directories);
      await store.initialize();
      return store;
    }

    final history = await open();
    for (var i = 0; i < 300; i++) {
      await history.record(video(i));
    }
    await history.record(video(5));
    await history.flush();
    expect(history.file.existsSync(), isFalse);
    final again = await open();
    expect(again.items.length, 300);
    expect(again.items.first.id, video(5).id);
    expect(again.items[1].id, video(299).id);
    expect(again.items.last.id, video(0).id);
    expect(again.watched[video(5).id], isNotNull);
    await again.remove({video(299).id});
    await again.flush();
    final third = await open();
    expect(third.items.length, 299);
    expect(third.items[1].id, video(298).id);
  }, skip: skip);

  test('a list written twice is stored once, in order', () async {
    final db = LocalDb('${directories.data.path}${Platform.pathSeparator}lumtub.db');
    final entries = [for (var i = 0; i < 50; i++) ('k$i', '{"n":$i}')];
    await db.write({'list': entries});
    await db.write({'list': entries});
    final found = await LocalDb('${directories.data.path}${Platform.pathSeparator}lumtub.db').read(['list']);
    expect(found.lists['list']!.length, 50);
    expect(found.lists['list']!.first.$1, 'k0');
    expect(found.lists['list']!.first.$2, {'n': 0});
  }, skip: skip);
}
