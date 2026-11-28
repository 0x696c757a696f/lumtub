part of 'app_controller.dart';

/// 按水平找视频: the lists of the learning page's videos at the learner's
/// level (see [LevelVideos]). The page owns the lists it asks for and
/// disposes of them.
extension LevelVideoActions on AppController {
  /// The dictionary [language]'s words are cut and counted with.
  DictionaryPack? levelDictionary(String language) =>
      DictionaryPack.values.where((p) => p.language == language).firstOrNull;

  /// Why videos spoken in [language] cannot be measured now; null when
  /// they can. Without the pack (trial used up) they still can, a few a
  /// day ([LevelVideos.freeLeft]), once its dictionary is here.
  LevelVideosBlock? levelVideosBlock(String language) {
    if (!levelVideosAvailable || _repository == null || _videoLanguages == null) {
      return LevelVideosBlock.unavailable;
    }
    if (!learningOn) return LevelVideosBlock.learningOff;
    final pack = levelDictionary(language);
    if (pack == null || learning.stateOf(pack) != PackState.ready || learning.book == null) {
      return LevelVideosBlock.dictionary;
    }
    return null;
  }

  /// The language lessons are explained in until the learner picks one:
  /// the interface language.
  ExploreLanguage get interfaceExploreLanguage {
    final hl = youtubeHl;
    final base = hl.split('-').first;
    return ExploreLanguage.values
            .where((l) => l != ExploreLanguage.any && l.youtubeHl == hl)
            .firstOrNull ??
        ExploreLanguage.values
            .where((l) => l != ExploreLanguage.any && (l.youtubeHl == base || l.code == base))
            .firstOrNull ??
        ExploreLanguage.en;
  }

  /// What every list of this page leaves out, as explore does: blocked and
  /// hidden channels, what the settings hide, Shorts and vertical videos,
  /// streams.
  bool _levelVideoShown(VideoItem item) {
    final prefs = preferences;
    if (homeFeed?.notInterested.videos.contains(item.id) ?? false) return false;
    if (prefs.blocksGroup(item) || prefs.isUnrecommended(item.channelId)) return false;
    if (!prefs.shows(item, watched: library?.progressOf(item.id)?.finished ?? false)) return false;
    if (item.isLive || item.isUpcoming || item.membersOnly) return false;
    final seconds = item.duration;
    if (seconds != null && seconds < 60) return false;
    return !(prefs.feedVertical == FeedLevel.drop && isVertical(item));
  }

  Listing _withoutPortraits(Listing listing) {
    final thumbnails = thumbnailDirectory;
    if (preferences.feedVertical != FeedLevel.drop || thumbnails == null) return listing;
    return listing.refined((lines) =>
        PortraitThumbnails.drop(lines, (id) => PortraitThumbnails.check(id, thumbnails)));
  }

