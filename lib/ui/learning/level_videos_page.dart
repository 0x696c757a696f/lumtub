part of 'learning_page.dart';

/// 按水平找视频, from the learning page or from Explore's 语言学习.
Future<void> openLevelVideos(BuildContext context, AppController controller) =>
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (context) => _LevelVideosPage(controller: controller)));

/// The learning home's card that opens it.
class _LevelVideosCard extends StatelessWidget {
  const _LevelVideosCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: AppStyle.cardRadius,
          onTap: () => unawaited(openLevelVideos(context, controller)),
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: _CardTitle(
              icon: AppIcons.filmReel,
              title: tr('Videos at your level'),
              subtitle: tr(
                  'Real videos sorted by how many of their words you know, and lessons explained in your language'),
              trailing: Icon(AppIcons.caretRight),
            ),
          ),
        ),
      );
}

/// The language picked last, else one with a level, else one with a
/// dictionary, else English (Spanish for those who read English).
String _defaultLevelLanguage(AppController controller) {
  final learning = controller.learning;
  final picked = controller.levelVideos.language;
  if (picked != null && levelTestLanguages.contains(picked)) return picked;
  final withLevel = levelTestLanguages.where((l) => learning.levelIn(l) != null).firstOrNull;
  if (withLevel != null) return withLevel;
  final withDictionary = levelTestLanguages
      .where((l) => DictionaryPack.values
          .any((p) => p.language == l && learning.stateOf(p) != PackState.missing))
      .firstOrNull;
  if (withDictionary != null) return withDictionary;
  return controller.interfaceExploreLanguage == ExploreLanguage.en ? 'es' : 'en';
}

class _LevelVideosPage extends StatefulWidget {
  const _LevelVideosPage({required this.controller});
  final AppController controller;

  @override
  State<_LevelVideosPage> createState() => _LevelVideosPageState();
}

class _LevelVideosPageState extends State<_LevelVideosPage> {
  AppController get controller => widget.controller;
  Learning get learning => controller.learning;

  late String _language = _defaultLevelLanguage(controller);
  late ExploreLanguage _explainedIn =
      controller.levelVideos.explainedIn ?? controller.interfaceExploreLanguage;
  late LevelVideoKind _kind = levelTierOf(_language, learning.levelIn(_language)) == 0 ||
          controller.levelVideosBlock(_language) == LevelVideosBlock.unavailable
      ? LevelVideoKind.graded
      : LevelVideoKind.native;
  VideoLevel _band = VideoLevel.right;
  VideoListLoader? _loader;
  LevelCheck? _check;

  /// How many times the learner asked to keep looking past the budget.
  int _rounds = 1;

  /// What the list shown was made for, to tell when it must be made again.
  Object? _made;

  Object get _wanted => (
        _kind,
        _language,
        _band,
        _explainedIn,
        learning.levelKey,
        controller.levelVideosBlock(_language)
      );

  @override
  void initState() {
    super.initState();
    learning.addListener(_learningChanged);
    _reload();
  }

  @override
  void dispose() {
    learning.removeListener(_learningChanged);
    _loader?.dispose();
    super.dispose();
  }

  /// A dictionary that became ready, a level taken, the pack unlocked:
  /// the list is made again for it.
  void _learningChanged() {
    if (!mounted || _made == _wanted) return;
    setState(_reload);
  }

  void _reload() {
    _loader?.dispose();
    _check = null;
    _made = _wanted;
    void checked(LevelCheck check) {
      if (mounted) setState(() => _check = check);
    }

    _loader = switch (_kind) {
      LevelVideoKind.lessons => controller.lessonVideoList(_language, _explainedIn),
      final kind =>
        controller.spokenVideoList(_language, kind, band: _band, rounds: _rounds, checked: checked),
    };
  }

  void _set(VoidCallback change) {
    Haptics.select();
    setState(() {
      change();
      _rounds = 1;
      controller.levelVideos.choose(language: _language, explainedIn: _explainedIn);
      _reload();
    });
  }

  void _keepLooking() {
    Haptics.select();
    setState(() {
      _rounds++;
      _reload();
    });
  }

