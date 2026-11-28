import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_controller.dart';
import '../../appearance_settings.dart' show languageStyle;
import '../../l10n/l10n.dart';
import '../../learning/review.dart';
import '../../learning/vocabulary.dart';
import '../../models.dart';
import '../app_icons.dart';
import '../motion.dart';
import '../skin_paint.dart';
import '../theme.dart';
import '../video_card.dart' show thumbnailFor;
import 'learning_page.dart' show LearningPriceTag, buyLearningPack;

/// 复习生词: the vocabulary book's words that are due, one at a time, each
/// in the line it was heard in, with that line's own sound; only those
/// heard in [video] when given.
Future<void> openReview(BuildContext context, AppController controller, {String? video}) async {
  final book = controller.learning.book;
  if (book == null) return;
  await book.load();
  await reviewStoreOf(book).load();
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => ReviewPage(controller: controller, video: video)));
}

/// Plays [word]'s video from a second before the moment it was saved.
void watchVocabularyMoment(BuildContext context, AppController controller, VocabularyWord word) {
  if (word.videoId.isEmpty) return;
  final start =
      word.at > const Duration(seconds: 1) ? word.at - const Duration(seconds: 1) : Duration.zero;
  unawaited(controller.play(
      VideoItem(
          id: word.videoId,
          title: word.videoTitle,
          channel: '',
          url: 'https://www.youtube.com/watch?v=${word.videoId}'),
      at: start));
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// A saved word's card: the word in its line, reading, meaning and
/// translation, the line's own sound, and a way back to its moment.
Future<void> showSavedWord(
    BuildContext context, AppController controller, VocabularyWord word) async {
  final book = controller.learning.book;
  final sound = book?.soundOf(word.key);
  final hasSound = sound != null && await sound.exists();
  if (hasSound) unawaited(controller.playSoundFile(sound));
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialog) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Entrance(
          scale: 0.97,
          child: SavedWordCard(
            word: word,
            shown: true,
            sound: hasSound,
            onReplay: () => unawaited(controller.playSoundFile(sound!)),
            onOpenVideo: () => watchVocabularyMoment(dialog, controller, word),
          ),
        ),
      ),
    ),
  );
}

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.controller, this.video});
  final AppController controller;

  /// Only the words heard in this video (empty: those saved without one).
  final String? video;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final VocabularyBook _book = widget.controller.learning.book!;
  late final ReviewStore _store = reviewStoreOf(_book);
  late List<VocabularyWord> _queue = [
    for (final w in _store.due(_book.words, DateTime.now()))
      if (widget.video == null || w.videoId == widget.video) w,
  ];
  late final int _total = _queue.length;
  final _focus = FocusNode();
  int _done = 0;
  bool _shown = false;
  bool _sound = false;
  // A second tap, swipe or repeated key while a grade is saved is let go.
  bool _grading = false;
  DateTime _since = DateTime.now();

  VocabularyWord? get _word => _queue.firstOrNull;

  @override
  void initState() {
    super.initState();
    unawaited(_playLine());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _playLine() async {
    final word = _word;
    if (word == null) return;
    final played = await widget.controller.playSoundFile(_book.soundOf(word.key));
    if (mounted && word == _word) setState(() => _sound = played);
  }

  Future<void> _grade(ReviewGrade grade) async {
    final word = _word;
    if (word == null || !_shown || _grading) return;
    _grading = true;
    final now = DateTime.now();
    try {
      await _store.grade(word.key, grade, now,
          seconds: now.difference(_since).inMilliseconds / 1000);
    } finally {
      _grading = false;
    }
    if (!mounted) return;
    setState(() {
      _queue = [..._queue.skip(1)];
      // Forgotten: once more at the end of this session.
      if (grade == ReviewGrade.again) {
        _queue.add(word);
      } else {
        _done++;
      }
      _shown = false;
      _sound = false;
      _since = DateTime.now();
    });
    unawaited(_playLine());
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (!_shown && (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter)) {
      setState(() => _shown = true);
      return KeyEventResult.handled;
    }
    if (_shown) {
      final grade = switch (key) {
        LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 => ReviewGrade.again,
        LogicalKeyboardKey.digit2 || LogicalKeyboardKey.numpad2 => ReviewGrade.hard,
        LogicalKeyboardKey.digit3 ||
        LogicalKeyboardKey.numpad3 ||
        LogicalKeyboardKey.space ||
        LogicalKeyboardKey.enter =>
          ReviewGrade.good,
        LogicalKeyboardKey.digit4 || LogicalKeyboardKey.numpad4 => ReviewGrade.easy,
        _ => null,
      };
      if (grade != null) {
        unawaited(_grade(grade));
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.keyF) {
      unawaited(_store.setFocus(!_store.focus));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      unawaited(_playLine());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static bool get _touch => Platform.isAndroid || Platform.isIOS;

  void _openVideo(VocabularyWord word) => watchVocabularyMoment(context, widget.controller, word);

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: _store, builder: (context, _) => _page(context));

  Widget _page(BuildContext context) {
    final learning = widget.controller.learning;
    final word = _word;
    final focus = _store.focus;
    // The scene needs the word's video; a word saved without one keeps
    // its card.
    final scene = focus && word != null && word.videoId.isNotEmpty;
    final touchHint = tr('Tap the card for the answer · swipe right: remembered, left: forgot');
    final keyHint =
        tr('Space shows the answer · 1 2 3 4 grade · R plays the line again · F focus mode');
    Widget answerArea(VocabularyWord word) => AnimatedSwitcher(
          duration: Motion.of(Ease.fade),
          child: _shown
              ? _GradeButtons(
                  key: const ValueKey('grades'),
                  store: _store,
                  word: word,
                  quiet: focus,
                  onGrade: (g) => unawaited(_grade(g)))
              : SizedBox(
                  key: const ValueKey('show'),
                  height: 64,
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: () => setState(() => _shown = true),
                      child: Text(tr('Show the answer'))),
                ),
        );
    Widget card(VocabularyWord word) => GestureDetector(
          key: ValueKey('${word.key}#$_done#${_queue.length}#$scene'),
          // On a touch screen the card itself answers: a tap turns it
          // over, then a swipe right is Remembered and a swipe left Forgot.
          behavior: HitTestBehavior.translucent,
          onTap: _touch && !_shown ? () => setState(() => _shown = true) : null,
          onHorizontalDragEnd: !_touch || !_shown
              ? null
              : (details) {
                  final speed = details.primaryVelocity ?? 0;
                  if (speed.abs() < 300) return;
                  unawaited(HapticFeedback.selectionClick());
                  unawaited(_grade(speed > 0 ? ReviewGrade.good : ReviewGrade.again));
                },
          child: scene
              ? ReviewScenePanel(
                  word: word,
                  shown: _shown,
                  sound: _sound,
                  thumbnails: widget.controller.thumbnailDirectory,
                  onReplay: () => unawaited(_playLine()),
                  onOpenVideo: () => _openVideo(word),
                )
              : SavedWordCard(
                  word: word,
                  shown: _shown,
                  sound: _sound,
                  onReplay: () => unawaited(_playLine()),
                  onOpenVideo: () => _openVideo(word),
                ),
        );
    return Scaffold(
      appBar: SkinAppBar(AppBar(
        title: Text(tr('Review words')),
        actions: [
          if (learning.unlocked)
            Padding(
              padding: const EdgeInsets.only(right: Space.s),
              child: IconButton(
                tooltip: focus
                    ? tr('Leave focus mode (F)')
                    : tr('Focus mode: the video scene, no numbers (F)'),
                isSelected: focus,
                icon: Icon(AppIcons.filmStrip),
                selectedIcon: Icon(AppIcons.filmStrip, color: context.colors.primary),
                onPressed: () => unawaited(_store.setFocus(!focus)),
              ),
            ),
        ],
      )),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _key,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: scene ? 820 : 620),
            child: Padding(
              padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? Space.m : Space.l),
              child: !learning.unlocked
                  ? const Center(child: ReviewPlate(child: _ReviewLocked()))
                  : word == null
                      ? Center(
                          child: ReviewPlate(
                              child: _ReviewDone(store: _store, book: _book, done: _done)))
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          // Focus mode drops the count: only the words.
                          if (!focus) ...[
                            ReviewPlate(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: Space.m, vertical: Space.s),
                              child: _Progress(done: _done, total: _total, left: _queue.length),
                            ),
                            const SizedBox(height: Space.m),
                          ],
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: Motion.of(Ease.move),
                              switchInCurve: Ease.curve,
                              transitionBuilder: (child, animation) => FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                    position: Tween(begin: const Offset(0.06, 0), end: Offset.zero)
                                        .animate(animation),
                                    child: child),
                              ),
                              layoutBuilder: (current, previous) => Stack(
                                  alignment: Alignment.topCenter,
                                  children: [...previous, if (current != null) current]),
                              child: card(word),
                            ),
                          ),
                          const SizedBox(height: Space.m),
                          ReviewPlate(
                            padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, Space.xs),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              answerArea(word),
                              const SizedBox(height: Space.xs),
                              Text(
                                _touch ? touchHint : keyHint,
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(fontSize: 11, color: context.colors.onSurfaceVariant),
                              ),
                            ]),
                          ),
                        ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a review's parts sit on: the skin's panel (its colours, gradient,
/// glass and border), so text reads over any skin's picture; Lumtub's own
/// card without a skin.
class ReviewPlate extends StatelessWidget {
  const ReviewPlate({super.key, required this.child, this.padding = const EdgeInsets.all(Space.l)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final panel = context.skin?.panel;
    if (panel != null) {
      return SkinBox(
          surface: panel, radius: context.cardRadius.topLeft.x, padding: padding, child: child);
    }
    return Card(child: Padding(padding: padding, child: child));
  }
}

/// 专注复习's card: the word's video as a screen, its line over the
/// picture as the subtitle it was (the word lit up in it), the line's
/// translation under it as a second subtitle once shown, and the word's
/// reading and meaning on the skin's panel below.
class ReviewScenePanel extends StatelessWidget {
  const ReviewScenePanel(
      {super.key,
      required this.word,
      required this.shown,
      required this.sound,
      required this.thumbnails,
      required this.onReplay,
      required this.onOpenVideo});
  final VocabularyWord word;
  final bool shown;
  final bool sound;
  final Directory? thumbnails;
  final VoidCallback onReplay;
  final VoidCallback onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sentence = word.sentence.isEmpty ? word.word : word.sentence;
    final at = sentence.toLowerCase().indexOf(word.word.toLowerCase());
    const outline = [
      Shadow(blurRadius: 4),
      Shadow(blurRadius: 2),
      Shadow(offset: Offset(0, 1), blurRadius: 1)
    ];
    // Sized to the screen as the player sizes subtitles: smaller on a
    // phone, never too small to read.
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 600;
    final line = TextStyle(
        color: Colors.white,
        fontSize: (width / 34).clamp(16, 24),
        height: 1.4,
        fontWeight: FontWeight.w600,
        shadows: outline);
    // The accent where it reads on the dark foot of the picture, else a
    // warm yellow, as subtitles light up a word.
    final lit = colors.primary.computeLuminance() > 0.18 ? colors.primary : const Color(0xFFFFD54F);
    final screen = ClipRRect(
      borderRadius: context.cardRadius,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Colors.black),
          Image(
            image: thumbnailFor(
                ReviewScene(word.videoId, word.videoTitle, const []).video, thumbnails,
                width: 1280, size: 'maxresdefault'),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
          // Darker toward the foot, where the subtitle is, as on the player.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.35, 1],
                  colors: [Color(0x14000000), Color(0xC8000000)]),
            ),
          ),
          Positioned(
            left: narrow ? Space.m : Space.xl,
            right: narrow ? Space.m : Space.xl,
            bottom: narrow ? Space.s : Space.l,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text.rich(
                at < 0
                    ? TextSpan(text: sentence)
                    : TextSpan(children: [
                        TextSpan(text: sentence.substring(0, at)),
                        TextSpan(
                          text: sentence.substring(at, at + word.word.length),
                          style: TextStyle(
                              color: lit,
                              decoration: TextDecoration.underline,
                              decorationColor: lit,
                              decorationThickness: 2),
                        ),
                        TextSpan(text: sentence.substring(at + word.word.length)),
                      ]),
                textAlign: TextAlign.center,
                style: line,
              ),
              AnimatedSize(
                duration: Motion.of(Ease.move),
                curve: Ease.curve,
                child: shown && word.translation.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: Space.xs),
                        child: Text(word.translation,
                            textAlign: TextAlign.center,
                            style: line.copyWith(
                                fontSize: narrow ? 13 : 16,
                                fontWeight: FontWeight.w400,
                                color: Colors.white.withValues(alpha: 0.9))),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ]),
          ),
          // The moment it comes from, a tap away.
          Positioned(
            left: Space.s,
            top: Space.s,
            right: Space.s,
            child: Row(children: [
              Flexible(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: context.controlRadius,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onOpenVideo,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(AppIcons.playCircle, size: 16, color: Colors.white),
                        const SizedBox(width: Space.xs),
                        Flexible(
                          child: Text(
                            '${word.videoTitle.isEmpty ? tr('Watch this moment') : word.videoTitle} · ${clockOf(word.at)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (sound)
                IconButton.filled(
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.45),
                      foregroundColor: Colors.white),
                  tooltip: tr('Play the line again'),
                  onPressed: onReplay,
                  icon: Icon(AppIcons.speakerHigh, size: 18),
                ),
            ]),
          ),
        ]),
      ),
    );
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        screen,
        AnimatedSize(
          duration: Motion.of(Ease.move),
          curve: Ease.curve,
          alignment: Alignment.topCenter,
          child: !shown
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: Space.m),
                  child: Entrance(
                    scale: 0.98,
                    child: ReviewPlate(
                      child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.end,
                          spacing: Space.l,
                          runSpacing: Space.xs,
                          children: [
                            SelectableText(word.word,
                                style: theme.textTheme.headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)
                                    .merge(languageStyle(word.language))),
                            if (word.reading.isNotEmpty)
                              Text(word.reading,
                                  style:
                                      theme.textTheme.titleMedium?.copyWith(color: colors.primary)),
                            if (word.meaning.isNotEmpty)
                              Text(word.meaning, style: theme.textTheme.bodyLarge),
                          ]),
                    ),
                  ),
                ),
        ),
      ]),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total, required this.left});
  final int done;
  final int total;
  final int left;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = total == 0 ? 0.0 : done / total;
    return Row(children: [
      Expanded(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: value),
          duration: Motion.of(Ease.move),
          curve: Ease.curve,
          builder: (context, v, _) => ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
                value: v,
                minHeight: 6,
                color: colors.primary,
                backgroundColor: colors.primaryContainer),
          ),
        ),
      ),
      const SizedBox(width: Space.m),
      Text(tr('{0} left', [left]), style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
    ]);
  }
}

