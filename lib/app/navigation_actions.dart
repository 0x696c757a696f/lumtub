part of 'app_controller.dart';

/// Moving between pages: the back stack, channels, playlists, search options, the home feed and history.
extension NavigationActions on AppController {
  /// Opens [target]; 返回 comes back to where this was.
  void navigate(PageMode target) {
    if (target != mode || onWatchPage) _remember();
    _go(target);
  }

  void _go(PageMode target) {
    setPip(false);
    final keep = _keepsPlaying;
    if (!keep) {
      if (playing != null) _finishWatching();
      _tracking = null;
      _recoveryTimer?.cancel();
      _recovery.reset();
      ++_playSerial;
    }
    if (target == PageMode.home) unawaited(refreshHomeFeed());
    if (target == PageMode.home || target == PageMode.history) unawaited(checkHistoryLive());
    _saveProgress(now: true);
    if (target == PageMode.subscriptions && preferences.feedAutoRefresh) {
      unawaited(library?.refreshFeed(interval: Duration(minutes: preferences.feedRefreshMinutes)));
    }
    _update(() {
      mode = target;
      if (keep) {
        mini = true;
      } else {
        playing = null;
        playbackError = null;
      }
    });
    if (!keep) _unload();
  }

  /// What is on screen now, as 返回 would come back to it.
  BackEntry get _here {
    final video = playing;
    if (video != null && !mini) {
      final state = player?.state;
      // A video that had finished starts over rather than ending again.
      final ended = state == null || (state.duration > Duration.zero && state.position > state.duration - const Duration(seconds: 5));
      return BackEntry.video(video, mode: mode, position: ended ? null : state.position, queue: queue);
    }
    return BackEntry.page(mode, query: _query, channel: channel, channelTab: channelTab, playlistId: openPlaylistId, youtubePlaylist: youtubePlaylist);
  }

  void _remember() {
    if (!_restoring && ready) _back.push(_here);
  }

  /// Whether 返回 has somewhere to go.
  bool get canGoBack => !_back.isEmpty || onWatchPage || _query != null || mode != PageMode.home || channelQuery != null;

  /// Goes back to the previous page or video: a search inside a channel is
  /// cleared first; with nothing earlier it closes the video, then the
  /// search, then goes home.
  void goBack() {
    if (!onWatchPage && mode == PageMode.channel && channelQuery != null) return searchChannel('');
    BackEntry? entry;
    do {
      entry = _back.pop();
    } while (entry != null && !onWatchPage && entry.same(_here));
    _restoring = true;
    try {
      if (entry != null) {
        _restore(entry);
      } else if (onWatchPage) {
        // Nothing earlier: leave the watch page for the page under it.
        _go(mode);
      } else if (_query != null) {
        clearSearch();
      } else if (mode != PageMode.home) {
        _go(PageMode.home);
      }
    } finally {
      _restoring = false;
    }
  }

  void _restore(BackEntry entry) {
    final video = entry.video;
    if (video != null) {
      if (mini && playing?.id == video.id) return expandMini();
      unawaited(play(video, from: entry.queue.isEmpty ? null : entry.queue, at: entry.position));
      return;
    }
    switch (entry.mode) {
      case PageMode.explore:
        final query = entry.query;
        if (query == null) {
          openExplore();
        } else if (query == _query) {
          _go(PageMode.explore);
        } else {
          unawaited(search(query));
        }
      case PageMode.channel:
        final ref = entry.channel;
        if (ref == null) return _go(PageMode.home);
        if (ref.id != channel?.id) {
          openChannel(ref);
        } else {
          _go(PageMode.channel);
        }
        if (entry.channelTab != channelTab) setChannelTab(entry.channelTab);
      case PageMode.youtubePlaylist:
        final playlist = entry.youtubePlaylist;
        if (playlist == null) return _go(PageMode.home);
        if (playlist.id != youtubePlaylist?.id) {
          openYoutubePlaylist(playlist);
        } else {
          _go(PageMode.youtubePlaylist);
        }
      case PageMode.playlist:
        final id = entry.playlistId;
        if (id == null) return _go(PageMode.home);
        openPlaylist(id);
      case final mode:
        _go(mode);
    }
  }

  /// Opens [ref]'s page with its uploads.
  void openChannel(ChannelRef ref) {
    final repository = _repository;
    if (repository == null) return;
    _remember();
    channelVideos?.dispose();
    channelPosts?.dispose();
    channelPosts = null;
    channel = ref;
    channelQuery = null;
    channelTab = ChannelTab.videos;
    channelVideos = VideoListLoader(() => repository.channelVideos(ref))
      ..addListener(_passOn('channel'))
      ..loadMore();
    _go(PageMode.channel);
  }

