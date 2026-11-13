import 'dart:convert';
import 'dart:io';

import 'app_directories.dart';
import 'background_json.dart';
import 'models.dart';
import 'l10n/l10n.dart';
import 'app_log.dart';

/// How far into a video playback stopped.
class WatchProgress {
  const WatchProgress(this.position, this.duration);
  final Duration position;
  final Duration duration;

  double get fraction => duration > Duration.zero ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0) : 0;

  /// Watched to the credits.
  bool get finished => fraction >= 0.95;

  /// Worth resuming: past the first seconds and not at the credits.
  bool get resumable => position >= const Duration(seconds: 10) && fraction < 0.95;
}

class LocalPlaylist {
  LocalPlaylist({required this.id, required this.name, List<VideoItem>? items}) : items = items ?? [];
  final String id;
  String name;
  final List<VideoItem> items;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'items': items.map((item) => item.toJson()).toList()};
}

/// 订阅分组: a name and the followed channels in it, by id.
class ChannelGroup {
  ChannelGroup(this.name, [Set<String>? channels]) : channels = channels ?? {};
  String name;
  final Set<String> channels;

  Map<String, dynamic> toJson() => {'name': name, 'channels': channels.toList()};
}

/// Playlists copied from the YouTube account have ids starting with this.
const remotePlaylistPrefix = 'yt:';

/// What restoring a backup added to the library.
class LibraryMerge {
  const LibraryMerge({this.channels = 0, this.videos = 0, this.playlists = 0});
  final int channels;
  final int videos;
  final int playlists;

  bool get changed => channels > 0 || videos > 0 || playlists > 0;
}

/// What a settings backup carries of the library: followed channels and
/// their groups, favorites, 稍后观看 and the user's own playlists. Copies of
/// the YouTube account's playlists, watch progress and live marks belong to
/// this computer and are left out.
class LibraryBackup {
  const LibraryBackup({this.channels = const [], this.groups = const [], this.favorites = const [], this.watchLater = const [], this.playlists = const []});
  final List<ChannelRef> channels;
  final List<(String name, Set<String> channels)> groups;
  final List<VideoItem> favorites;
  final List<VideoItem> watchLater;
  final List<LocalPlaylist> playlists;

  Map<String, dynamic> toJson() => {
        'channels': channels.map((channel) => channel.toJson()).toList(),
        'groups': [for (final (name, ids) in groups) {'name': name, 'channels': ids.toList()}],
        'favorites': favorites.map((item) => item.toJson()).toList(),
        'watchLater': watchLater.map((item) => item.toJson()).toList(),
        'playlists': playlists.map((playlist) => playlist.toJson()).toList(),
      };

  /// Reads the `library` part of a settings backup; anything unreadable is
  /// skipped. Meant to run away from the UI isolate.
  static LibraryBackup parse(Object? raw) {
    if (raw is! Map) return const LibraryBackup();
    List<Object?> list(Object? value) => value is List ? value : const [];
    return LibraryBackup(
      channels: [for (final value in list(raw['channels'])) if (ChannelRef.fromJson(value) case final channel?) channel],
      groups: [
        for (final value in list(raw['groups']))
          if (value is Map && value['name'] is String && (value['name'] as String).trim().isNotEmpty)
            ((value['name'] as String).trim(), {for (final id in list(value['channels'])) if (id is String) id}),
      ],
      favorites: LibraryStore._items(raw['favorites']),
      watchLater: LibraryStore._items(raw['watchLater']),
      playlists: [
        for (final value in list(raw['playlists']))
          if (value is Map && value['id'] is String && !(value['id'] as String).startsWith(remotePlaylistPrefix))
            LocalPlaylist(id: value['id'] as String, name: value['name']?.toString() ?? '', items: LibraryStore._items(value['items'])),
      ],
    );
  }
}

/// Favorites, playlists, followed channels and watch progress, stored only on
/// this computer in `data/library.json`.
class LibraryStore {
  LibraryStore(this.file);
  final File file;

  static const _maxProgress = 500;

  final favorites = <VideoItem>[];
  /// 稍后观看, newest first.
  final watchLater = <VideoItem>[];
  final playlists = <LocalPlaylist>[];
  final channels = <ChannelRef>[];
  final channelGroups = <ChannelGroup>[];
  /// Followed channels' videos that were live or about to go live at the
  /// last look, by video id: the channel's id and `is_live` or
  /// `is_upcoming`. Shown at once on the next launch, then checked again.
  final liveVideos = <String, (String, String)>{};
  // Insertion order is age order, so the oldest entry is dropped first.
  final _progress = <String, (int, int)>{};
  final _writes = WriteQueue();

