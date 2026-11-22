part of 'learning_page.dart';

/// 学习, the rail's page: the pack's state, the vocabulary book, the
/// dictionaries. A column of cards, each its own widget, so later parts
/// (study progress, notes) add one card to [_LearningHomeState._cards].
/// Colors come from the theme only, so every skin and palette carries it.
class LearningHome extends StatefulWidget {
  const LearningHome({super.key, required this.controller});
  final AppController controller;

  @override
  State<LearningHome> createState() => _LearningHomeState();
}

class _LearningHomeState extends State<LearningHome> {
  AppController get controller => widget.controller;
  Learning get learning => controller.learning;

  @override
  void initState() {
    super.initState();
    unawaited(learning.book?.load());
  }

  List<Widget> _cards(BuildContext context) => [
        if (learning.licenseStopped) _StoppedCard(learning: learning),
        // Today's words first: what a learner comes back to the page for.
        if ((learning.book?.words.isNotEmpty ?? false)) _ReviewHomeCard(controller: controller),
        if (_GettingStarted.needed(learning)) _GettingStarted(controller: controller),
        if (learning.licensed) _StatusCard(controller: controller) else _Pitch(learning: learning),
        _VocabularyCard(controller: controller),
        _DictionariesCard(learning: learning),
        _AboutCard(controller: controller),
      ];

  @override
  Widget build(BuildContext context) {
    final book = learning.book;
    return ListenableBuilder(
      listenable: Listenable.merge([learning, if (book != null) book]),
      builder: (context, _) {
        final words = book?.words.length ?? 0;
        return LayoutBuilder(builder: (context, constraints) {
          // A comfortable reading width; wide windows get margins, not
          // stretched rows.
          final side = constraints.maxWidth > 980 ? (constraints.maxWidth - 940) / 2 : AppStyle.pagePadding;
          return CustomScrollView(slivers: [
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: side - AppStyle.pagePadding),
              sliver: SliverToBoxAdapter(
              child: PageHeader(
                tr('Learning'),
                subtitle: learning.licensed ? tr('{0} words in your vocabulary book', [words]) : tr('Learn languages from real videos'),
                trailing: Wrap(spacing: Space.s, children: [
                  OutlinedButton.icon(
                    onPressed: () => openSettings(context, controller, category: SettingsCategory.learning),
                    icon: Icon(AppIcons.gear),
                    label: Text(tr('Learning settings')),
                  ),
                ]),
              ),
            )),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, Space.xxxl),
              sliver: SliverList.separated(
                itemCount: _cards(context).length,
                separatorBuilder: (context, index) => const SizedBox(height: AppStyle.cardSpacing),
                itemBuilder: (context, i) => _cards(context)[i],
              ),
            ),
          ]);
        });
      },
    );
  }
}

/// A card's title row: an icon in a soft accent circle, the title, and
/// what it holds on the right.
class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title, this.subtitle, this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(children: [
      _Badge(icon: icon),
      const SizedBox(width: Space.m),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (subtitle != null) Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        ]),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, this.size = 40});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.5, color: colors.primary),
    );
  }
}

