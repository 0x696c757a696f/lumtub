import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'app_directories.dart';
import 'app_log.dart';
import 'background_json.dart';
import 'l10n/l10n.dart';
import 'local_db.dart';
import 'models.dart';

/// How far into a video playback stopped.
class WatchProgress {
  const WatchProgress(this.position, this.duration);
  final Duration position;
  final Duration duration;

  double get fraction => duration > Duration.zero
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
      : 0;

  /// Watched to the credits.
  bool get finished => fraction >= 0.95;

  /// Worth resuming: past the first seconds and not at the credits.
  bool get resumable => position >= const Duration(seconds: 10) && fraction < 0.95;
}

/// A list that knows the ids of its entries, so asking whether one is in
/// it costs no scan; the index changes with the list, whoever changes it.
class IdList<T> extends ListBase<T> {
  IdList(this._idOf);
  final String Function(T) _idOf;
  final _items = <T>[];

  /// How many entries have each id.
  final _ids = <String, int>{};

  bool containsId(String id) => _ids.containsKey(id);

  void _count(T item) => _ids.update(_idOf(item), (n) => n + 1, ifAbsent: () => 1);

  void _uncount(T item) {
    final id = _idOf(item);
    final n = _ids[id];
    if (n == null) return;
    if (n <= 1) {
      _ids.remove(id);
    } else {
      _ids[id] = n - 1;
    }
  }

  @override
  int get length => _items.length;
  @override
  set length(int value) {
    for (var i = value; i < _items.length; i++) {
      _uncount(_items[i]);
    }
    _items.length = value;
  }

  @override
  T operator [](int index) => _items[index];
  @override
  void operator []=(int index, T value) {
    final old = _items[index];
    _items[index] = value;
    _uncount(old);
    _count(value);
  }

  @override
  void add(T element) {
    _items.add(element);
    _count(element);
  }

  @override
  void addAll(Iterable<T> iterable) {
    final start = _items.length;
    _items.addAll(iterable);
    for (var i = start; i < _items.length; i++) {
      _count(_items[i]);
    }
  }

  @override
  void insert(int index, T element) {
    _items.insert(index, element);
    _count(element);
  }

  @override
  bool remove(Object? element) {
    if (element is! T) return false;
    final at = _items.indexOf(element);
    if (at < 0) return false;
    _uncount(_items.removeAt(at));
    return true;
  }

  @override
  T removeAt(int index) {
    final item = _items.removeAt(index);
    _uncount(item);
    return item;
  }

  @override
  void removeWhere(bool Function(T element) test) => _items.removeWhere((item) {
        if (!test(item)) return false;
        _uncount(item);
        return true;
      });

  @override
  void retainWhere(bool Function(T element) test) => removeWhere((item) => !test(item));

  @override
  void clear() {
    _items.clear();
    _ids.clear();
  }

  @override
  void sort([int Function(T a, T b)? compare]) => _items.sort(compare);
}

class LocalPlaylist {
  LocalPlaylist({required this.id, required this.name, List<VideoItem>? items})
      : items = IdList<VideoItem>((item) => item.id)..addAll(items ?? const []);
  final String id;
  String name;
  final IdList<VideoItem> items;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'items': items.map((item) => item.toJson()).toList()};
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
  const LibraryBackup(
      {this.channels = const [],
      this.groups = const [],
      this.favorites = const [],
      this.watchLater = const [],
      this.playlists = const []});
  final List<ChannelRef> channels;
  final List<(String name, Set<String> channels)> groups;
  final List<VideoItem> favorites;
  final List<VideoItem> watchLater;
  final List<LocalPlaylist> playlists;

  Map<String, dynamic> toJson() => {
        'channels': channels.map((channel) => channel.toJson()).toList(),
        'groups': [
          for (final (name, ids) in groups) {'name': name, 'channels': ids.toList()}
        ],
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
      channels: [
        for (final value in list(raw['channels']))
          if (ChannelRef.fromJson(value) case final channel?) channel
      ],
      groups: [
        for (final value in list(raw['groups']))
          if (value is Map &&
              value['name'] is String &&
              (value['name'] as String).trim().isNotEmpty)
            (
              (value['name'] as String).trim(),
              {
                for (final id in list(value['channels']))
                  if (id is String) id
              }
            ),
      ],
      favorites: LibraryStore._items(raw['favorites']),
      watchLater: LibraryStore._items(raw['watchLater']),
      playlists: [
        for (final value in list(raw['playlists']))
          if (value is Map &&
              value['id'] is String &&
              !(value['id'] as String).startsWith(remotePlaylistPrefix))
            LocalPlaylist(
                id: value['id'] as String,
                name: value['name']?.toString() ?? '',
                items: LibraryStore._items(value['items'])),
      ],
    );
  }
}

/// [item] as JSON text, made once per item: items do not change, so a
/// list written again only encodes the ones added since.
String encodedItem(VideoItem item) => _encodedItems[item] ??= jsonEncode(item.toJson());
final _encodedItems = Expando<String>('encoded');

