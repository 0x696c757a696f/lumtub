import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../channel_avatars.dart';
import '../app_log.dart';
import '../channel_feed.dart';
import '../library_store.dart';
import '../map_limited.dart';
import '../models.dart';
import '../native_http.dart';
import '../video_repository.dart';
import '../youtube_player_probe.dart';

export '../map_limited.dart';

/// Favorites, playlists, followed channels, watch progress and the feed of
/// followed channels. Everything stays on this computer.
class LibraryController extends ChangeNotifier {
  LibraryController(this.store, {http.Client? client}) : _client = client ?? appHttpClient();

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
      for (final group in store.channelGroups) {
        group.channels.remove(channel.id);
      }
    }
    _changed();
    return following;
  }

  List<ChannelGroup> get channelGroups => store.channelGroups;

  /// A new 订阅分组 named [name], with [channels] in it.
  ChannelGroup addGroup(String name, [Set<String>? channels]) {
    final group = ChannelGroup(name.trim(), channels);
    store.channelGroups.add(group);
    _changed();
    return group;
  }

  void renameGroup(ChannelGroup group, String name) {
    if (name.trim().isEmpty) return;
    group.name = name.trim();
    _changed();
  }

  void removeGroup(ChannelGroup group) {
    store.channelGroups.remove(group);
    _changed();
  }

  /// Puts [channelId] in [group] or takes it out.
  void setInGroup(ChannelGroup group, String channelId, bool inGroup) {
    if (inGroup ? !group.channels.add(channelId) : !group.channels.remove(channelId)) return;
    _changed();
  }

  /// Follows each of [channels] not yet followed; returns how many were new.
  int followAll(List<ChannelRef> channels) {
    var added = 0;
    var updated = false;
    final index = {for (var i = 0; i < store.channels.length; i++) store.channels[i].id: i};
    for (final channel in channels) {
      final at = index[channel.id] ?? -1;
      if (at >= 0) {
        // Keep pictures and names current for channels already followed.
        final known = store.channels[at];
        if (channel.avatar != null && (channel.avatar != known.avatar || channel.name != known.name)) {
          store.channels[at] = channel;
          updated = true;
        }
        continue;
      }
      index[channel.id] = store.channels.length;
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

  /// A copy of the followed channels, groups, favorites, 稍后观看 and own
  /// playlists, for the settings backup.
  LibraryBackup backup() => store.backup();

  /// Adds what [backup] has and this library lacks.
  LibraryMerge restoreBackup(LibraryBackup backup) {
    final merge = store.mergeBackup(backup);
    if (merge.channels > 0) {
      _feedLoadedAt = null;
      unawaited(fillMissingAvatars());
    }
    _changed();
    return merge;
  }

  /// Playlists copied from the YouTube account have ids starting with this.
  static const remotePrefix = remotePlaylistPrefix;

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
    _checked.clear();
    notifyListeners();
    // What was live at the last look is asked about again at once, while
    // the feeds load, so the 直播 marks are right before the feed is in.
    final early = _checkLive([for (final MapEntry(:key, :value) in store.liveVideos.entries) (key, value.$1)]);
    final failures = <String>[];
    // A few requests at a time: hundreds of imported subscriptions would
    // otherwise open hundreds of connections at once and, where the feed
    // fails, start as many yt-dlp processes.
    final feedErrors = <int, Object>{};
    final results = await mapLimited(channels, feedConcurrency, (channel) async {
      try {
        return await _feed.latest(channel, fresh: force);
      } catch (e) {
        feedErrors[channels.indexOf(channel)] = e;
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
      } catch (e) {
        // Why each channel failed, for the log: a channel gone or renamed
        // fails here every time.
        final channel = channels[i];
        logWarn('Could not load the uploads of ${channel.name} (${channel.id}): feed: ${feedErrors[i]}; yt-dlp: $e');
        return null;
      }
    });
    for (final (n, i) in missing.indexed) {
      final list = n < fallback.length ? fallback[n] : null;
      results[i] = list;
      if (list == null) failures.add(channels[i].name.isEmpty ? channels[i].id : channels[i].name);
      if (list == null && n >= fallback.length) logWarn('Could not load the uploads of ${channels[i].name} (${channels[i].id}): feed: ${feedErrors[i]}');
    }
    final merged = mergeFeeds([for (final list in results) if (list != null) list]).take(maxFeedItems).toList();
    feed = _marked(merged) ?? merged;
    feedFailures = failures;
    loadingFeed = false;
    _feedLoadedAt = DateTime.now();
    notifyListeners();
    unawaited(fillMissingAvatars());
    await early;
    await _markLive();
  }

  /// How recent a feed video has to be to be checked for being live: a
  /// stream shows in the feed from when it is scheduled.
  static const liveWindow = Duration(days: 2);

  /// Live lookups in flight at once.
  static const liveConcurrency = 6;

  late final _probe = YoutubePlayerProbe(_client);

  /// What this refresh learnt, by video id: `is_live`, `is_upcoming`,
  /// `was_live` for one that has ended since the last look, or null.
  final _checked = <String, String?>{};

  Timer? _liveTimer;

  /// Channels streaming now, as far as is known: from the feed, and from
  /// the last look until it is checked again.
  Set<String> get liveChannels => {
        for (final item in feed) if (item.isLive && item.channelId != null) item.channelId!,
        for (final (channel, status) in store.liveVideos.values) if (status == 'is_live') channel,
      };

  /// Marks the feed's videos that are live now or about to be: channel
  /// feeds do not say, so each recent video is asked, a few at a time,
  /// those live at the last look first.
  Future<void> _markLive() async {
    final since = DateTime.now().subtract(liveWindow);
    final checked = [
      for (final item in feed)
        if (!_checked.containsKey(item.id) && (store.liveVideos.containsKey(item.id) || (item.published?.isAfter(since) ?? false))) (item.id, item.channelId),
    ];
    await _checkLive(checked);
  }

  /// Asks whether each of [videos] (id, channel id) is live, showing each
  /// answer within a moment rather than after the last one.
  Future<void> _checkLive(List<(String, String?)> videos) async {
    if (videos.isEmpty) return;
    await mapLimited(videos, liveConcurrency, (video) async {
      final (id, channel) = video;
      String? state;
      try {
        state = await liveStateOf(await _probe.fetch(id, 'videoDetails.videoId,videoDetails.isLive,videoDetails.isUpcoming', expect: 'videoDetails'));
      } catch (_) {
        // Offline or refused: what was known stays.
        return;
      }
      final known = store.liveVideos[id];
      // A stream that was on at the last look and is not any more has ended.
      _checked[id] = state ?? (known != null ? 'was_live' : null);
      if (state != null && channel != null) {
        store.liveVideos[id] = (channel, state);
      } else if (state == null) {
        store.liveVideos.remove(id);
      }
      if (known?.$2 != state) _liveTimer ??= Timer(const Duration(milliseconds: 300), _showLive);
    });
    _liveTimer?.cancel();
    _showLive();
  }

  void _showLive() {
    _liveTimer = null;
    final marked = _marked(feed);
    if (marked != null) feed = marked;
    _changed();
  }

  /// [items] with what is known about which are live, or null when nothing
  /// changes.
  List<VideoItem>? _marked(List<VideoItem> items) {
    var changed = false;
    final marked = <VideoItem>[];
    for (final item in items) {
      var state = _checked.containsKey(item.id) ? _checked[item.id] : store.liveVideos[item.id]?.$2 ?? item.liveStatus;
      // A stream that was on and is not any more has ended.
      if (state == null && (item.isLive || item.isUpcoming || item.liveStatus == 'was_live')) state = 'was_live';
      if (state != item.liveStatus) {
        changed = true;
        marked.add(item.withLiveStatus(state));
      } else {
        marked.add(item);
      }
    }
    return changed ? marked : null;
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
    _liveTimer?.cancel();
    if (_saveTimer != null) unawaited(flush());
    super.dispose();
  }
}

/// `is_live`, `is_upcoming` or null, from a `/player` answer's
/// `videoDetails`.
Future<String?> liveStateOf(List<int> bytes) async {
  // A whole answer, when YouTube refused the field mask, runs to a few
  // hundred kilobytes.
  final data = bytes.length > 64 * 1024 ? await Isolate.run(() => jsonDecode(utf8.decode(bytes))) : jsonDecode(utf8.decode(bytes));
  final details = data is Map<String, dynamic> ? data['videoDetails'] : null;
  if (details is! Map<String, dynamic>) return null;
  if (details['isLive'] == true) return 'is_live';
  if (details['isUpcoming'] == true) return 'is_upcoming';
  return null;
}
