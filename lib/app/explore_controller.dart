part of 'app_controller.dart';

/// The explore page's state, mixed into [AppController].
mixin _ExploreState {
  /// The explore page: its part, zone, sub-category (0 for all of the
  /// zone) and the sub-category's own (0 for all of it), how videos are
  /// picked, and the filters.
  ExploreSection exploreSection = ExploreSection.popular;
  int exploreTopic = 0;
  int exploreSub = 0;
  int exploreLeaf = 0;
  ExploreMode exploreMode = ExploreMode.popular;
  SearchUploadDate explorePeriod = SearchUploadDate.month;
  SearchDuration exploreDuration = SearchDuration.any;
  SearchQuality exploreQuality = SearchQuality.any;
  /// The 类型 and 视角 filters: 宗教与信仰's own lists there, general ones
  /// elsewhere ([exploreFormats], [exploreViews]).
  WordFilter exploreFormat = ContentFormat.any;
  WordFilter exploreView = ContentView.any;

  /// The chosen zone's videos.
  VideoListLoader? explore;

  (ExploreSection, int) _topicBeforeFaith = (ExploreSection.popular, 0);

  /// Lists of zones shown lately, so going back to one shows it again
  /// instead of searching anew. 全部 is left out, as each visit brings
  /// others, and so is a list that failed.
  final _recentExplore = <Object, (DateTime, VideoListLoader)>{};

  /// How many videos the explore language filter asked about and kept,
  /// once it stopped; null while it is still looking or with no language.
  ({int asked, int kept})? exploreLanguageCheck;

  /// How many times further the next explore load may look for videos in
  /// the language picked.
  int _exploreDepth = 0;
}

/// How long a zone's list shown lately can be shown again.
const _keepExplore = Duration(minutes: 15);

/// The explore page's actions: its zones, filters and loading.
extension ExploreActions on AppController {
  List<WordFilter> get exploreFormats => AppController.formatsOf(exploreSection);
  List<WordFilter> get exploreViews => AppController.viewsOf(exploreSection);

  /// Every zone of [section], built in and the user's, in no set order.
  List<ExploreTopic> allExploreTopics(ExploreSection section) => exploreTopicsOf(section, preferences.exploreCustomTopics);

  /// The zones of [section] the strip shows, in the user's order.
  List<ExploreTopic> exploreTopicsFor(ExploreSection section) => arrangeTopics(
        allExploreTopics(section),
        preferences.exploreOrder[section.name] ?? const [],
        {...?preferences.exploreHidden[section.name]},
      );

  ExploreTopic get exploreTopicNow {
    final topics = exploreTopicsFor(exploreSection);
    return topics[exploreTopic.clamp(0, topics.length - 1)];
  }

  /// The sub-category shown, if one is.
  ExploreSub? get exploreSubNow {
    final subs = exploreTopicNow.subs;
    return exploreSub > 0 && exploreSub <= subs.length ? subs[exploreSub - 1] : null;
  }

  /// The sub-category's own sub-category shown, if one is.
  ExploreSub? get exploreLeafNow {
    final subs = exploreSubNow?.subs ?? const [];
    return exploreLeaf > 0 && exploreLeaf <= subs.length ? subs[exploreLeaf - 1] : null;
  }

  /// The words searched for: the narrowest sub-category's, or the whole
  /// zone's, with 宗教与信仰's filter words.
  String get exploreQuery => [
        (exploreLeafNow ?? exploreSubNow)?.query ?? exploreTopicNow.query,
        exploreFormat.words,
        exploreView.words,
      ].where((w) => w.isNotEmpty).join(' ');

  /// Adds a category of the user's own and shows it.
  Future<void> addExploreTopic(CustomTopic topic) async {
    final kept = preferences.exploreCustomTopics.where((t) => !(t.section == topic.section && t.label == topic.label)).toList();
    final key = topic.topic.key;
    await savePreferences(preferences.copyWith(
      exploreCustomTopics: [...kept, topic],
      exploreHidden: {...preferences.exploreHidden, topic.section.name: [...?preferences.exploreHidden[topic.section.name]]..remove(key)},
    ));
    final index = exploreTopicsFor(topic.section).indexWhere((t) => t.key == key);
    _reloadExplore(section: topic.section, topic: index);
  }