  /// Videos spoken in [language], of [kind] graded or native. Measured by
  /// their subtitles when [levelVideosBlock] allows: native ones then only
  /// those in [band], nearest its middle first; graded ones all, nearest
  /// "just right" first, as pictures and gestures carry a beginner
  /// through what the words do not. Unmeasured graded videos come in
  /// search order. Null for native videos that cannot be measured.
  /// [rounds] times [LevelVideos.budget] new videos are fetched at most.
  /// Without the pack only [LevelVideos.freeLeft] new native videos are
  /// shown. [checked] hears how far the search got.
  VideoListLoader? spokenVideoList(String language, LevelVideoKind kind,
      {VideoLevel band = VideoLevel.right,
      int rounds = 1,
      void Function(LevelCheck check)? checked}) {
    assert(kind != LevelVideoKind.lessons);
    final repository = _repository;
    final languages = _videoLanguages;
    if (repository == null) return null;
    final book = learning.book;
    final measure = levelVideosBlock(language) == null && book != null && languages != null;
    if (kind == LevelVideoKind.native && !measure) return null;
    final spoken = exploreLanguageOf(language);
    final hl = spoken.youtubeHl;
    // As explore: from the region picked, else the language's home country.
    final picked = preferences.exploreRegion.gl;
    final region = picked.isNotEmpty ? picked : spoken.homeCountry;
    final tier = levelTierOf(language, learning.levelIn(language));
    final steps = kind == LevelVideoKind.graded
        ? [gradedLevelQueries(language, tier)]
        : nativeLevelQueries(language, tier);
    final known = book == null ? null : knownWordsOf(book);
    final sp = searchParams(type: SearchFilter.videos)!;
    final free = measure && kind == LevelVideoKind.native && !learning.unlocked;
    var total = (
      asked: 0,
      measured: 0,
      noSubtitles: 0,
      failed: 0,
      skipped: 0,
      budgetSpent: false,
      refused: false
    );

    Listing step(List<String> queries) {
      final anchor = spoken.searchAnchor;
      final words = [for (final q in queries) anchor == null ? q : '$q $anchor'];
      logInfo(
          'Level videos (${kind.name}) in ${spoken.name}: searching ${words.map((w) => '"$w"').join(', ')} (hl $hl, gl ${region ?? '-'})');
      final listing =
          _withoutPortraits(repository.searchMix(words, sp: sp, region: region, hl: hl));
      if (languages == null) return listing;
      // Only videos heard in the language: a translated title, or
      // subtitles in it on a video spoken in another, never let one in.
      Stream<String> heard(Stream<String> lines) =>
          languages.only(lines, spoken, listedInLanguage: true);
      if (!measure) return listing.refined(heard);
      return listing.refined((lines) => levelVideos.measured(
            heard(lines),
            language: language,
            learning: learning,
            known: known!,
            languages: languages,
            rounds: rounds,
            enough: free ? () => levelVideos.freeLeft <= 0 : null,
            done: (check) {
              total = (
                asked: total.asked + check.asked,
                measured: total.measured + check.measured,
                noSubtitles: total.noSubtitles + check.noSubtitles,
                failed: total.failed + check.failed,
                skipped: total.skipped + check.skipped,
                budgetSpent: total.budgetSpent || check.budgetSpent,
                refused: total.refused || check.refused,
              );
              checked?.call(total);
            },
          ));
    }

    LevelReading? reading(VideoItem item) => switch (levelVideos.readingOf(item.id)) {
          final r? when r.language == language && r.known != null => r,
          _ => null,
        };

    return VideoListLoader(
      () {
        var listing = step(steps.first);
        for (final next in steps.skip(1)) {
          listing = listing.followedBy(() => step(next),
              switched: () =>
                  logInfo('Level videos in ${spoken.name}: ran out, searching the next words'));
        }
        return listing;
      },
      where: (item) {
        if (!_levelVideoShown(item)) return false;
        if (kind == LevelVideoKind.graded || !measure) return true;
        if (reading(item)?.level != band) return false;
        return !free || levelVideos.showFree(item.id);
      },
      rank: measure
          ? (item) => switch (reading(item)) {
                final r? => levelVideoScore(kind == LevelVideoKind.graded ? null : band, r,
                    seconds: item.duration,
                    tier: tier,
                    channelFit: levelVideos.channelFit(language, item.channelId)),
                null => -1,
              }
          : null,
      fill: 8,
      readAhead: languages == null,
      name:
          'Level videos ${kind.name} ${spoken.name}${kind == LevelVideoKind.native ? ' ${band.name}' : ''}',
    )..loadMore();
  }

  /// Lessons of [language] explained in [explainedIn], those naming the
  /// learner's level first. Free: only a search and the language check.
  VideoListLoader? lessonVideoList(String language, ExploreLanguage explainedIn) {
    final repository = _repository;
    final languages = _videoLanguages;
    if (repository == null) return null;
    final level = learning.levelIn(language);
    final tag = levelTag(language, level);
    final queries = lessonQueries(language, levelTierOf(language, level), explainedIn, tag: tag);
    final hl = explainedIn.youtubeHl;
    final picked = preferences.exploreRegion.gl;
    final region = picked.isNotEmpty ? picked : explainedIn.homeCountry;
    final sp = searchParams(type: SearchFilter.videos)!;
    final check = languages != null && VideoLanguages.available;
    return VideoListLoader(
      () => _withoutPortraits(Listing.deferred(() async {
        // Put into the explanation language as explore puts its zones'
        // words, phrase by phrase and kept on disk; the level's own name
        // (N5, HSK 3) is added untranslated.
        final asked = [for (final q in queries) q.words];
        final translated =
            queries.every((q) => !q.translated) ? asked : await _searchWordsIn(asked, explainedIn);
        final anchor = explainedIn.searchAnchor;
        final words = [
          for (final (i, q) in queries.indexed)
            if (q.withTag(translated[i]) case final w)
              anchor == null || w.contains(anchor) ? w : '$w $anchor',
        ];
        logInfo(
            'Lessons of $language in ${explainedIn.name}: searching ${words.map((w) => '"$w"').join(', ')} (hl $hl, gl ${region ?? '-'})');
        return repository.searchMix(words, sp: sp, region: region, hl: hl);
      })).refined(
          (lines) => check ? languages.only(lines, explainedIn, listedInLanguage: true) : lines),
      where: (item) => _levelVideoShown(item) && (check || explainedIn.matches(item.title)),
      rank: (item) => lessonFit(item.title, tag).toDouble(),
      fill: 8,
      readAhead: !check,
      name: 'Lessons of $language in ${explainedIn.name}',
    )..loadMore();
  }
}

/// What keeps videos spoken in the language from being measured.
enum LevelVideosBlock {
  /// The learning features are off (Settings › Learning).
  learningOff,

  /// The language's dictionary is not downloaded or not ready yet.
  dictionary,

  /// The language core is missing on this build.
  unavailable,
}
