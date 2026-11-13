import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/library_store.dart';
import 'package:lumtub/models.dart';

void main() {
  const channel = ChannelRef('UCuAXFkgsw1L7xaCfnd5JJOw', 'Rick Astley');
  const video = VideoItem(id: 'dQw4w9WgXcQ', title: 'Never Gonna Give You Up', channel: 'Rick Astley', url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', channelId: 'UCuAXFkgsw1L7xaCfnd5JJOw');
  const other = VideoItem(id: 'aaaaaaaaaaa', title: 'Other', channel: '', url: 'https://www.youtube.com/watch?v=aaaaaaaaaaa');

  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('lumtub_library'));
  tearDown(() => dir.delete(recursive: true));

  LibraryStore store() => LibraryStore(File('${dir.path}/library.json'));

  test('resumes only between the first seconds and the credits', () {
    final library = store();
    library.setProgress(video.id, const Duration(seconds: 5), const Duration(minutes: 3));
    expect(library.progressOf(video.id)!.resumable, isFalse);
    library.setProgress(video.id, const Duration(seconds: 90), const Duration(minutes: 3));
    expect(library.progressOf(video.id)!.resumable, isTrue);
    expect(library.progressOf(video.id)!.fraction, closeTo(0.5, 0.001));
    // A finished video starts over next time, but stays marked as watched.
    library.setProgress(video.id, const Duration(seconds: 175), const Duration(minutes: 3));
    expect(library.progressOf(video.id)!.resumable, isFalse);
    expect(library.progressOf(video.id)!.finished, isTrue);
    library.clearProgress();
    expect(library.progressOf(video.id), isNull);
  });

  test('counts changes to which videos are finished', () async {
    final library = store();
    var version = library.finishedVersion;
    library.setProgress(video.id, const Duration(seconds: 90), const Duration(minutes: 3));
    expect(library.finishedVersion, version);
    library.setProgress(video.id, const Duration(seconds: 175), const Duration(minutes: 3));
    expect(library.finishedVersion, ++version);
    library.setProgress(video.id, const Duration(seconds: 178), const Duration(minutes: 3));
    expect(library.finishedVersion, version);
    library.setProgress(video.id, const Duration(seconds: 10), const Duration(minutes: 3));
    expect(library.finishedVersion, ++version);
    library.clearProgress();
    expect(library.finishedVersion, ++version);
  });

  test('keeps favorites, playlists and followed channels without duplicates', () {
    final library = store();
    expect(library.toggleFavorite(video), isTrue);
    expect(library.isFavorite(video.id), isTrue);
    expect(library.toggleFavorite(video), isFalse);
    expect(library.favorites, isEmpty);

    final playlist = library.createPlaylist('  稍后观看 ');
    expect(playlist.name, '稍后观看');
    expect(library.createPlaylist('').name, 'Untitled playlist');
    expect(library.addToPlaylist(playlist, video), isTrue);
    expect(library.addToPlaylist(playlist, video), isFalse);

    expect(library.toggleFollow(channel), isTrue);
    expect(library.isFollowing(channel.id), isTrue);
    expect(library.toggleFollow(const ChannelRef('UCuAXFkgsw1L7xaCfnd5JJOw', '')), isFalse);
    expect(library.channels, isEmpty);
  });

  test('saves and loads everything', () async {
    final library = store();
    library.toggleFavorite(video);
    library.addToPlaylist(library.createPlaylist('Music'), other);
    library.toggleFollow(channel);
    library.setProgress(video.id, const Duration(seconds: 42), const Duration(minutes: 3));
    await library.save();

    final loaded = store();
    await loaded.load();
    expect(loaded.favorites.single.id, video.id);
    expect(loaded.favorites.single.channelRef, channel);
    expect(loaded.playlists.single.name, 'Music');
    expect(loaded.playlists.single.items.single.id, other.id);
    expect(loaded.channels.single.name, 'Rick Astley');
    expect(loaded.progressOf(video.id)!.position, const Duration(seconds: 42));
  });

  test('ignores a damaged file and bad channel ids', () async {
    await File('${dir.path}/library.json').writeAsString('{"channels":[{"id":"not-a-channel"}],"favorites":"x","progress":{"a":[1]}}');
    final library = store();
    await library.load();
    expect(library.channels, isEmpty);
    expect(library.favorites, isEmpty);
    expect(library.progressOf('a'), isNull);

    await File('${dir.path}/library.json').writeAsString('{not json');
    await store().load();
  });

  test('a backup restores channels, groups, favorites and own playlists without duplicates', () {
    final source = store();
    source.channels.add(channel);
    source.channelGroups.add(ChannelGroup('Music', {channel.id}));
    source.favorites.add(video);
    source.watchLater.add(other);
    source.createPlaylist('Mine').items.add(video);
    source.playlists.add(LocalPlaylist(id: '${remotePlaylistPrefix}PL1', name: 'From YouTube', items: [other]));
    source.setProgress(video.id, const Duration(seconds: 90), const Duration(minutes: 3));
    final backup = jsonDecode(jsonEncode(source.backupJson()));
    expect((backup as Map).containsKey('progress'), isFalse);
    expect(backup['playlists'], hasLength(1));

    final target = store();
    target.favorites.add(video);
    final merge = target.mergeBackup(backup);
    expect(merge.channels, 1);
    expect(merge.videos, 1);
    expect(merge.playlists, 1);
    expect(target.channels.single.id, channel.id);
    expect(target.channelGroups.single.channels, {channel.id});
    expect(target.favorites, hasLength(1));
    expect(target.watchLater.single.id, other.id);
    expect(target.playlists.single.name, 'Mine');

    // Restoring again adds nothing.
    final again = target.mergeBackup(backup);
    expect(again.changed, isFalse);
    expect(target.channelGroups, hasLength(1));
    expect(target.mergeBackup('not a map').changed, isFalse);
  });
}