/// The word in its line: the line and its sound first, the word lit up in
/// it; the reading, meaning and translation once shown.
class SavedWordCard extends StatelessWidget {
  const SavedWordCard(
      {super.key,
      required this.word,
      required this.shown,
      required this.sound,
      required this.onReplay,
      required this.onOpenVideo});
  final VocabularyWord word;
  final bool shown;
  final bool sound;
  final VoidCallback onReplay;
  final VoidCallback onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sentence = word.sentence;
    final at = sentence.toLowerCase().indexOf(word.word.toLowerCase());
    final lineStyle = theme.textTheme.titleMedium
        ?.copyWith(height: 1.6, fontWeight: FontWeight.w400)
        .merge(languageStyle(word.language));
    return ReviewPlate(
      padding: const EdgeInsets.all(Space.xl),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: SelectableText(word.word,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)
                        .merge(languageStyle(word.language)))),
            if (sound)
              IconButton(
                  tooltip: tr('Play the line again'),
                  onPressed: onReplay,
                  icon: Icon(AppIcons.speakerHigh, color: colors.primary)),
          ]),
          if (sentence.isNotEmpty) ...[
            const SizedBox(height: Space.m),
            Text.rich(
              at < 0
                  ? TextSpan(text: sentence)
                  : TextSpan(children: [
                      TextSpan(text: sentence.substring(0, at)),
                      TextSpan(
                        text: sentence.substring(at, at + word.word.length),
                        style: TextStyle(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                            decorationColor: colors.primary),
                      ),
                      TextSpan(text: sentence.substring(at + word.word.length)),
                    ]),
              style: lineStyle,
            ),
          ],
          AnimatedSize(
            duration: Motion.of(Ease.move),
            curve: Ease.curve,
            alignment: Alignment.topLeft,
            child: !shown
                ? const SizedBox(width: double.infinity)
                : Entrance(
                    scale: 0.98,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Divider(height: Space.xl * 1.5, color: colors.outlineVariant),
                      if (word.reading.isNotEmpty)
                        Text(word.reading,
                            style: theme.textTheme.titleMedium?.copyWith(color: colors.primary)),
                      if (word.meaning.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(word.meaning, style: theme.textTheme.bodyLarge)),
                      if (word.translation.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.m),
                          child: Text(word.translation,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: colors.onSurfaceVariant)),
                        ),
                      if (word.videoId.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.m),
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                            onPressed: onOpenVideo,
                            icon: Icon(AppIcons.playCircle, size: 18),
                            label: Text(
                              '${word.videoTitle.isEmpty ? tr('Watch this moment') : word.videoTitle} · ${clockOf(word.at)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _GradeButtons extends StatelessWidget {
  const _GradeButtons(
      {super.key,
      required this.store,
      required this.word,
      required this.onGrade,
      this.quiet = false});
  final ReviewStore store;
  final VocabularyWord word;

  /// Focus mode: the grades without the intervals they give.
  final bool quiet;
  final ValueChanged<ReviewGrade> onGrade;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();
    Widget button(ReviewGrade grade, String label, {Color? color, bool main = false}) {
      final next = store.preview(word.key, grade, now).due.difference(now);
      // One line each, shrunk rather than wrapped, so long words fit the
      // row on a narrow phone.
      final content = FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (!quiet) ...[
            const SizedBox(height: 2),
            Text(reviewIntervalLabel(next),
                maxLines: 1,
                style: TextStyle(
                    fontSize: 11,
                    color:
                        main ? colors.onPrimary.withValues(alpha: 0.8) : colors.onSurfaceVariant)),
          ],
        ]),
      );
      const padding = EdgeInsets.symmetric(vertical: 6);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: main
              ? FilledButton(
                  style: FilledButton.styleFrom(
                      padding: padding,
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary),
                  onPressed: () => onGrade(grade),
                  child: content)
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      padding: padding, foregroundColor: color ?? colors.onSurface),
                  onPressed: () => onGrade(grade),
                  child: content,
                ),
        ),
      );
    }

    return SizedBox(
      height: 64,
      child: Row(children: [
        button(ReviewGrade.again, tr('Forgot'), color: colors.error),
        button(ReviewGrade.hard, tr('Hard')),
        button(ReviewGrade.good, tr('Remembered'), main: true),
        button(ReviewGrade.easy, tr('Easy')),
      ]),
    );
  }
}