  /// Removes one of the user's categories, keeping the one shown if it stays.
  Future<void> removeExploreTopic(ExploreSection section, String label) async {
    final key = 'custom:$label';
    await _arrangeExplore(section, () => savePreferences(preferences.copyWith(
          exploreCustomTopics: preferences.exploreCustomTopics.where((t) => !(t.section == section && t.label == label)).toList(),
          exploreOrder: {...preferences.exploreOrder, section.name: [...?preferences.exploreOrder[section.name]]..remove(key)},
          exploreHidden: {...preferences.exploreHidden, section.name: [...?preferences.exploreHidden[section.name]]..remove(key)},
        )));
  }

  /// Saves the order and hidden zones of [section] from the manage dialog.
  Future<void> arrangeExploreTopics(ExploreSection section, List<String> order, Set<String> hidden) => _arrangeExplore(
        section,
        () => savePreferences(preferences.copyWith(
          exploreOrder: {...preferences.exploreOrder, section.name: order},
          exploreHidden: {...preferences.exploreHidden, section.name: hidden.toList()},
        )),
      );

  /// Runs [change] and keeps the zone shown if it is still in the strip.
  Future<void> _arrangeExplore(ExploreSection section, Future<void> Function() change) async {
    final shown = exploreTopicNow.key;
    await change();
    if (section != exploreSection) return;
    final index = exploreTopicsFor(section).indexWhere((t) => t.key == shown);
    if (index == exploreTopic) {
      notifyListeners();
    } else if (index >= 0) {
      // Same zone at another place: nothing to load again.
      _update(() => exploreTopic = index);
    } else {
      _reloadExplore(topic: 0);
    }
  }

  void _reloadExplore({ExploreSection? section, required int topic}) {
    explore?.dispose();
    explore = null;
    setExplore(section: section, topic: topic < 0 ? 0 : topic);
  }

  /// Opens the explore page on its topics.
  void openExplore() {
    _remember();
    if (_query != null) {
      _query = null;
      searchResults?.dispose();
      searchResults = null;
    }
    _go(PageMode.explore);
    _loadExplore();
  }

  /// 视频 or 直播, whichever 宗教信仰 was opened from while its tabs show.
  ExploreSection get exploreHalf => exploreSection.isFaith ? _topicBeforeFaith.$1 : exploreSection;

  /// Shows another part, zone, sub-category, mode, period or filter of the
  /// explore page. A new part starts on its first zone, and on its usual
  /// mode unless the one shown also suits it; a new zone on all of it.
  void setExplore({
    ExploreSection? section,
    int? topic,
    int? sub,
    int? leaf,
    ExploreMode? mode,
    SearchUploadDate? period,
    SearchDuration? duration,
    SearchQuality? quality,
    WordFilter? format,
    WordFilter? view,
    ExploreRegion? region,
    ExploreLanguage? language,
    bool? heardOnly,
  }) {
    if ((region != null && region != preferences.exploreRegion) ||
        (language != null && language != preferences.exploreLanguage) ||
        (heardOnly != null && heardOnly != preferences.exploreHeardOnly)) {
      unawaited(savePreferences(preferences.copyWith(exploreRegion: region, exploreLanguage: language, exploreHeardOnly: heardOnly)));
      explore?.dispose();
      explore = null;
    }
    final nextSection = section ?? exploreSection;
    final newSection = nextSection != exploreSection;
    final topics = exploreTopicsFor(nextSection);
    final nextTopic = (topic ?? (newSection ? 0 : exploreTopic)).clamp(0, topics.length - 1);
    // 宗教信仰 among the video zones opens 宗教与信仰's tabs; leaving them
    // goes back to the zone shown before.
    final opens = topics[nextTopic].opens;
    if (opens != null) {
      if (!exploreSection.isFaith) _topicBeforeFaith = (exploreSection, exploreTopic);
      setExplore(section: opens);
      return;
    }
    final nextSub = sub ?? (newSection || nextTopic != exploreTopic ? 0 : exploreSub);
    final nextLeaf = leaf ?? (newSection || nextTopic != exploreTopic || nextSub != exploreSub ? 0 : exploreLeaf);
    final modes = ExploreMode.of(nextSection);
    final sameKind = nextSection.isFaith == exploreSection.isFaith && nextSection.isLive == exploreSection.isLive;
    final nextMode = mode != null && modes.contains(mode)
        ? mode
        : !newSection || (sameKind && modes.contains(exploreMode))
            ? exploreMode
            : ExploreMode.defaultOf(nextSection);
    final nextPeriod = period ?? explorePeriod;
    final nextDuration = duration ?? exploreDuration;
    final nextQuality = quality ?? exploreQuality;
    // A filter of the other kind's list starts over at 不限.
    final formats = AppController.formatsOf(nextSection), views = AppController.viewsOf(nextSection);
    final nextFormat = format ?? (formats.contains(exploreFormat) ? exploreFormat : formats.first);
    final nextView = view ?? (views.contains(exploreView) ? exploreView : views.first);
    if (!newSection &&
        nextTopic == exploreTopic &&
        nextSub == exploreSub &&
        nextLeaf == exploreLeaf &&
        nextMode == exploreMode &&
        nextPeriod == explorePeriod &&
        nextDuration == exploreDuration &&
        nextQuality == exploreQuality &&
        nextFormat == exploreFormat &&
        nextView == exploreView &&
        explore != null) {
      return;
    }
    _update(() {
      _putAwayExplore();
      exploreSection = nextSection;
      exploreTopic = nextTopic;
      exploreSub = nextSub;
      exploreLeaf = nextLeaf;
      exploreFormat = nextFormat;
      exploreView = nextView;
      exploreMode = nextMode;
      explorePeriod = nextPeriod;
      exploreDuration = nextDuration;
      exploreQuality = nextQuality;
    });
    _loadExplore();
  }

