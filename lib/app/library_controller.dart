import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../channel_avatars.dart';
import '../channel_feed.dart';
import '../library_store.dart';
import '../models.dart';
import '../video_repository.dart';

/// Favorites, playlists, followed channels, watch progress and the feed of
/// followed channels. Everything stays on this computer.
class LibraryController extends ChangeNotifier {
  LibraryController(this.store, {http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  final LibraryStore store;
  late final _feed = ChannelFeed(_client);
  late final _avatars = ChannelAvatars(_client);
  /// Channels whose picture was looked up this session, found or not.
  final _avatarTried = <String>{};
  bool _fillingAvatars = false;
  VideoRepository? repository;

  List<VideoItem> feed = const [];
  bool loadingFeed = false;
  /// Channels whose latest videos could not be loaded.
  List<String> feedFailures = const [];
  DateTime? _feedLoadedAt;

  Timer? _saveTimer;

  List<VideoItem> get favorites => store.favorites;
  List<VideoItem> get watchLater => store.watchLater;
  List<LocalPlaylist> get playlists => store.playlists;
  List<ChannelRef> get channels => store.channels;

  bool isFavorite(String id) => store.isFavorite(id);
  bool isWatchLater(String id) => store.isWatchLater(id);
  bool isFollowing(String channelId) => store.isFollowing(channelId);
  WatchProgress? progressOf(String id) => store.progressOf(id);

  LocalPlaylist? playlist(String id) {
    for (final playlist in store.playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  /// Saves shortly after the last change, so progress updates during
  /// playback do not write the file every few seconds.
  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () => unawaited(flush()));
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      await store.save();
    } on FileSystemException {
      // Kept in memory; the next change tries again.
    }
  }

  /// Records playback position; listeners are not notified because only
  /// cards drawn later need the new value. Playback reports a position every
  /// few seconds, so these are written at most twice a minute.
  void recordProgress(String id, Duration position, Duration duration) {
    store.setProgress(id, position, duration);
    _saveTimer ??= Timer(const Duration(seconds: 30), () => unawaited(flush()));
  }

  void clearProgress() {
    store.clearProgress();
    _changed();
  }

  bool toggleFavorite(VideoItem item) {
    final added = store.toggleFavorite(item);
    _changed();
    return added;
  }

  /// Adds or removes [item] from 稍后观看; returns whether it is now there.
  bool toggleWatchLater(VideoItem item) {
    final added = store.toggleWatchLater(item);
    _changed();
    return added;
  }

  void removeWatchLater(String id) {
    if (store.removeWatchLater(id)) _changed();
  }

  void clearWatchLater() {
    if (store.watchLater.isEmpty) return;
    store.watchLater.clear();
    _changed();
  }

  LocalPlaylist createPlaylist(String name) {
    final playlist = store.createPlaylist(name);
    _changed();
    return playlist;
  }

  bool addToPlaylist(LocalPlaylist playlist, VideoItem item) {
    final added = store.addToPlaylist(playlist, item);
    if (added) _changed();
    return added;
  }

  void removeFromPlaylist(LocalPlaylist playlist, VideoItem item) {
    playlist.items.removeWhere((other) => other.id == item.id);
    _changed();
  }

  void renamePlaylist(LocalPlaylist playlist, String name) {
    if (name.trim().isEmpty) return;
    playlist.name = name.trim();
    _changed();
  }

  void deletePlaylist(LocalPlaylist playlist) {
    store.playlists.remove(playlist);
    _changed();
  }

  bool toggleFollow(ChannelRef channel) {
    final following = store.toggleFollow(channel);
    if (following) {
      _feedLoadedAt = null;
    } else {
      feed = feed.where((item) => item.channelId != channel.id).toList();
    }
    _changed();
    return following;
  }

  /// Follows each of [channels] not yet followed; returns how many were new.
  int followAll(List<ChannelRef> channels) {
    var added = 0;
    var updated = false;
    for (final channel in channels) {
      final at = store.channels.indexOf(channel);
      if (at >= 0) {
        // Keep pictures and names current for channels already followed.
        final known = store.channels[at];
        if (channel.avatar != null && (channel.avatar != known.avatar || channel.name != known.name)) {
          store.channels[at] = channel;
          updated = true;
        }
        continue;
      }
      store.channels.add(channel);
      added++;
    }
    if (updated && added == 0) _changed();
    if (added > 0) {
      _feedLoadedAt = null;
      _changed();
    }
    return added;
  }

  /// Playlists copied from the YouTube account have ids starting with this.
  static const remotePrefix = 'yt:';

  static bool isRemote(LocalPlaylist playlist) => playlist.id.startsWith(remotePrefix);

  /// Replaces the copies of the account's playlists with [remote], keyed by
  /// YouTube playlist id. Copies of playlists deleted on YouTube go too;
  /// the user's own playlists are not touched.
  void mirrorRemotePlaylists(Map<String, ({String name, List<VideoItem> items})> remote) {
    final playlists = store.playlists;
    playlists.removeWhere((playlist) => isRemote(playlist) && !remote.containsKey(playlist.id.substring(remotePrefix.length)));
    for (final MapEntry(key: id, value: (:name, :items)) in remote.entries) {
      final index = playlists.indexWhere((playlist) => playlist.id == '$remotePrefix$id');
      final copy = LocalPlaylist(id: '$remotePrefix$id', name: name, items: List.of(items));
      if (index < 0) {
        playlists.add(copy);
      } else {
        playlists[index] = copy;
      }
    }
    _changed();
  }

  /// Replaces one mirrored YouTube playlist, after a change made from here.
  void mirrorRemotePlaylist(String id, String name, List<VideoItem> items) {
    final playlists = store.playlists;
    final copy = LocalPlaylist(id: '$remotePrefix$id', name: name, items: List.of(items));
    final index = playlists.indexWhere((playlist) => playlist.id == copy.id);
    if (index < 0) {
      playlists.add(copy);
    } else {
      playlists[index] = copy;
    }
    _changed();
  }

  /// Loads the newest uploads of every followed channel, at most once per
  /// [interval] unless [force]d. Each channel's feed is tried first; yt-dlp is
  /// the fallback when YouTube's feed is unavailable.
  Future<void> refreshFeed({bool force = false, Duration interval = const Duration(minutes: 10)}) async {
    if (loadingFeed) return;
    final loadedAt = _feedLoadedAt;
    if (!force && loadedAt != null && DateTime.now().difference(loadedAt) < interval) return;
    final channels = List.of(store.channels);
    loadingFeed = true;
    notifyListeners();
    final failures = <String>[];
    // A few requests at a time: hundreds of imported subscriptions would
    // otherwise open hundreds of connections at once and, where the feed
    // fails, start as many yt-dlp processes.
    final results = await mapLimited(channels, feedConcurrency, (channel) async {
      try {
        return await _feed.latest(channel);
      } catch (_) {
        return null;
      }
    });
    final missing = [for (final (i, list) in results.indexed) if (list == null) i];
    // yt-dlp is the slow, heavy fallback: two at a time, for a few channels.
    final fallback = await mapLimited(missing.take(maxFeedFallbacks).toList(), 2, (i) async {
      try {
        final repository = this.repository;
        if (repository == null) throw StateError('yt-dlp is not ready');
        final listing = repository.channelVideos(channels[i]);
        try {
          return (await listing.next(10).toList()).whereType<VideoItem>().toList();
        } finally {
          listing.close();
        }
      } catch (_) {
        return null;
      }
    });
    for (final (n, i) in missing.indexed) {
      final list = n < fallback.length ? fallback[n] : null;
      results[i] = list;
      if (list == null) failures.add(channels[i].name.isEmpty ? channels[i].id : channels[i].name);
    }
    feed = mergeFeeds([for (final list in results) if (list != null) list]).take(maxFeedItems).toList();
    feedFailures = failures;
    loadingFeed = false;
    _feedLoadedAt = DateTime.now();
    notifyListeners();
    unawaited(fillMissingAvatars());
  }

  /// Looks up the picture of each followed channel that has none, a few at a
  /// time and once per session, and keeps what it finds with the channel.
  Future<void> fillMissingAvatars({int concurrency = 3}) async {
    if (_fillingAvatars) return;
    _fillingAvatars = true;
    try {
      final queue = [for (final channel in store.channels) if (channel.avatar == null && _avatarTried.add(channel.id)) channel];
      var found = false;
      Future<void> worker() async {
        while (queue.isNotEmpty) {
          final channel = queue.removeLast();
          try {
            final avatar = await _avatars.fetch(channel);
            final at = store.channels.indexOf(channel);
            if (avatar != null && at >= 0 && store.channels[at].avatar == null) {
              store.channels[at] = ChannelRef(channel.id, store.channels[at].name, avatar);
              found = true;
            }
          } catch (_) {
            // Offline or blocked: the letter avatar stays.
          }
        }
      }

      await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
      if (found) _changed();
    } finally {
      _fillingAvatars = false;
    }
  }

  /// [channel]'s newest videos from its feed, for recommendations.
  Future<List<VideoItem>> uploadsOf(ChannelRef channel) => _feed.latest(channel);

  /// Newest first; videos without a date keep their channel's order after
  /// the dated ones.
  /// Feed requests in flight at once.
  static const feedConcurrency = 8;
  /// Channels whose feed failed that yt-dlp is asked about, per refresh.
  static const maxFeedFallbacks = 12;
  /// The newest videos kept from all the feeds together.
  static const maxFeedItems = 1500;

  static List<VideoItem> mergeFeeds(List<List<VideoItem>> perChannel) {
    final seen = <String>{};
    final all = [for (final list in perChannel) ...list].where((item) => seen.add(item.id)).toList();
    final dated = all.where((item) => item.published != null).toList()..sort((a, b) => b.published!.compareTo(a.published!));
    return [...dated, ...all.where((item) => item.published == null)];
  }

  @override
  void dispose() {
    if (_saveTimer != null) unawaited(flush());
    super.dispose();
  }
}

/// [work] on each of [items], at most [limit] at a time, results in order.
Future<List<R>> mapLimited<T, R>(List<T> items, int limit, Future<R> Function(T item) work) async {
  final results = List<R?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final i = next++;
      results[i] = await work(items[i]);
    }
  }

  await Future.wait([for (var i = 0; i < limit && i < items.length; i++) worker()]);
  return results.cast<R>();
}
