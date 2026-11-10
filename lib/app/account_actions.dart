part of 'app_controller.dart';

/// Sign-in changes and the account lists on the YouTube side.
extension AccountActions on AppController {
  /// The history keeps a video as it was when it was watched, so a stream
  /// watched live would stay 直播中 after it ended. Streams marked live or
  /// upcoming there are asked again, at most every 10 minutes.
  Future<void> checkHistoryLive() async {
    final store = _history;
    final last = _historyLiveChecked;
    if (store == null || (last != null && DateTime.now().difference(last) < const Duration(minutes: 10))) return;
    final marked = [for (final item in store.items) if (item.isLive || item.isUpcoming) item].take(20).toList();
    if (marked.isEmpty) return;
    _historyLiveChecked = DateTime.now();
    final states = await mapLimited(marked, 4, (item) async {
      try {
        final bytes = await _liveProbe.fetch(item.id, 'videoDetails.videoId,videoDetails.isLive,videoDetails.isUpcoming', expect: 'videoDetails');
        // No videoDetails (a bot check or a removed video) says nothing.
        if (!utf8.decode(bytes, allowMalformed: true).contains('"videoDetails"')) return item.liveStatus;
        return await liveStateOf(bytes) ?? 'was_live';
      } catch (_) {
        return item.liveStatus;
      }
    });
    final changed = {for (final (i, item) in marked.indexed) if (states[i] != item.liveStatus) item.id: states[i]};
    if (changed.isEmpty || _disposed) return;
    logInfo('History: ${changed.length} of ${marked.length} streams marked live changed');
    await store.setLiveStatus(changed);
    _update(() {});
  }

  /// Settings › Google 账号 › 保存电视版样本.
  Future<String> saveTvSamples() async {
    final sign = tvSignIn;
    final logs = directories?.logs;
    if (sign == null || !sign.signedIn || logs == null) return tr('Sign in with a TV code in Settings › YouTube account first');
    return tv_samples.saveTvSamples(sign, logs);
  }

  void _webSignInChanged() {
    final web = webSignIn;
    // A new sign-in is tried again even after YouTube refused the old one.
    if (web != null && web.signIns != _webSignIns) {
      _webSignIns = web.signIns;
      comments.webRefused = false;
    }
    notifyListeners();
  }

  void _tvSignInChanged() {
    final signedIn = tvSignIn?.signedIn ?? false;
    if (signedIn) comments.refused = false;
    if (signedIn != _tvWasSignedIn) {
      _tvWasSignedIn = signedIn;
      youtubeHistory?.dispose();
      youtubeHistory = null;
      tvPlaylists = const [];
      _tvPlaylistsRead = false;
      // Signed in just now: YouTube's own suggestions join the feed.
      if (signedIn && homeFeed != null) unawaited(refreshHomeFeed(force: true, keep: true));
    }
    notifyListeners();
  }

  /// Reads the account's YouTube playlists the first time 播放列表 shows.
  void ensureTvPlaylists() {
    if (_tvPlaylistsRead || !(tvFeed?.available ?? false)) return;
    _tvPlaylistsRead = true;
    unawaited(loadTvPlaylists());
  }

  /// Reads the account's YouTube playlists again.
  Future<void> loadTvPlaylists() async {
    final feed = tvFeed;
    if (feed == null || !feed.available || tvPlaylistsLoading) return;
    tvPlaylistsLoading = true;
    notifyListeners();
    try {
      final found = await feed.accountPlaylists();
      if (feed.available) tvPlaylists = found;
    } catch (e) {
      logWarn('Could not read the YouTube playlists: $e');
    } finally {
      tvPlaylistsLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// 观看历史 › YouTube: the account's history on YouTube, loaded the first
  /// time it is shown.
  VideoListLoader? openYoutubeHistory({bool reload = false}) {
    final feed = tvFeed;
    if (feed == null || !feed.available) return null;
    if (reload) {
      youtubeHistory?.dispose();
      youtubeHistory = null;
    }
    return youtubeHistory ??= VideoListLoader(() => Listing(() => feed.lines(YoutubeTvFeed.history)), pageSize: 40, name: 'YouTube history')
      ..addListener(_passOn('youtube history'))
      ..loadMore();
  }

  /// Whether [playlist] is the account's own, read signed in.
  bool _isAccountPlaylist(PlaylistResult playlist) =>
      playlist.id == YoutubeTvFeed.watchLaterId || tvPlaylists.any((list) => list.id == playlist.id);
}