  Object get _exploreKey => (exploreSection, exploreTopic, exploreSub, exploreLeaf, exploreMode, explorePeriod, exploreDuration, exploreQuality, exploreFormat, exploreView, preferences.exploreRegion, preferences.exploreLanguage, preferences.exploreHeardOnly);

  void _putAwayExplore() {
    final loader = explore;
    explore = null;
    if (loader == null) return;
    // An empty list is looked for again next time, not shown again.
    if (exploreTopicNow.mix || loader.error != null || loader.items.isEmpty) {
      loader.dispose();
      return;
    }
    loader.removeListener(_passOn('explore'));
    final key = _exploreKey;
    final older = _recentExplore.remove(key)?.$2;
    if (older != null && !identical(older, loader)) older.dispose();
    _recentExplore[key] = (DateTime.now(), loader);
    while (_recentExplore.length > 4) {
      _recentExplore.remove(_recentExplore.keys.first)!.$2.dispose();
    }
  }

  void _loadExplore() {
    final repository = _repository;
    if (repository == null || explore != null) return;
    if (exploreTopicNow.opens case final opens?) {
      setExplore(section: opens);
      return;
    }
    if (_recentExplore.remove(_exploreKey) case (final at, final loader)) {
      if (DateTime.now().difference(at) < _keepExplore) {
        logDebug(() => 'Explore ${exploreSection.name} · ${exploreTopicNow.label}: shown again from ${DateTime.now().difference(at).inSeconds} s ago');
        _update(() => explore = loader..addListener(_passOn('explore')));
        return;
      }
      loader.dispose();
    }
    final query = exploreQuery;
    final mode = exploreMode;
    final mix = exploreTopicNow.mix;
    final language = preferences.exploreLanguage;
    // With no region picked, a language is searched for from its home
    // country, where YouTube ranks its videos first.
    final picked = preferences.exploreRegion.gl;
    final region = picked.isNotEmpty ? picked : language.homeCountry;
    exploreLanguageCheck = null;
    final depth = _exploreDepth;
    _exploreDepth = 0;
    // Listed titles are machine-translated, so the language is asked of
    // each video instead (VideoLanguages).
    final spoken = language != ExploreLanguage.any && VideoLanguages.available && _videoLanguages != null;
    final perChannel = <String, int>{};
    final sp = exploreParams(mode, period: explorePeriod, duration: exploreDuration, quality: exploreQuality);
    final taste = mode == ExploreMode.forYou ? _exploreTaste() : null;
    // The Home and Explore "For You" lists share these choices.  Explore has
    // its own loader, so it must apply the mix here instead of relying on
    // HomeFeed's ranking pass.
    final feedMix = mode == ExploreMode.forYou ? preferences.feedMix : null;
    final notInterested = homeFeed?.notInterested;
    final faith = exploreSection.isFaith ? faithFilter() : null;
    // A live stream goes on after it was watched: only videos are left out
    // of 全部 once seen.
    final seen = mix && !exploreSection.isLive ? {for (final item in history) item.id, ...?homeFeed?.items.map((item) => item.id)} : const <String>{};
    final prefs = preferences;
    final ai = _aiFilter;
    final known = mode == ExploreMode.fresh
        ? {for (final item in history) TasteProfile.channelKey(item), for (final channel in library?.channels ?? const <ChannelRef>[]) channel.id}
        : const <String>{};
    final dropped = <String, int>{};
    bool drop(String why) {
      dropped.update(why, (n) => n + 1, ifAbsent: () => 1);
      return false;
    }

    bool where(VideoItem item) {
      if (notInterested != null && notInterested.videos.contains(item.id)) return drop('not interested');
      // What the page would hide is left out here too, so that hiding it
      // still fills the page (see [AppController.visible]).
      if (prefs.blocksGroup(item) || prefs.isUnrecommended(item.channelId)) return drop('blocked');
      if (!prefs.shows(item, watched: library?.progressOf(item.id)?.finished ?? false)) return drop('settings');
      if (ai != null && ai.hides(item) && !(item.channelId != null && (library?.isFollowing(item.channelId!) ?? false))) return drop('AI filter');
      // "Don't recommend" is a hard exclusion.  "Fewer" remains in the
      // list, but its score is reduced below in the ranking callback.
      if (feedMix != null && feedMix.penaltyOf(item) == null) return drop('Shorts or vertical');
      if (taste != null && taste.channelAffinity(item) < -0.3) return drop('often skipped channel');
      if (mode == ExploreMode.liveUpcoming && !item.isUpcoming) return drop('not upcoming');
      if (mode == ExploreMode.liveReplay && item.liveStatus != 'was_live') return drop('not a replay');
      final seconds = item.duration;
      if (mode == ExploreMode.gems) {
        final views = item.viewCount;
        if (views == null || views > gemMaxViews || seconds == null || seconds < 240) return drop('not a hidden gem');
      }
      if (mode == ExploreMode.fresh) {
        final views = item.viewCount;
        if (views == null || views > freshMaxViews || seconds == null || seconds < 60) return drop('not new');
        if (known.contains(TasteProfile.channelKey(item))) return drop('known channel');
      }
      if (mode == ExploreMode.curated && seconds != null && seconds < 240) return drop('too short');
      if (!spoken && !language.matches(item.title)) return drop('language');
      // 全部 is for finding more: not what was watched or what 为你推荐
      // already shows. It keeps any one channel from filling it.
      if (mix && seen.contains(item.id)) return drop('already seen');
      if (mix && (perChannel[TasteProfile.channelKey(item)] = (perChannel[TasteProfile.channelKey(item)] ?? 0) + 1) > 2) return drop('more than 2 per channel');
      // Last, as it counts the videos that show.
      return faith == null || faith(item) || drop('faith filter');
    }

    _update(() => explore = VideoListLoader(
          () {
            Listing search(List<String> queries) =>
                mix ? repository.searchMix(queries, sp: sp, region: region) : repository.search(queries.single, sp: sp, region: region);
            final queries = mix ? exploreMixQueries(exploreSection) : [query];
            // The zones' search words are Chinese, which finds Chinese
            // videos: they are put in the language picked, else the
            // region's, else a non-Chinese interface's.
            final ui = youtubeHl.startsWith('zh') ? ExploreLanguage.any : ExploreLanguage.parse(youtubeHl.split('-').first);
            final regional = preferences.exploreRegion.searchLanguage;
            final wordsIn = language != ExploreLanguage.any ? language : regional != ExploreLanguage.any ? regional : ui;
            // Taiwan and Hong Kong write traditional characters.
            final traditional = wordsIn == ExploreLanguage.zh && (region == 'TW' || region == 'HK');
            // A zone of the user's own is searched as they wrote it: its
            // words are not sent to be translated.
            final listing = wordsIn == ExploreLanguage.any || (wordsIn == ExploreLanguage.zh && !traditional) || exploreTopicNow.custom
                ? search(queries)
                : Listing.deferred(() async => search(await _searchWordsIn(queries, wordsIn, traditional: traditional)));
            final languages = _videoLanguages;
            return spoken && languages != null
                ? listing.refined((lines) => languages.only(
                      lines,
                      language,
                      heardOnly: preferences.exploreHeardOnly,
                      giveUpAfter: VideoLanguages.giveUpAfterDefault * (depth + 1),
                      done: (asked, kept) => _update(() => exploreLanguageCheck = (asked: asked, kept: kept)),
                    ))
                : listing;
          },
          where: where,
          fill: switch (mode) {
            ExploreMode.gems || ExploreMode.fresh || ExploreMode.liveReplay => 8,
            ExploreMode.liveUpcoming => 4,
            _ => faith != null || mix || language != ExploreLanguage.any ? 8 : 1,
          },
          // Most watched first, as YouTube ranks each search but not the
          // searches 全部 mixes, nor what is left after the filters.
          rank: taste != null
              ? (item) => AppController.exploreScore(taste, item) - (feedMix?.penaltyOf(item) ?? 0)
              : mode.byViews
                  ? (item) => (item.viewCount ?? -1).toDouble()
                  : null,
          // Each video is looked up for the language filter: shown as
          // found rather than gathered pages ahead.
          readAhead: !spoken,
          name: 'Explore ${exploreSection.name} · ${exploreTopicNow.label} · ${mode.name}',
          dropped: dropped,
        )
          ..addListener(_passOn('explore'))
          ..loadMore());
  }