class _StoppedCard extends StatelessWidget {
  const _StoppedCard({required this.learning});
  final Learning learning;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final devices = learning.licenseStopReason == 'devices';
    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(AppIcons.key, color: colors.onErrorContainer),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('The learning pack is stopped on this device'), style: context.text.titleSmall?.copyWith(color: colors.onErrorContainer, fontWeight: FontWeight.w600)),
              const SizedBox(height: Space.xs),
              Text(
                switch (learning.licenseStopReason) {
                  'revoked' => tr('This code has been revoked because it was shared publicly. If you bought it, write to the author with your order number.'),
                  'refunded' => tr('This order was refunded, so the learning pack is off. Your vocabulary book stays on this device and can still be exported.'),
                  'devices' => tr('This device was removed from the code, which is now on as many devices as it allows. Remove one you no longer use to use it here.'),
                  _ => tr('The license server could not be reached since the code was entered. Connect to the internet and open Lumtub again.'),
                },
                style: TextStyle(color: colors.onErrorContainer),
              ),
              if (devices) ...[
                const SizedBox(height: Space.s),
                FilledButton(onPressed: () => unawaited(manageLicenseDevices(context, learning)), child: Text(tr('Devices'))),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The pack is on: who it is licensed to, what is ready, and the devices.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final learning = controller.learning;
    final colors = context.colors;
    final ready = [for (final p in DictionaryPack.values) if (const {PackState.ready, PackState.downloaded, PackState.loading}.contains(learning.stateOf(p))) p];
    final words = learning.book?.words ?? const <VocabularyWord>[];
    final week = DateTime.now().subtract(const Duration(days: 7));
    final thisWeek = words.where((w) => w.added.isAfter(week)).length;
    Widget stat(String value, String label) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: colors.primary)),
          Text(label, style: context.text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        ]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _CardTitle(
            icon: AppIcons.graduationCap,
            title: tr('Learning pack'),
            subtitle: learningSummary(learning),
            trailing: TextButton(onPressed: () => unawaited(manageLicenseDevices(context, learning)), child: Text(tr('Devices'))),
          ),
          const SizedBox(height: Space.l),
          Wrap(spacing: Space.xxl, runSpacing: Space.m, children: [
            stat('${words.length}', tr('Words saved')),
            stat('$thisWeek', tr('Saved this week')),
            stat('${ready.length}', tr('Dictionaries ready')),
          ]),
          if (ready.isEmpty) ...[
            const SizedBox(height: Space.l),
            Text(
              tr('How to use it: download a dictionary, turn on a Chinese, English or Japanese subtitle, then tap any word on the video or in the subtitle list. The video waits while the word is open. Everything stays on this device.'),
              style: context.text.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.5),
            ),
          ],
        ]),
      ),
    );
  }
}

/// 今天: what today's review holds and how long it will take, its words
/// laid out by the video each was heard in, as a strip of frames; a frame
/// starts a review of that video's words only.
class _ReviewHomeCard extends StatefulWidget {
  const _ReviewHomeCard({required this.controller});
  final AppController controller;

  @override
  State<_ReviewHomeCard> createState() => _ReviewHomeCardState();
}

class _ReviewHomeCardState extends State<_ReviewHomeCard> {
  late final VocabularyBook _book = widget.controller.learning.book!;
  late final ReviewStore _store = reviewStoreOf(_book);

  @override
  void initState() {
    super.initState();
    unawaited(_store.load());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_store, _book]),
        builder: (context, _) {
          final colors = context.colors;
          final now = DateTime.now();
          final queue = _store.due(_book.words, now);
          final due = queue.length;
          final streak = _store.streak(now);
          final known = _store.knownCount(_book.words);
          final locked = !widget.controller.learning.unlocked;
          final scenes = todaysScenes(queue);
          final next = due > 0 ? null : _store.nextDue(_book.words, now);
          final summary = due > 0
              ? tr('{0} words · about {1} min', [due, _store.minutesFor(due)])
              : next == null
                  ? tr('Nothing due right now')
                  : tr('All done · the next words come back in {0}', [reviewIntervalLabel(next.difference(now))]);
          Widget stat(String number, String label) => Padding(
                padding: const EdgeInsets.only(right: Space.xl),
                child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(number, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: Space.xs),
                  Text(label, style: context.text.bodySmall?.copyWith(color: colors.outline)),
                ]),
              );
          final start = FilledButton.icon(
            onPressed: () => unawaited(openReview(context, widget.controller)),
            icon: Icon(locked ? AppIcons.lock : AppIcons.playCircle, size: 18),
            label: Text(due > 0 ? tr('Start review') : tr('Open')),
          );
          // A phone (or a narrow window) gets the button under the title,
          // as wide as the card, where a thumb finds it.
          final narrow = MediaQuery.sizeOf(context).width < 600;
          return Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: EdgeInsets.all(narrow ? Space.m : Space.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _CardTitle(icon: AppIcons.filmStrip, title: tr('Today'), subtitle: summary, trailing: narrow ? null : start),
                if (narrow) ...[
                  const SizedBox(height: Space.m),
                  SizedBox(width: double.infinity, height: 48, child: start),
                ],
                if (scenes.isNotEmpty) ...[
                  const SizedBox(height: Space.l),
                  Text(tr('From {0} videos', [scenes.where((s) => s.videoId.isNotEmpty).length]),
                      style: context.text.labelMedium?.copyWith(color: colors.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  const SizedBox(height: Space.s),
                  SizedBox(
                    height: _SceneTile.heightFor(narrow),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: scenes.length,
                      separatorBuilder: (context, index) => const SizedBox(width: Space.m),
                      itemBuilder: (context, i) => _SceneTile(
                        scene: scenes[i],
                        width: narrow ? 140 : 176,
                        thumbnails: widget.controller.thumbnailDirectory,
                        onTap: () => unawaited(openReview(context, widget.controller, video: scenes[i].videoId)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: Space.m),
                Wrap(runSpacing: Space.xs, children: [
                  stat('$streak', tr('days in a row')),
                  stat('$known', tr('words learnt')),
                ]),
              ]),
            ),
          );
        },
      );
}