/// Favorites, playlists, followed channels and watch progress, stored only on
/// this computer: in `data/lumtub.db` with the Rust core, otherwise in
/// `data/library.json`. A library.json left by an earlier version is read
/// into the database once and then left as it was.
class LibraryStore {
  LibraryStore(this.file) : _db = LocalDb.enabled ? LocalDb.beside(file) : null;
  final File file;
  LocalDb? _db;

  static const _lists = [
    'favorites',
    'watchLater',
    'playlists',
    'channels',
    'groups',
    'live',
    'progress'
  ];
  static const _playlistList = 'playlist:';

  /// The playlists' item lists in the database at the last read or write.
  final _playlistLists = <String>{};

  static const _maxProgress = 500;

  final favorites = IdList<VideoItem>((item) => item.id);

  /// 稍后观看, newest first.
  final watchLater = IdList<VideoItem>((item) => item.id);
  final playlists = <LocalPlaylist>[];
  final channels = IdList<ChannelRef>((channel) => channel.id);
  final channelGroups = <ChannelGroup>[];

  /// Followed channels' videos that were live or about to go live at the
  /// last look, by video id: the channel's id and `is_live` or
  /// `is_upcoming`. Shown at once on the next launch, then checked again.
  final liveVideos = <String, (String, String)>{};
  // Insertion order is age order, so the oldest entry is dropped first.
  final _progress = <String, (int, int)>{};
  final _writes = WriteQueue();

  Future<void> load() async {
    final db = _db;
    if (db == null) return _loadJson();
    try {
      final found = await db.read(_lists, prefixes: const [_playlistList]);
      if (found.meta['library'] == '1') {
        _fill(found.lists);
        return;
      }
    } on LocalDbException catch (e) {
      if (e.setAside == null) {
        // Unreadable for now, not damaged: this session keeps the JSON file
        // rather than writing over what the database holds.
        logError('Could not read the library database, using library.json for now', e);
        _db = null;
        return _loadJson();
      }
      logError('The library database was damaged, reading library.json again', e);
    }
    await _loadJson();
    try {
      await _write(db);
      logInfo('The library is now kept in lumtub.db');
    } on LocalDbException catch (e) {
      logError('Could not move the library into lumtub.db', e);
    }
  }

  void _fill(Map<String, List<(String, Object?)>> lists) {
    List<(String, Object?)> list(String name) => lists[name] ?? const [];
    favorites.addAll(_items([for (final (_, body) in list('favorites')) body]));
    watchLater.addAll(_items([for (final (_, body) in list('watchLater')) body]));
    for (final (id, body) in list('playlists')) {
      final name = body is Map ? body['name']?.toString() : null;
      playlists.add(LocalPlaylist(
          id: id,
          name: name ?? tr('Playlist'),
          items: _items([for (final (_, item) in list('$_playlistList$id')) item])));
    }
    _playlistLists.addAll(lists.keys.where((name) => name.startsWith(_playlistList)));
    for (final (_, body) in list('channels')) {
      final channel = ChannelRef.fromJson(body);
      if (channel != null && !channels.containsId(channel.id)) channels.add(channel);
    }
    for (final (name, body) in list('groups')) {
      if (name.trim().isEmpty) continue;
      channelGroups.add(ChannelGroup(name.trim(), {
        for (final id in body is List ? body : const [])
          if (id is String) id
      }));
    }
    for (final (id, body) in list('live')) {
      if (body is List &&
          body.length == 2 &&
          body[0] is String &&
          (body[1] == 'is_live' || body[1] == 'is_upcoming')) {
        liveVideos[id] = (body[0] as String, body[1] as String);
      }
    }
    for (final (id, body) in list('progress')) {
      if (body is List && body.length >= 2 && body[0] is num && body[1] is num) {
        _progress[id] = ((body[0] as num).toInt(), (body[1] as num).toInt());
      }
    }
    finishedVersion++;
  }

  /// Hands the whole library to [db], which writes only what changed.
  Future<void> _write(LocalDb db) async {
    final items = <String, List<(String, String)>>{
      'favorites': [for (final item in favorites) (item.id, encodedItem(item))],
      'watchLater': [for (final item in watchLater) (item.id, encodedItem(item))],
      'playlists': [
        for (final playlist in playlists) (playlist.id, jsonEncode({'name': playlist.name}))
      ],
      for (final playlist in playlists)
        '$_playlistList${playlist.id}': [
          for (final item in playlist.items) (item.id, encodedItem(item))
        ],
      'channels': [for (final channel in channels) (channel.id, jsonEncode(channel.toJson()))],
      'groups': [
        for (final group in channelGroups) (group.name, jsonEncode(group.channels.toList()))
      ],
      'live': [
        for (final MapEntry(:key, :value) in liveVideos.entries)
          (key, jsonEncode([value.$1, value.$2]))
      ],
      'progress': [
        for (final MapEntry(:key, :value) in _progress.entries) (key, '[${value.$1},${value.$2}]')
      ],
    };
    final gone = _playlistLists.where((name) => !items.containsKey(name)).toList();
    await db.write(items, drop: gone, meta: const {'library': '1'});
    _playlistLists
      ..removeAll(gone)
      ..addAll(items.keys.where((name) => name.startsWith(_playlistList)));
  }

