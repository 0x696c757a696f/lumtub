import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../channel_feed.dart';
import '../library_store.dart';
import '../models.dart';
import '../video_repository.dart';

/// Favorites, playlists, followed channels, watch progress and the feed of
/// followed channels. Everything stays on this computer.
class LibraryController extends ChangeNotifier {
  LibraryController(this.store, {http.Client? client}) : _feed = ChannelFeed(client ?? http.Client());

  final LibraryStore store;
  final ChannelFeed _feed;
  VideoRepository? repository;

  List<VideoItem> feed = const [];
  bool loadingFeed = false;
  /// Channels whose latest videos could not be loaded.
  List<String> feedFailures = const [];
  DateTime? _feedLoadedAt;

  Timer? _saveTimer;

  List<VideoItem> get favorites => store.favorites;
  List<LocalPlaylist> get playlists => store.playlists;
  List<ChannelRef> get channels => store.channels;

  bool isFavorite(String id) => store.isFavorite(id);
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
    for (final channel in channels) {
      if (store.isFollowing(channel.id)) continue;
      store.channels.add(channel);
      added++;
    }
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
    final results = await Future.wait(channels.map((channel) async {
      try {
        return await _feed.latest(channel);
      } catch (_) {
        try {
          final repository = this.repository;
          if (repository == null) throw StateError('yt-dlp is not ready');
          return await repository.channelVideos(channel, count: 10).toList();
        } catch (_) {
          failures.add(channel.name.isEmpty ? channel.id : channel.name);
          return const <VideoItem>[];
        }
      }
    }));
    feed = mergeFeeds(results);
    feedFailures = failures;
    loadingFeed = false;
    _feedLoadedAt = DateTime.now();
    notifyListeners();
  }

  /// Newest first; videos without a date keep their channel's order after
  /// the dated ones.
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