/// A video's frame with how many of its words are due and the first of
/// them under it, like a subtitle.
class _SceneTile extends StatelessWidget {
  const _SceneTile({required this.scene, required this.width, required this.thumbnails, required this.onTap});
  final ReviewScene scene;
  final double width;
  final Directory? thumbnails;
  final VoidCallback onTap;

  /// The frame and two lines of title under it.
  static double heightFor(bool narrow) => (narrow ? 140 : 176) * 9 / 16 + 44;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final words = scene.words.map((w) => w.word).take(3).join('  ');
    final frame = ClipRRect(
      borderRadius: context.thumbnailRadius,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(fit: StackFit.expand, children: [
          if (scene.videoId.isEmpty)
            ColoredBox(color: colors.surfaceContainerHighest, child: Icon(AppIcons.bookOpenText, color: colors.outline))
          else
            Image(
              image: thumbnailFor(scene.video, thumbnails, width: 320, size: 'mqdefault'),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => ColoredBox(color: colors.surfaceContainerHighest),
            ),
          // The words over the frame's foot, as the subtitle they were.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xB0000000)])),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.s, Space.l, Space.s, Space.xs),
                child: Text(words, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13, shadows: [Shadow(blurRadius: 3)])),
              ),
            ),
          ),
          Positioned(
            top: Space.xs,
            right: Space.xs,
            child: DecoratedBox(
              decoration: BoxDecoration(color: colors.primary, borderRadius: context.controlRadius),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                child: Text('${scene.words.length}', style: TextStyle(color: colors.onPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      ),
    );
    return SizedBox(
      width: width,
      child: Tooltip(
        message: scene.videoId.isEmpty ? tr('Words without a video') : scene.title,
        waitDuration: const Duration(milliseconds: 500),
        child: InkWell(
          onTap: onTap,
          borderRadius: context.thumbnailRadius,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            frame,
            const SizedBox(height: Space.xs),
            Text(scene.videoId.isEmpty ? tr('Words without a video') : scene.title,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(height: 1.25)),
          ]),
        ),
      ),
    );
  }
}

/// The newest words, each opening its video at its moment, with the
/// whole book and its exports one tap away.
class _VocabularyCard extends StatelessWidget {
  const _VocabularyCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final learning = controller.learning;
    final colors = context.colors;
    final words = learning.book?.words ?? const <VocabularyWord>[];
    final recent = [...words]..sort((a, b) => b.added.compareTo(a.added));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.s, Space.s),
          child: _CardTitle(
            icon: AppIcons.bookOpenText,
            title: tr('Vocabulary book'),
            subtitle: tr('{0} words', [words.length]),
            // Saved words stay the buyer's: seen and exported even when the
            // pack is off here.
            trailing: words.isEmpty ? null : TextButton(onPressed: () => unawaited(openVocabularyBook(context, controller)), child: Text(tr('See all'))),
          ),
        ),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
            child: Text(tr('No words yet. Tap a word in a subtitle and choose Add to vocabulary book.'), style: context.text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          )
        else ...[
          for (final w in recent.take(5))
            ListTile(
              onTap: () => unawaited(showSavedWord(context, controller, w)),
              title: Text.rich(TextSpan(children: [
                TextSpan(text: w.word, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                if (w.reading.isNotEmpty) TextSpan(text: '  ${w.reading}', style: TextStyle(color: colors.primary)),
              ]), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [if (w.meaning.isNotEmpty) w.meaning, if (w.videoTitle.isNotEmpty) w.videoTitle].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: w.videoId.isEmpty
                  ? null
                  : TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: colors.onSurfaceVariant, visualDensity: VisualDensity.compact),
                      onPressed: () => watchVocabularyMoment(context, controller, w),
                      icon: Icon(AppIcons.playCircle, size: 16),
                      label: Text(clockOf(w.at)),
                    ),
            ),
          const SizedBox(height: Space.s),
        ],
      ]),
    );
  }
}