  Future<void> _loadJson() async {
    if (!await file.exists()) return;
    try {
      final data = await decodeJsonInBackground(await file.readAsString());
      if (data is! Map) throw const FormatException('Not a JSON object');
      favorites.addAll(_items(data['favorites']));
      watchLater.addAll(_items(data['watchLater']));
      for (final raw in data['playlists'] is List ? data['playlists'] as List : const []) {
        if (raw is! Map || raw['id'] is! String) continue;
        playlists.add(LocalPlaylist(
            id: raw['id'] as String,
            name: raw['name']?.toString() ?? tr('Playlist'),
            items: _items(raw['items'])));
      }
      for (final raw in data['channels'] is List ? data['channels'] as List : const []) {
        final channel = ChannelRef.fromJson(raw);
        if (channel != null && !channels.containsId(channel.id)) channels.add(channel);
      }
      for (final raw in data['groups'] is List ? data['groups'] as List : const []) {
        if (raw is! Map || raw['name'] is! String || (raw['name'] as String).trim().isEmpty) {
          continue;
        }
        final ids = raw['channels'] is List
            ? {
                for (final id in raw['channels'] as List)
                  if (id is String) id
              }
            : <String>{};
        channelGroups.add(ChannelGroup((raw['name'] as String).trim(), ids));
      }
      final live = data['live'];
      if (live is Map) {
        for (final MapEntry(:key, :value) in live.entries) {
          if (key is String &&
              value is List &&
              value.length == 2 &&
              value[0] is String &&
              (value[1] == 'is_live' || value[1] == 'is_upcoming')) {
            liveVideos[key] = (value[0] as String, value[1] as String);
          }
        }
      }
      final progress = data['progress'];
      if (progress is Map) {
        for (final entry in progress.entries) {
          final value = entry.value;
          if (value is List && value.length >= 2 && value[0] is num && value[1] is num) {
            _progress[entry.key.toString()] =
                ((value[0] as num).toInt(), (value[1] as num).toInt());
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
            if (!playlist.id.startsWith(remotePlaylistPrefix))
              LocalPlaylist(id: playlist.id, name: playlist.name, items: List.of(playlist.items)),
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
        'live': {
          for (final MapEntry(:key, :value) in liveVideos.entries) key: [value.$1, value.$2]
        },
        'progress': {
          for (final entry in _progress.entries) entry.key: [entry.value.$1, entry.value.$2]
        },
      };

  /// Writes to a temporary file first so a crash never leaves half a file.
  /// Saves run one after another and read the state when they start, so
  /// the latest state is written last.
  Future<void> save() => _writes.run(() async {
        if (_db case final db?) {
          try {
            await _write(db);
          } on LocalDbException catch (e) {
            // Kept in memory; the next save sends everything again.
            logError('Could not save the library', e);
          }
          return;
        }
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
    return value == null
        ? null
        : WatchProgress(Duration(seconds: value.$1), Duration(seconds: value.$2));
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

  bool isFavorite(String id) => favorites.containsId(id);

  /// Adds or removes [item]; returns whether it is now a favorite.
  bool toggleFavorite(VideoItem item) {
    if (isFavorite(item.id)) {
      favorites.removeWhere((other) => other.id == item.id);
      return false;
    }
    favorites.insert(0, item);
    return true;
  }

  bool isWatchLater(String id) => watchLater.containsId(id);

  /// Adds or removes [item] from 稍后观看; returns whether it is now there.
  bool toggleWatchLater(VideoItem item) {
    if (removeWatchLater(item.id)) return false;
    watchLater.insert(0, item);
    return true;
  }

  /// Takes [id] off 稍后观看; false when it was not there.
  bool removeWatchLater(String id) {
    if (!watchLater.containsId(id)) return false;
    final before = watchLater.length;
    watchLater.removeWhere((item) => item.id == id);
    return watchLater.length != before;
  }

  LocalPlaylist createPlaylist(String name) {
    final playlist = LocalPlaylist(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        name: name.trim().isEmpty ? tr('Untitled playlist') : name.trim());
    playlists.add(playlist);
    return playlist;
  }

  /// Adds [item] at the end of [playlist]; false when it was already there.
  bool addToPlaylist(LocalPlaylist playlist, VideoItem item) {
    if (playlist.items.containsId(item.id)) return false;
    playlist.items.add(item);
    return true;
  }

  bool isFollowing(String channelId) => channels.containsId(channelId);

  bool toggleFollow(ChannelRef channel) {
    if (channels.remove(channel)) return false;
    channels.add(channel);
    return true;
  }
}