  /// [queries] in [language], translated where they are in another, or
  /// into [traditional] characters; a query that cannot be translated is
  /// searched as it is. Only Chinese, Japanese and Korean words are
  /// translated: words in Latin letters are names and terms a search
  /// keeps (Blender, lofi, keynote), and a query of them alone is searched
  /// as written.
  Future<List<String>> _searchWordsIn(List<String> queries, ExploreLanguage language, {bool traditional = false}) {
    final target = traditional ? 'zh-TW' : language.code;
    Future<String> translate(String text) => _google.translate(text, target).timeout(const Duration(seconds: 10));
    return Future.wait([
      for (final query in queries)
        if (query.trim().isEmpty || (!traditional && titleLanguage(query) == language) || !searchPhrasesOf(query).any(isCjkPhrase))
          Future.value(query)
        else
          () async {
            try {
              // Keyword by keyword, as a search wants keywords: "科技 数码 评测"
              // as one sentence is "Revisione digitale della tecnologia",
              // which finds next to nothing.
              final words = searchPhrasesOf(query);
              final asked = [for (final w in words) if (isCjkPhrase(w) && searchGlossary[w] == null) w];
              final lines = asked.isEmpty ? const <String>[] : (await translate(asked.join('\n'))).split('\n');
              if (lines.length != asked.length) throw StateError('${lines.length} lines for ${asked.length} phrases');
              var next = 0;
              final translated = searchWordsOf([
                for (final w in words) !isCjkPhrase(w) ? w : searchGlossary[w] ?? lines[next++],
              ]);
              logDebug(() => 'Explore searches "$query" in $target as "$translated"');
              return translated.isEmpty ? query : translated;
            } catch (e) {
              logWarn('Could not translate the explore search "$query" into $target: $e');
              return query;
            }
          }(),
    ]);
  }