  Future<void> load() async {
    if (!await file.exists()) return;
    try {
      final data = await decodeJsonInBackground(await file.readAsString());
      if (data is! Map) throw const FormatException('Not a JSON object');
      favorites.addAll(_items(data['favorites']));
      watchLater.addAll(_items(data['watchLater']));
      for (final raw in data['playlists'] is List ? data['playlists'] as List : const []) {
        if (raw is! Map || raw['id'] is! String) continue;
        playlists.add(LocalPlaylist(id: raw['id'] as String, name: raw['name']?.toString() ?? tr('Playlist'), items: _items(raw['items'])));
      }
      for (final raw in data['channels'] is List ? data['channels'] as List : const []) {
        final channel = ChannelRef.fromJson(raw);
        if (channel != null && !channels.contains(channel)) channels.add(channel);
      }
      for (final raw in data['groups'] is List ? data['groups'] as List : const []) {
        if (raw is! Map || raw['name'] is! String || (raw['name'] as String).trim().isEmpty) continue;
        final ids = raw['channels'] is List ? {for (final id in raw['channels'] as List) if (id is String) id} : <String>{};
        channelGroups.add(ChannelGroup((raw['name'] as String).trim(), ids));
      }
      final live = data['live'];
      if (live is Map) {
        for (final MapEntry(:key, :value) in live.entries) {
          if (key is String && value is List && value.length == 2 && value[0] is String && (value[1] == 'is_live' || value[1] == 'is_upcoming')) {
            liveVideos[key] = (value[0] as String, value[1] as String);
          }
        }
      }
      final progress = data['progress'];
      if (progress is Map) {
        for (final entry in progress.entries) {
          final value = entry.value;
          if (value is List && value.length >= 2 && value[0] is num && value[1] is num) {
            _progress[entry.key.toString()] = ((value[0] as num).toInt(), (value[1] as num).toInt());
          }
        }
        finishedVersion++;
      }
    } catch (e) {
      // A damaged file starts an empty library rather than blocking startup;
      // it is kept aside so the next save does not overwrite it.
      favorites.clear();
      watchLater.clear();
      playlists.clear();
      channels.clear();
      channelGroups.clear();
      liveVideos.clear();
      _progress.clear();
      await setBrokenFileAside(file, e);
    }
  }

  static List<VideoItem> _items(Object? raw) {
    final items = <VideoItem>[];
    for (final value in raw is List ? raw : const []) {
      try {
        if (value is Map<String, dynamic>) items.add(VideoItem.fromJson(value));
      } catch (e) {
        logWarn('Skipped a library item that could not be read: $e');
      }
    }
    return items;
  }

  /// A copy of what a backup holds, taken on the UI isolate so it can be
  /// turned into JSON on another.
  LibraryBackup backup() => LibraryBackup(
        channels: List.of(channels),
        groups: [for (final group in channelGroups) (group.name, Set.of(group.channels))],
        favorites: List.of(favorites),
        watchLater: List.of(watchLater),
        playlists: [
          for (final playlist in playlists)
            if (!playlist.id.startsWith(remotePlaylistPrefix)) LocalPlaylist(id: playlist.id, name: playlist.name, items: List.of(playlist.items)),
        ],
      );