  /// Shows another tab of the open channel.
  void setChannelTab(ChannelTab tab) {
    final repository = _repository;
    final ref = channel;
    if (repository == null || ref == null) return;
    _update(() {
      channelTab = tab;
      channelQuery = null;
      channelVideos?.dispose();
      channelVideos = null;
      channelPosts?.dispose();
      channelPosts = null;
      if (tab == ChannelTab.posts) {
        channelPosts = PostsLoader(_posts, ref)..addListener(_passOn('channel'));
        unawaited(channelPosts!.loadMore());
      } else {
        channelVideos = VideoListLoader(() => repository.channelTab(ref, tab))
          ..addListener(_passOn('channel'))
          ..loadMore();
      }
    });
  }

  /// Opens a YouTube playlist's page.
  void openYoutubePlaylist(PlaylistResult playlist) {
    final repository = _repository;
    if (repository == null) return;
    _remember();
    youtubePlaylistVideos?.dispose();
    youtubePlaylist = playlist;
    final feed = tvFeed;
    final signedIn = feed != null && feed.available && _isAccountPlaylist(playlist);
    youtubePlaylistVideos = VideoListLoader(() => signedIn ? Listing(() => feed.lines('VL${playlist.id}', pages: 50)) : repository.playlist(playlist.id), pageSize: 50)
      ..addListener(_passOn('channel'))
      ..loadMore();
    _go(PageMode.youtubePlaylist);
  }

  /// Searches the open channel; an empty [query] lists the tab again.
  void searchChannel(String query, {ChannelTab? within}) {
    final repository = _repository;
    final ref = channel;
    if (repository == null || ref == null) return;
    final text = query.trim();
    _update(() {
      channelVideos?.dispose();
      channelVideos = null;
      channelPosts?.dispose();
      channelPosts = null;
      channelQuery = text.isEmpty ? null : text;
      channelSearchTab = text.isEmpty ? null : within;
      if (text.isEmpty) {
        // Back to the tab that was open.
        if (channelTab == ChannelTab.posts) {
          channelPosts = PostsLoader(_posts, ref)..addListener(_passOn('channel'));
          unawaited(channelPosts!.loadMore());
        } else {
          final tab = channelTab;
          channelVideos = VideoListLoader(() => repository.channelTab(ref, tab))
            ..addListener(_passOn('channel'))
            ..loadMore();
        }
        return;
      }
      final words = text.toLowerCase().split(RegExp(r'\s+'));
      bool matches(String title) {
        final lower = title.toLowerCase();
        return words.every(lower.contains);
      }

      if (within == ChannelTab.posts) {
        channelPosts = PostsLoader(_posts, ref, matches: matches)..addListener(_passOn('channel'));
        unawaited(channelPosts!.loadMore());
      } else {
        channelVideos = (within == null
            ? VideoListLoader(() => repository.channelSearch(ref, text))
            : VideoListLoader(() => repository.channelTab(ref, within), matches: matches))
          ..addListener(_passOn('channel'))
          ..loadMore();
      }
    });
  }

  void openPlaylist(String id) {
    _remember();
    openPlaylistId = id;
    _go(PageMode.playlist);
  }

  void retrySearch() {
    final last = _query;
    if (last != null) unawaited(search(last));
  }

  /// Searches again with another order, upload date or length.
  void setSearchOptions({SearchSort? sort, SearchUploadDate? date, SearchDuration? duration}) {
    searchSort = sort ?? searchSort;
    searchDate = date ?? searchDate;
    searchDuration = duration ?? searchDuration;
    retrySearch();
  }

  /// Gathers recommendations again when they are old, or when [force]d;
  /// with [keep], the videos shown stay and new ones follow them.
  Future<void> refreshHomeFeed({bool force = false, bool keep = false}) async {
    final feed = homeFeed;
    final repository = _repository;
    final library = this.library;
    if (feed == null || repository == null || !preferences.homeShowRecommended || preferences.focusHideHome || feed.loading) return;
    if (!force && !feed.stale && feed.items.isNotEmpty) return;
    // The last launch's feed shows while a new one is gathered.
    await feed.restore(filter: visible);
    if (!force && !preferences.homeAutoRefresh && feed.items.isNotEmpty) return;
    if (library != null && library.channels.isNotEmpty && library.feed.isEmpty) {
      await library.refreshFeed().timeout(const Duration(seconds: 20), onTimeout: () {});
    }
    feed.mix = preferences.feedMix;
    await feed.refresh(await _homeSources(repository), filter: visible, keep: keep);
  }