/// One tile per language, laid out in as many columns as fit.
class _DictionariesCard extends StatelessWidget {
  const _DictionariesCard({required this.learning});
  final Learning learning;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _CardTitle(
              icon: AppIcons.translate,
              title: tr('Dictionaries'),
              subtitle: tr('Download the languages you watch; then everything works offline'),
            ),
            const SizedBox(height: Space.l),
            LayoutBuilder(builder: (context, constraints) {
              final columns = (constraints.maxWidth / 260).floor().clamp(1, 3);
              final width = (constraints.maxWidth - Space.m * (columns - 1)) / columns;
              return Wrap(spacing: Space.m, runSpacing: Space.m, children: [
                for (final pack in DictionaryPack.values) SizedBox(width: width, child: _PackCell(learning: learning, pack: pack)),
              ]);
            }),
          ]),
        ),
      );
}

String _packLanguage(DictionaryPack pack) => switch (pack) {
      DictionaryPack.chinese => tr('Chinese'),
      DictionaryPack.english => tr('English'),
      DictionaryPack.japanese => tr('Japanese'),
      DictionaryPack.korean => tr('Korean'),
      DictionaryPack.spanish => tr('Spanish'),
      DictionaryPack.french => tr('French'),
      DictionaryPack.german => tr('German'),
      DictionaryPack.italian => tr('Italian'),
      DictionaryPack.russian => tr('Russian'),
    };

/// The language's own sample, so each tile reads at a glance.
String _packSample(DictionaryPack pack) => switch (pack) {
      DictionaryPack.chinese => '中',
      DictionaryPack.english => 'En',
      DictionaryPack.japanese => 'あ',
      DictionaryPack.korean => '한',
      DictionaryPack.spanish => 'Es',
      DictionaryPack.french => 'Fr',
      DictionaryPack.german => 'De',
      DictionaryPack.italian => 'It',
      DictionaryPack.russian => 'Ру',
    };

class _PackCell extends StatelessWidget {
  const _PackCell({required this.learning, required this.pack});
  final Learning learning;
  final DictionaryPack pack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = learning.stateOf(pack);
    final progress = learning.progressOf(pack);
    final on = const {PackState.ready, PackState.downloaded, PackState.loading}.contains(state);
    final status = switch (state) {
      PackState.missing => tr('Not downloaded'),
      PackState.downloading => progress == null ? tr('Downloading…') : tr('Downloading… {0}%', [(progress * 100).round()]),
      PackState.loading => tr('Loading…'),
      PackState.downloaded || PackState.ready => tr('Ready'),
      PackState.failed => tr('Failed: {0}', [learning.errorOf(pack) ?? '']),
    };
    final action = switch (state) {
            PackState.missing || PackState.failed => IconButton.filledTonal(tooltip: tr('Download'), icon: Icon(learning.unlocked ? AppIcons.downloadSimple : AppIcons.lock, size: 18), onPressed: () => unawaited(_getDictionary(context, learning, pack))),
            PackState.downloading || PackState.loading => SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, value: state == PackState.downloading ? progress : null)),
            PackState.ready || PackState.downloaded => IconButton(tooltip: tr('Delete'), icon: Icon(AppIcons.trash, size: 18, color: colors.onSurfaceVariant), onPressed: () => unawaited(learning.delete(pack))),
          };
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.s),
      decoration: BoxDecoration(
        borderRadius: context.controlRadius,
        border: Border.all(color: on ? colors.primary.withValues(alpha: 0.5) : colors.outlineVariant),
        color: on ? colors.primary.withValues(alpha: 0.06) : null,
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? colors.primary : colors.surfaceContainerHighest, borderRadius: context.controlRadius),
          child: Text(_packSample(pack), style: TextStyle(fontWeight: FontWeight.w700, color: on ? colors.onPrimary : colors.onSurfaceVariant)),
        ),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_packLanguage(pack), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: state == PackState.failed ? colors.error : colors.onSurfaceVariant)),
          ]),
        ),
        SizedBox(width: 40, child: Center(child: action)),
      ]),
    );
  }
}

