import 'dart:convert';
import 'dart:io';

import 'background_json.dart';
import 'models.dart';
import 'l10n/l10n.dart';

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
  // Insertion order is age order, so the oldest entry is dropped first.
  final _progress = <String, (int, int)>{};

  Future<void> load() async {
    if (!await file.exists()) return;
    try {
      final data = await decodeJsonInBackground(await file.readAsString());
      if (data is! Map) return;
      favorites.addAll(_items(data['favorites']));
      watchLater.addAll(_items(data['watchLater']));
      for (final raw in data['playlists'] is List ? data['playlists'] as List : const []) {
        if (raw is! Map || raw['id'] is! String) continue;
        playlists.add(LocalPlaylist(id: raw['id'] as String, name: raw['name']?.toString() ?? tr('播放列表'), items: _items(raw['items'])));
      }
      for (final raw in data['channels'] is List ? data['channels'] as List : const []) {
        final channel = ChannelRef.fromJson(raw);
        if (channel != null && !channels.contains(channel)) channels.add(channel);
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
    } catch (_) {
      // A damaged file starts an empty library rather than blocking startup.
    }
  }

  static List<VideoItem> _items(Object? raw) {
    final items = <VideoItem>[];
    for (final value in raw is List ? raw : const []) {
      try {
        if (value is Map<String, dynamic>) items.add(VideoItem.fromJson(value));
      } catch (_) {}
    }
    return items;
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'favorites': favorites.map((item) => item.toJson()).toList(),
        'watchLater': watchLater.map((item) => item.toJson()).toList(),
        'playlists': playlists.map((playlist) => playlist.toJson()).toList(),
        'channels': channels.map((channel) => channel.toJson()).toList(),
        'progress': {for (final entry in _progress.entries) entry.key: [entry.value.$1, entry.value.$2]},
      };

  /// Writes to a temporary file first so a crash never leaves half a file.
  Future<void> save() async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(toJson()), flush: true);
    await temp.rename(file.path);
  }

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
    final playlist = LocalPlaylist(id: DateTime.now().microsecondsSinceEpoch.toRadixString(36), name: name.trim().isEmpty ? tr('新播放列表') : name.trim());
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