  /// The next page of 为你推荐, as the home page scrolls to its end.
  Future<void> loadMoreHomeFeed() async {
    final feed = homeFeed;
    if (feed == null) return;
    // Kept from the last launch without refreshing: gather now, after it.
    if (!feed.gathered) return refreshHomeFeed(force: true, keep: true);
    await feed.loadMore();
  }

  /// Tells 为你推荐 about the video just left: watched a while, it steers
  /// what comes next; left within seconds, it counts against its channel.
  void _finishWatching() {
    final item = _watching;
    _watching = null;
    if (item != null) _reportWatchedToYoutube(item);
    final feed = homeFeed;
    final repository = _repository;
    final player = this.player;
    if (item == null || feed == null || repository == null || player == null || !preferences.homeShowRecommended || incognito) return;
    final position = player.state.position;
    final duration = player.state.duration;
    final fraction = duration > Duration.zero ? position.inMilliseconds / duration.inMilliseconds : 0.0;
    final skipped = position < const Duration(seconds: 15) && fraction < 0.1;
    if (!skipped && position < const Duration(seconds: 30) && fraction < 0.3) return;
    unawaited(() async {
      await feed.learn(item, await _homeSources(repository), skipped: skipped);
    }());
  }

  /// 观看记录同步到 YouTube: adds the video just left to the account's
  /// history, as SmartTube does: from the start for the first three minutes,
  /// else where it was left; nearly finished marks it watched.
  void _reportWatchedToYoutube(VideoItem item) {
    final sign = tvSignIn;
    final player = this.player;
    if (sign == null || !sign.signedIn || player == null || !preferences.syncHistoryToYoutube || !preferences.recordHistory || incognito) return;
    final to = player.state.position.inMilliseconds / 1000;
    if (to < 5) return;
    final length = player.state.duration.inMilliseconds / 1000;
    unawaited(() async {
      final why = await sign.reportWatched(item.id, from: to < 180 ? 0 : to, to: to, length: length);
      if (why != null) logWarn('Could not add ${item.id} to the YouTube history: $why');
    }());
  }

  Future<HomeFeedSources> _homeSources(VideoRepository repository) async {
    final library = this.library;
    final weekly = searchParams(type: SearchFilter.videos, sort: SearchSort.views, date: SearchUploadDate.week);
    return HomeFeedSources(
        history: history,
        progressOf: library?.progressOf,
        favorites: [...?library?.favorites, ...?account?.likedVideos.take(50)],
        followed: library?.channels ?? const [],
        subscriptions: library?.feed ?? const [],
        searches: preferences.recordHistory ? await searchHistory?.items() ?? const [] : const [],
        youtubeHome: tvFeed?.available ?? false ? () => tvFeed!.videos(YoutubeTvFeed.home, limit: 40) : null,
        related: relatedVideos.forVideo,
        channelUploads: library?.uploadsOf ?? (_) async => const [],
        search: (query) async {
          final listing = repository.search(query, sp: weekly);
          try {
            return (await listing.next(10).toList()).whereType<VideoItem>().toList();
          } finally {
            listing.close();
          }
        },
      );
  }

  /// Follows or unfollows [channel] here, and on YouTube when signed in
  /// and [AppPreferences.syncFollowToYoutube]. Returns whether it is
  /// followed now.
  bool toggleFollow(ChannelRef channel) {
    final library = this.library;
    if (library == null) return false;
    final following = library.toggleFollow(channel);
    final account = this.account;
    if (account != null && account.canWrite && preferences.syncFollowToYoutube) unawaited(account.setSubscribed(channel, following));
    return following;
  }

  /// 换一批.
  void shuffleHomeFeed() {
    homeFeed?.mix = preferences.feedMix;
    homeFeed?.shuffle(filter: visible);
  }

  /// 不感兴趣: hides [item] and shows less from its channel.
  Future<void> dismissRecommendation(VideoItem item) async {
    await homeFeed?.dismiss(item);
    _notice(tr("You'll see fewer recommendations like this"));
  }

  Future<void> clearNotInterested() async {
    await homeFeed?.notInterested.clear();
    _notice(tr('Cleared "Not interested" history'));
  }

  /// Shows the current search's results of another kind.
  void setSearchFilter(SearchFilter filter) {
    final last = _query;
    if (last != null && filter != searchFilter) unawaited(search(last, filter: filter));
  }

  Future<void> clearSearchHistory() async {
    await searchHistory?.clear();
    _notice(tr('Search history cleared.'));
  }

  /// Forgets the videos with these [ids] from the watch history.
  Future<void> removeFromHistory(Set<String> ids) async {
    await _history?.remove(ids);
    _update(() {});
  }

  Future<void> clearHistory() async {
    await _history?.clear();
    _update(() {});
    _notice(tr('Watch history cleared.'));
  }
}
