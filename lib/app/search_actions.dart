part of 'app_controller.dart';

/// Searching, and filtering lists by the content filters.
extension SearchActions on AppController {
  Future<void> search(String value, {SearchFilter? filter}) async {
    final query = value.trim();
    if (query.isEmpty || !ready) return;
    final asUrl = AppController.parseYoutubeId(query);
    if (asUrl != null) {
      await play(VideoItem(id: asUrl, title: tr('YouTube video · {0}', [asUrl]), channel: 'YouTube', url: 'https://www.youtube.com/watch?v=$asUrl'));
      return;
    }
    if (query != _query || mode != PageMode.explore || onWatchPage) _remember();
    final keep = _keepsPlaying;
    if (!keep) _unload();
    final repository = _repository!;
    final chosen = filter ?? searchFilter;
    if (preferences.recordHistory && !incognito) unawaited(searchHistory?.add(query));
    final sp = searchParams(type: chosen, sort: searchSort, date: searchDate, duration: searchDuration);
    _update(() {
      mode = PageMode.explore;
      if (keep) {
        mini = true;
      } else {
        playing = null;
      }
      _query = query;
      searchFilter = chosen;
      searchResults?.dispose();
      searchResults = VideoListLoader(() => sp == null ? repository.search(query) : repository.search(query, sp: sp))
        ..addListener(_passOn('search'))
        ..loadMore();
    });
  }

  /// Fetches the next page of the current search. After a failed page,
  /// scrolling does not retry on its own; [retry] comes from the retry button.
  void loadMoreResults({bool retry = false}) => searchResults?.loadMore(retry: retry);

  /// Leaves search results for the explore topics.
  void clearSearch() {
    _update(() {
      _query = null;
      searchResults?.dispose();
      searchResults = null;
    });
    _loadExplore();
  }

  /// Videos of [items] that pass the privacy and content filters. The
  /// subscriptions feed is filtered only when [AppPreferences.filterSubscriptions].
  List<VideoItem> visible(List<VideoItem> items, {bool subscriptions = false, bool search = false}) {
    final prefs = preferences;
    // Pages filter their lists on every rebuild, and a feed runs to a
    // thousand items: the answer is kept while the list and the preferences
    // stay. Hiding watched videos also follows which videos are finished.
    final ai = _aiFilter;
    final key = (prefs, subscriptions, search, search ? _query : null, prefs.hideWatched ? (library?.store, library?.store.finishedVersion) : null, ai?.version);
    if (_visible[items] case (final known, final kept) when known == key) return kept;
    var kept = _filter(items, prefs, subscriptions: subscriptions, search: search);
    // Subscribed channels are the viewer's own choice.
    if (ai != null && ai.mode != AiFilterMode.off && !subscriptions) {
      bool followed(VideoItem item) => item.channelId != null && (library?.isFollowing(item.channelId!) ?? false);
      kept = [for (final item in kept) if (followed(item) || !ai.hides(item)) item];
      ai.check(kept.where((item) => !followed(item)));
    }
    _visible[items] = (key, kept);
    return kept;
  }

  List<VideoItem> _filter(List<VideoItem> items, AppPreferences prefs, {required bool subscriptions, required bool search}) {
    if (subscriptions && !prefs.filterSubscriptions) return items.where((item) => !prefs.isBlocked(item.channelId)).toList();
    final library = this.library;
    // Blocked groups show in a search only for their channel's exact name,
    // channels not to recommend in any search; followed channels are the
    // user's choice and stay.
    bool hidden(VideoItem item) =>
        !subscriptions &&
        ((prefs.blocksGroup(item) && !(search && isExactName(item.channel, _query))) || (!search && prefs.isUnrecommended(item.channelId)));
    return items.where((item) => !hidden(item) && prefs.shows(item, watched: library?.progressOf(item.id)?.finished ?? false)).toList();
  }
}