/// All done for now: what today did, the streak, and words learnt.
class _ReviewDone extends StatelessWidget {
  const _ReviewDone({required this.store, required this.book, required this.done});
  final ReviewStore store;
  final VocabularyBook book;
  final int done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final now = DateTime.now();
    final streak = store.streak(now);
    final next = [for (final w in book.words) store.of(w.key)?.due]
        .whereType<DateTime>()
        .where((d) => d.isAfter(now))
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    Widget stat(String number, String label) => Expanded(
          child: Column(children: [
            Text(number,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800, color: colors.primary)),
            Text(label, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          ]),
        );
    return Entrance(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(AppIcons.checkCircle, size: 56, color: colors.primary),
        const SizedBox(height: Space.m),
        Text(
          book.words.isEmpty
              ? tr('No words yet')
              : (done > 0 ? tr('Done for today') : tr('Nothing to review right now')),
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Space.s),
        Text(
          book.words.isEmpty
              ? tr(
                  'Tap words in subtitles and add them to the vocabulary book; they come back here when it is time.')
              : next == null
                  ? ''
                  : tr('The next words come back in {0}.',
                      [reviewIntervalLabel(next.difference(now))]),
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        if (book.words.isNotEmpty) ...[
          const SizedBox(height: Space.xl),
          Row(children: [
            stat('$done', tr('reviewed now')),
            stat('$streak', tr('days in a row')),
            stat('${store.knownCount(book.words)}', tr('words learnt')),
          ]),
        ],
        const SizedBox(height: Space.xl),
        OutlinedButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(tr('Back'))),
      ]),
    );
  }
}

class _ReviewLocked extends StatelessWidget {
  const _ReviewLocked();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(AppIcons.lock, size: 40, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(height: Space.m),
      Text(tr('Review is part of the learning pack'),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: Space.s),
      Text(
          tr('Words come back just before you would forget them, each with the line it was said in.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: Space.l),
      const LearningPriceTag(),
      const SizedBox(height: Space.l),
      Wrap(spacing: Space.s, children: [
        FilledButton(
            onPressed: () => unawaited(buyLearningPack()),
            child: Text(tr('Buy the learning pack'))),
      ]),
    ]);
  }
}