  void _open(VideoItem item, List<VideoItem> items) {
    unawaited(controller.play(item, from: items));
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// The level's name, as the level test names it; null without one.
  String? get _levelName {
    final level = learning.levelIn(_language);
    if (level == null) return null;
    return _levelTestName(_language, _language == 'en' ? level + 1 : level);
  }

  @override
  Widget build(BuildContext context) {
    final loader = _loader;
    return Scaffold(
      appBar: SkinAppBar(AppBar(title: Text(tr('Videos at your level')))),
      body: VideoActions(
        controller: controller,
        child: ListenableBuilder(
          listenable: Listenable.merge([if (loader != null) loader, controller.levelVideos]),
          builder: (context, _) {
            final items = loader?.items ?? const <VideoItem>[];
            final loading = loader?.loading ?? false;
            final error = loader?.error;
            final block =
                _kind == LevelVideoKind.native ? controller.levelVideosBlock(_language) : null;
            final measured =
                _kind != LevelVideoKind.lessons && controller.levelVideosBlock(_language) == null;
            final free = _kind == LevelVideoKind.native && measured && !learning.unlocked;
            final usedUp = free && controller.levelVideos.freeLeft <= 0;
            final check = _check;
            final stopped = !loading &&
                error == null &&
                check != null &&
                (check.budgetSpent || check.refused) &&
                !usedUp;
            return NearEndListener(
              onNearEnd: () => loader?.loadMore(),
              child: CustomScrollView(slivers: [
                SliverToBoxAdapter(child: _header(context)),
                if (block != null)
                  SliverToBoxAdapter(child: _blocked(context, block))
                else ...[
                  if (_kind != LevelVideoKind.lessons &&
                      measured &&
                      learning.levelIn(_language) == null)
                    SliverToBoxAdapter(child: _noLevel(context)),
                  if (_kind == LevelVideoKind.graded && !measured)
                    SliverToBoxAdapter(child: _unsorted(context)),
                  if (items.isNotEmpty)
                    SliverReveal(
                      key: ValueKey(_made),
                      sliver: SliverVideoGrid(
                          items: items,
                          thumbnails: controller.thumbnailDirectory,
                          onOpen: (item) => _open(item, items),
                          reasons: _reasons(items)),
                    ),
                  if (loading) ...[
                    if (items.isNotEmpty)
                      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
                    SliverSkeletonGrid(rows: items.isEmpty ? 2 : 1),
                  ],
                  if (error != null)
                    SliverToBoxAdapter(
                        child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
                      child: ErrorBanner(
                          items.isEmpty
                              ? tr("Couldn't load: {0}", [error])
                              : tr("Couldn't load more: {0}", [error]),
                          onRetry: () => loader?.loadMore(retry: true)),
                    )),
                  if (stopped && items.isNotEmpty)
                    SliverToBoxAdapter(child: _stopped(context, check)),
                  if (free && !loading && (items.isNotEmpty || usedUp))
                    SliverToBoxAdapter(child: _freeEnd(context)),
                  if (items.isEmpty && !loading && error == null && loader != null && !usedUp)
                    SliverFillRemaining(
                        hasScrollBody: false,
                        child: stopped
                            ? _stopped(context, check, alone: true)
                            : _empty(context, loader)),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: Space.xxxl)),
              ]),
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final colors = context.colors;
    final levelName = _levelName;
    final check = _check;
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppStyle.pagePadding, Space.s, AppStyle.pagePadding, Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OptionChip<String>(
                icon: AppIcons.translate,
                value: _language,
                values: levelTestLanguages,
                label: (l) => tr('Learning {0}', [_languageName(l)]),
                item: _languageName,
                changed: false,
                onSelected: (l) => _set(() => _language = l),
              ),
              ActionChip(
                avatar: Icon(AppIcons.chartBar, size: 18),
                label:
                    Text(levelName == null ? tr('Find your level') : tr('Level: {0}', [levelName])),
                tooltip: tr('Find your level in 2 minutes'),
                onPressed: () => unawaited(openLevelTest(context, learning, language: _language)),
              ),
              if (_kind == LevelVideoKind.lessons)
                OptionChip<ExploreLanguage>(
                  icon: AppIcons.chatCenteredText,
                  value: _explainedIn,
                  values: [
                    for (final l in ExploreLanguage.values)
                      if (l != ExploreLanguage.any) l
                  ],
                  label: (l) => tr('Explained in {0}', [l.label]),
                  item: (l) => l.label,
                  changed: _explainedIn != controller.interfaceExploreLanguage,
                  onSelected: (l) => _set(() => _explainedIn = l),
                ),
            ]),
        const SizedBox(height: Space.m),
        FittingSegments<LevelVideoKind>(
          values: LevelVideoKind.values,
          label: (k) => switch (k) {
            LevelVideoKind.graded => tr('Graded listening'),
            LevelVideoKind.native => tr('Native videos'),
            LevelVideoKind.lessons => tr('Lessons'),
          },
          selected: _kind,
          onSelected: (k) => _set(() => _kind = k),
        ),
        const SizedBox(height: Space.s),
        AnimatedSwitcher(
          duration: Motion.of(Ease.fade),
          child: Text(
            key: ValueKey(_kind),
            switch (_kind) {
              LevelVideoKind.graded => tr(
                  'Made for learners: spoken in {0}, slowly, with pictures and gestures. Good from the first day.',
                  [_languageName(_language)]),
              LevelVideoKind.native => tr(
                  'What speakers of {0} watch themselves, by how much of it you would understand.',
                  [_languageName(_language)]),
              LevelVideoKind.lessons => tr(
                  'Videos that teach {0} in a language you read, those for your level first.',
                  [_languageName(_language)]),
            },
            style: context.text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        AnimatedSize(
          duration: Motion.of(Ease.move),
          curve: Ease.curve,
          alignment: Alignment.topCenter,
          child: _kind != LevelVideoKind.native
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: Space.m),
                  Wrap(spacing: Space.s, runSpacing: Space.s, children: [
                    for (final band in const [
                      VideoLevel.right,
                      VideoLevel.easy,
                      VideoLevel.challenging,
                      VideoLevel.hard,
                      VideoLevel.tooHard
                    ])
                      ChoiceChip(
                        label: Text(_bandName(band)),
                        selected: _band == band,
                        onSelected: (_) => _set(() => _band = band),
                      ),
                  ]),
                  const SizedBox(height: Space.s),
                  AnimatedSwitcher(
                    duration: Motion.of(Ease.fade),
                    child: Text(
                      key: ValueKey(_band),
                      _bandHint(_band),
                      style: context.text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                ]),
        ),
        if (_kind != LevelVideoKind.lessons && check != null && check.asked > 0) ...[
          const SizedBox(height: Space.xs),
          Text(
            tr('Checked {0} videos in {1}, read the subtitles of {2}',
                [check.asked, _languageName(_language), check.measured]),
            style: context.text.labelSmall?.copyWith(color: colors.outline),
          ),
        ],
      ]),
    );
  }