  /// 全部's searches: zones of [section] picked at random each time, so
  /// every visit brings others. Personal picks are left to 为你推荐 on the
  /// home page.
  @visibleForTesting
  List<String> exploreMixQueries(ExploreSection section, {Random? random}) {
    final zones = [
      for (final topic in exploreTopicsFor(section))
        // Live streams are few in any one sub-category: a live mix searches
        // each zone as a whole.
        if (!topic.mix && topic.opens == null) topic.subs.isEmpty || section.isLive ? topic.query : (topic.subs.toList()..shuffle(random)).first.query,
    ]..shuffle(random);
    final filter = [exploreFormat.words, exploreView.words].where((w) => w.isNotEmpty).join(' ');
    return [for (final query in zones.take(6)) filter.isEmpty ? query : '$query $filter'];
  }

  /// Looks again, further down the search, after the language filter
  /// found none.
  void searchExploreFurther() {
    // Answers kept on disk come back at once, so going over the same
    // videos again costs little.
    _exploreDepth = (exploreLanguageCheck?.asked ?? 0) ~/ VideoLanguages.giveUpAfterDefault;
    refreshExplore();
  }

  /// Shows 全部 or the zone shown with other videos.
  void refreshExplore() {
    explore?.dispose();
    explore = null;
    _loadExplore();
  }

  /// What the history says about taste, for 为你推荐 in a zone.
  TasteProfile _exploreTaste() {
    final library = this.library;
    return TasteProfile.from(
      history: history,
      progressOf: library?.progressOf,
      favorites: [...?library?.favorites, ...?account?.likedVideos.take(50)],
      followed: {for (final c in library?.channels ?? const <ChannelRef>[]) c.id},
      decay: 0.97,
    );
  }
}