/// Where the data comes from and what activation keeps.
class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          NormalItem(
            title: tr('Orders and refunds'),
            subtitle: tr('Getting your code again, devices, refunds, and whom to write to'),
            leading: Icon(AppIcons.sealCheck),
            onTap: () => unawaited(showLearningOrders(context)),
          ),
          NormalItem(
            title: tr('Data sources and licenses'),
            subtitle: tr('The dictionaries are open data: who made them and under which license'),
            leading: Icon(AppIcons.info),
            onTap: () => unawaited(showLearningSources(context)),
          ),
          NormalItem(
            title: tr('Activation and privacy'),
            subtitle: tr('What the license server keeps, for how long, and how to have it deleted'),
            leading: Icon(AppIcons.shieldWarning),
            onTap: () => unawaited(showLearningPrivacy(context)),
          ),
        ]),
      );
}

/// 新手引导: three steps to a first word, each ticked off as it is done;
/// gone once all three are.
class _GettingStarted extends StatelessWidget {
  const _GettingStarted({required this.controller});
  final AppController controller;

  static bool _hasDictionary(Learning learning) => DictionaryPack.values.any((p) => const {PackState.ready, PackState.downloaded, PackState.loading}.contains(learning.stateOf(p)));
  static bool needed(Learning learning) => !_hasDictionary(learning) || !learning.lookedUp || (learning.book?.words.isEmpty ?? true);

  @override
  Widget build(BuildContext context) {
    final learning = controller.learning;
    final colors = context.colors;
    final steps = [
      (_hasDictionary(learning), tr('Download the dictionary of a language you watch'), tr('Pick one: a few MB, then it works offline.')),
      (learning.lookedUp, tr('Play a video with subtitles in that language and tap a word'), tr('Pinyin or kana show above the words; the video waits while the card is open.')),
      (learning.book?.words.isNotEmpty ?? false, tr('Add the word to your vocabulary book'), tr('It keeps the line and the moment, and goes to Anki in one tap.')),
    ];
    final next = steps.indexWhere((s) => !s.$1);
    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Get started in three steps'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: colors.onPrimaryContainer)),
          const SizedBox(height: Space.m),
          for (final (i, (done, title, detail)) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done || i == next ? colors.primary : null,
                    border: done || i == next ? null : Border.all(color: colors.onPrimaryContainer.withValues(alpha: 0.4)),
                  ),
                  child: done
                      ? Icon(AppIcons.check, size: 15, color: colors.onPrimary)
                      : Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: i == next ? colors.onPrimary : colors.onPrimaryContainer)),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: context.text.bodyLarge?.copyWith(
                      fontWeight: i == next ? FontWeight.w600 : null,
                      color: colors.onPrimaryContainer.withValues(alpha: done ? 0.6 : 1),
                      decoration: done ? TextDecoration.lineThrough : null,
                    )),
                    if (!done) Text(detail, style: context.text.bodySmall?.copyWith(color: colors.onPrimaryContainer.withValues(alpha: 0.75))),
                    if (i == 0 && !done) _QuickDownload(learning: learning),
                  ]),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// The first step's languages, each downloading its dictionary at a tap,
/// so a new learner need not look for the Dictionaries card further down.
class _QuickDownload extends StatelessWidget {
  const _QuickDownload({required this.learning});
  final Learning learning;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s),
      child: Wrap(spacing: Space.s, runSpacing: Space.s, children: [
        for (final pack in DictionaryPack.values)
          switch (learning.stateOf(pack)) {
            PackState.downloading || PackState.loading => Chip(
                avatar: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, value: learning.progressOf(pack))),
                label: Text(_packLanguage(pack)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            _ => ActionChip(
                avatar: Text(_packSample(pack), style: TextStyle(fontWeight: FontWeight.w700, color: colors.primary)),
                label: Text(_packLanguage(pack)),
                tooltip: learning.stateOf(pack) == PackState.failed ? tr('Failed: {0}', [learning.errorOf(pack) ?? '']) : tr('Download'),
                onPressed: () => unawaited(_getDictionary(context, learning, pack)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
          },
      ]),
    );
  }
}