  static String _bandName(VideoLevel band) => switch (band) {
        VideoLevel.easy => tr('Easy'),
        VideoLevel.right => tr('Just right'),
        VideoLevel.challenging => tr('Challenging'),
        VideoLevel.hard => tr('Difficult'),
        VideoLevel.tooHard => tr('Too hard'),
      };

  static String _bandHint(VideoLevel band) => switch (band) {
        VideoLevel.right =>
          tr('You know about 95 to 98% of what is said: easy to follow, with new words to learn.'),
        VideoLevel.easy =>
          tr('You know 98% or more of what is said: for relaxed listening and fluency.'),
        VideoLevel.challenging => tr(
            'You know about 90 to 95%: for careful listening, looking words up and playing lines again.'),
        VideoLevel.hard =>
          tr('You know about 80 to 90%: you will need the subtitles and many lookups.'),
        VideoLevel.tooHard => tr(
            'You know less than 80%: most lines would stop for a word. The other tabs leave these out.'),
      };

  Map<String, String> _reasons(List<VideoItem> items) {
    if (_kind == LevelVideoKind.lessons) {
      final tag = levelTag(_language, learning.levelIn(_language));
      return {
        for (final item in items)
          if (tag != null && lessonFit(item.title, tag) == 2)
            item.id: tr('For your level ({0})', [tag]),
      };
    }
    return {
      for (final item in items)
        if (controller.levelVideos.readingOf(item.id) case final r?
            when r.known != null && r.language == _language)
          item.id: _readingLine(r),
    };
  }