  /// Adds what [backup] has and this library lacks; nothing here is removed
  /// or replaced. Lookups go through sets, so this stays quick for
  /// thousands of entries; the parsing is done beforehand by
  /// [LibraryBackup.parse], away from the UI isolate.
  LibraryMerge mergeBackup(LibraryBackup backup) {
    final followed = {for (final channel in channels) channel.id};
    var channelsAdded = 0;
    for (final channel in backup.channels) {
      if (!followed.add(channel.id)) continue;
      channels.add(channel);
      channelsAdded++;
    }
    for (final (name, ids) in backup.groups) {
      final kept = ids.where(followed.contains);
      final group = channelGroups.where((group) => group.name == name).firstOrNull;
      if (group == null) {
        channelGroups.add(ChannelGroup(name, kept.toSet()));
      } else {
        group.channels.addAll(kept);
      }
    }
    var videosAdded = 0;
    void addMissing(List<VideoItem> into, List<VideoItem> from) {
      final known = {for (final item in into) item.id};
      for (final item in from) {
        if (known.add(item.id)) {
          into.add(item);
          videosAdded++;
        }
      }
    }

    addMissing(favorites, backup.favorites);
    addMissing(watchLater, backup.watchLater);
    var playlistsAdded = 0;
    final byId = {for (final playlist in playlists) playlist.id: playlist};
    for (final playlist in backup.playlists) {
      final known = byId[playlist.id];
      if (known == null) {
        if (playlist.name.trim().isEmpty) playlist.name = tr('Playlist');
        playlists.add(playlist);
        byId[playlist.id] = playlist;
        playlistsAdded++;
      } else {
        addMissing(known.items, playlist.items);
      }
    }
    return LibraryMerge(channels: channelsAdded, videos: videosAdded, playlists: playlistsAdded);
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'favorites': favorites.map((item) => item.toJson()).toList(),
        'watchLater': watchLater.map((item) => item.toJson()).toList(),
        'playlists': playlists.map((playlist) => playlist.toJson()).toList(),
        'channels': channels.map((channel) => channel.toJson()).toList(),
        'groups': channelGroups.map((group) => group.toJson()).toList(),
        'live': {for (final MapEntry(:key, :value) in liveVideos.entries) key: [value.$1, value.$2]},
        'progress': {for (final entry in _progress.entries) entry.key: [entry.value.$1, entry.value.$2]},
      };

  /// Writes to a temporary file first so a crash never leaves half a file.
  /// Saves run one after another and read the state when they start, so
  /// the latest state is written last.
  Future<void> save() => _writes.run(() async {
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(jsonEncode(toJson()), flush: true);
        await temp.rename(file.path);
      });

  /// Forgets every position, for the privacy settings.
  void clearProgress() {
    _progress.clear();
    finishedVersion++;
  }

  /// Changes whenever a video becomes watched to the end or stops being
  /// so, for lists that hide watched videos to know when to filter again.
  int finishedVersion = 0;

  WatchProgress? progressOf(String id) {
    final value = _progress[id];
    return value == null ? null : WatchProgress(Duration(seconds: value.$1), Duration(seconds: value.$2));
  }

  /// Remembers where [id] stopped. A finished video is kept as watched to
  /// the end, which is not resumable, so it starts from the beginning.
  void setProgress(String id, Duration position, Duration duration) {
    final wasFinished = progressOf(id)?.finished ?? false;
    _progress.remove(id);
    if (duration <= Duration.zero) {
      if (wasFinished) finishedVersion++;
      return;
    }
    final finished = WatchProgress(position, duration).fraction >= 0.95;
    if (finished != wasFinished) finishedVersion++;
    _progress[id] = (finished ? duration.inSeconds : position.inSeconds, duration.inSeconds);
    while (_progress.length > _maxProgress) {
      final (seconds, total) = _progress.remove(_progress.keys.first)!;
      if (total > 0 && seconds / total >= 0.95) finishedVersion++;
    }
  }

  bool isFavorite(String id) => favorites.any((item) => item.id == id);

  /// Adds or removes [item]; returns whether it is now a favorite.
  bool toggleFavorite(VideoItem item) {
    if (isFavorite(item.id)) {
      favorites.removeWhere((other) => other.id == item.id);
      return false;
    }
    favorites.insert(0, item);
    return true;
  }

  bool isWatchLater(String id) => watchLater.any((item) => item.id == id);

  /// Adds or removes [item] from 稍后观看; returns whether it is now there.
  bool toggleWatchLater(VideoItem item) {
    if (removeWatchLater(item.id)) return false;
    watchLater.insert(0, item);
    return true;
  }

  /// Takes [id] off 稍后观看; false when it was not there.
  bool removeWatchLater(String id) {
    final before = watchLater.length;
    watchLater.removeWhere((item) => item.id == id);
    return watchLater.length != before;
  }

  LocalPlaylist createPlaylist(String name) {
    final playlist = LocalPlaylist(id: DateTime.now().microsecondsSinceEpoch.toRadixString(36), name: name.trim().isEmpty ? tr('Untitled playlist') : name.trim());
    playlists.add(playlist);
    return playlist;
  }

  /// Adds [item] at the end of [playlist]; false when it was already there.
  bool addToPlaylist(LocalPlaylist playlist, VideoItem item) {
    if (playlist.items.any((other) => other.id == item.id)) return false;
    playlist.items.add(item);
    return true;
  }

  bool isFollowing(String channelId) => channels.any((channel) => channel.id == channelId);

  bool toggleFollow(ChannelRef channel) {
    if (channels.remove(channel)) return false;
    channels.add(channel);
    return true;
  }
}