  /// "≈96% known · 4 new words a minute", with the pace when it is not
  /// everyday and a note when YouTube's automatic captions were read.
  static String _readingLine(LevelReading r) => [
        tr('≈{0}% known', [(r.known! * 100).floor()]),
        tr('{0} new words a minute', [r.newPerMinute.round()]),
        if (r.pace == SpeechPace.slow) tr('Slow speech'),
        if (r.pace == SpeechPace.fast) tr('Fast speech'),
        if (r.doubtful)
          tr('Subtitles may be unreliable')
        else if (r.automatic)
          tr('From automatic captions'),
      ].join(' · ');

  Widget _noLevel(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, Space.l),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(Space.l, Space.s, Space.s, Space.s),
        decoration:
            BoxDecoration(color: colors.secondaryContainer, borderRadius: AppStyle.cardRadius),
        child: Row(children: [
          Icon(AppIcons.info, size: 20, color: colors.onSecondaryContainer),
          const SizedBox(width: Space.m),
          Expanded(
            child: Text(
              tr('Without your level, only the words in your vocabulary book count as known, and most videos look too hard. The test takes 2 minutes.'),
              style: TextStyle(color: colors.onSecondaryContainer),
            ),
          ),
          TextButton(
              onPressed: () => unawaited(openLevelTest(context, learning, language: _language)),
              child: Text(tr('Take the test'))),
        ]),
      ),
    );
  }

  Widget _blocked(BuildContext context, LevelVideosBlock block) {
    final pack = controller.levelDictionary(_language);
    final state = pack == null ? null : learning.stateOf(pack);
    final busy = state == PackState.downloading || state == PackState.loading;
    final graded = TextButton(
        onPressed: () => _set(() => _kind = LevelVideoKind.graded),
        child: Text(tr('See graded listening instead')));
    final (icon, title, message, Widget? action) = switch (block) {
      LevelVideosBlock.learningOff => (
          AppIcons.graduationCap,
          tr('Language learning is off'),
          tr('Turn on the learning features to see how much of each video you would understand. Graded listening and lessons work without them.'),
          FilledButton(
              onPressed: () => unawaited(controller.setLearningMode(true)),
              child: Text(tr('Turn on'))),
        ),
      LevelVideosBlock.dictionary => (
          AppIcons.downloadSimple,
          tr('Download the {0} dictionary first', [_languageName(_language)]),
          tr('Lumtub counts the words of each video\'s subtitles with it, on this device.'),
          busy
              ? SizedBox(
                  width: 160, child: LinearProgressIndicator(value: learning.progressOf(pack!)))
              : FilledButton.icon(
                  onPressed: pack == null
                      ? null
                      : () => unawaited(_getDictionary(context, learning, pack)),
                  icon: Icon(AppIcons.downloadSimple, size: 18),
                  label: Text(tr('Download')),
                ),
        ),
      LevelVideosBlock.unavailable => (
          AppIcons.warningCircle,
          tr('Not available in this build'),
          tr('The language core is missing, so the words of subtitles cannot be counted.'),
          null
        ),
    };
    return SizedBox(
      height: 360,
      child: StatusView(
        icon: icon,
        title: title,
        message: message,
        action: Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            alignment: WrapAlignment.center,
            children: [if (action != null) action, graded]),
      ),
    );
  }

  Widget _empty(BuildContext context, VideoListLoader loader) {
    final more = loader.hasMore
        ? FilledButton.icon(
            onPressed: () => loader.loadMore(),
            icon: Icon(AppIcons.magnifyingGlass),
            label: Text(tr('Keep looking')))
        : null;
    if (_kind == LevelVideoKind.lessons) {
      return StatusView(
          icon: AppIcons.bookOpenText,
          title: tr('No lessons found'),
          message: tr('Try explaining in another language.'),
          action: more);
    }
    final beginner = levelTierOf(_language, learning.levelIn(_language)) == 0;
    if (_kind == LevelVideoKind.graded) {
      return StatusView(
          icon: AppIcons.ear,
          title: tr('No graded listening found yet'),
          message: tr('Keep looking, or try the lessons.'),
          action: more);
    }
    return StatusView(
      icon: AppIcons.filmReel,
      title: tr('No videos at this level found yet'),
      message: beginner && _band != VideoLevel.hard && _band != VideoLevel.tooHard
          ? tr(
              'Few native videos are spoken simply enough at the start. Graded listening is made for this.')
          : tr('Keep looking, or try another level.'),
      action:
          Wrap(spacing: Space.s, runSpacing: Space.s, alignment: WrapAlignment.center, children: [
        if (more != null) more,
        if (beginner)
          TextButton(
              onPressed: () => _set(() => _kind = LevelVideoKind.graded),
              child: Text(tr('See graded listening instead'))),
      ]),
    );
  }

  /// Where a search stopped before the end: at the budget of new videos,
  /// with a button to look further, or as YouTube stopped answering.
  Widget _stopped(BuildContext context, LevelCheck check, {bool alone = false}) {
    final message = check.refused
        ? tr('YouTube stopped answering for now. Try again in a few minutes.')
        : tr('Checked {0} new videos this time, to keep data use low.',
            [LevelVideos.budget * _rounds]);
    final action = FilledButton.icon(
      onPressed: _keepLooking,
      icon: Icon(check.refused ? AppIcons.arrowClockwise : AppIcons.magnifyingGlass, size: 18),
      label: Text(check.refused ? tr('Retry') : tr('Keep looking')),
    );
    if (alone) {
      return StatusView(
          icon: AppIcons.filmReel,
          title: tr('No videos at this level found yet'),
          message: message,
          action: action);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
      child: Row(children: [
        Expanded(
            child: Text(message,
                style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant))),
        const SizedBox(width: Space.m),
        action,
      ]),
    );
  }

  /// Under the native videos measured for a learner without the pack:
  /// how many new ones today still allows.
  Widget _freeEnd(BuildContext context) {
    final colors = context.colors;
    final left = controller.levelVideos.freeLeft;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Row(children: [
            _Badge(icon: AppIcons.lockOpen),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    left > 0
                        ? tr('Free: {0} new videos at your level left today', [left])
                        : tr("Today's free videos at your level are used up"),
                    style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: Space.xs),
                Text(
                  tr('The learning pack finds all of them, and sorts them again as you learn words. Graded listening and lessons stay free.'),
                  style: context.text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ]),
            ),
            const SizedBox(width: Space.m),
            FilledButton(
                onPressed: () => unawaited(showLearningLocked(context, learning)),
                child: Text(tr('Unlock'))),
          ]),
        ),
      ),
    );
  }

  /// Over graded listening that cannot be measured yet.
  Widget _unsorted(BuildContext context) {
    final colors = context.colors;
    final block = controller.levelVideosBlock(_language);
    if (block == LevelVideosBlock.unavailable) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, Space.l),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(Space.l, Space.s, Space.s, Space.s),
        decoration:
            BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: AppStyle.cardRadius),
        child: Row(children: [
          Icon(AppIcons.info, size: 20, color: colors.onSurfaceVariant),
          const SizedBox(width: Space.m),
          Expanded(
            child: Text(
              block == LevelVideosBlock.learningOff
                  ? tr(
                      'Turn on the learning features to sort these by how much of each you would understand.')
                  : tr(
                      'Download the {0} dictionary to sort these by how much of each you would understand.',
                      [_languageName(_language)]),
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () {
              if (block == LevelVideosBlock.learningOff) {
                unawaited(controller.setLearningMode(true));
              } else if (controller.levelDictionary(_language) case final pack?) {
                unawaited(_getDictionary(context, learning, pack));
              }
            },
            child: Text(block == LevelVideosBlock.learningOff ? tr('Turn on') : tr('Download')),
          ),
        ]),
      ),
    );
  }
}
