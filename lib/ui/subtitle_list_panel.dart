import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

import '../app/app_controller.dart';
import '../app_log.dart';
import '../app_preferences.dart' show SubtitleListMode;
import '../friendly_error.dart';
import '../l10n/l10n.dart';
import '../language_guess.dart' show readsAs;
import '../learning/known_words.dart';
import '../learning/learning.dart';
import '../learning/vocabulary.dart' show VocabularyBook;
import '../models.dart' show SubtitleOption;
import '../save_file.dart';
import '../subtitle_cues.dart';
import '../translation.dart' show translateForeignLines;
import 'app_icons.dart';
import 'common.dart';
import 'learning/ruby_line.dart';
import 'learning/word_card.dart';
import 'motion.dart';
import 'player_panel.dart';
import 'study_bar.dart' show StudyVeil;
import 'video_notes.dart';

/// 字幕列表: every line of the main subtitle beside the video, with the
/// second subtitle's words under it, the one being spoken marked and kept
/// in view. A tap jumps there; the copy button copies the line, and a
/// right click or long press offers to copy it, explain it with AI or keep
/// it as a note. Words searched for are marked.
Future<void> showSubtitleList(BuildContext context, AppController controller, Player player) => showPlayerPanel(
      context,
      title: tr('Subtitle list'),
      width: 420,
      builder: (context) => SubtitleList(controller: controller, player: player),
    );

class SubtitleList extends StatefulWidget {
  const SubtitleList({super.key, required this.controller, required this.player});
  final AppController controller;
  final Player player;

  @override
  State<SubtitleList> createState() => _SubtitleListState();
}

class _SubtitleListState extends State<SubtitleList> {
  late Future<List<PairedCue>> _cues = widget.controller.listedSubtitleCues();
  final _scroll = ScrollController();
  StreamSubscription<Object?>? _trackChanges;
  StreamSubscription<Duration>? _positions;
  int _current = -1;
  /// Following the playing line stops while the person scrolls.
  bool _follow = true;
  String _query = '';
  Timer? _typing;
  final _currentKey = GlobalKey();

  late SubtitleOption? _second = widget.controller.secondarySubtitle;
  late String _secondTrack = widget.controller.secondaryTrackId;
  late SubtitleListMode _mode = widget.controller.preferences.subtitleListMode;

  /// 按整句阅读: short caption lines joined into whole sentences, each
  /// with its translation made from the whole sentence. Kept while the app
  /// runs.
  static bool _readBySentence = false;
  bool _bySentence = _readBySentence;
  (List<PairedCue>, List<PairedCue>)? _sentences;
  /// Whole-sentence translations asked for, by sentence.
  final _wholeTranslations = <String, Future<String?>>{};
  /// What is selected in the list (with a mouse), for the menu's 讲解 and
  /// 记笔记 of part of a line.
  String _selected = '';
  /// Which search match was stepped to last, for the arrows.
  int _match = -1;

  /// [cues] as listed: line by line, or as whole sentences.
  List<PairedCue> _rowsOf(List<PairedCue> cues) {
    if (!_bySentence) return cues;
    final kept = _sentences;
    if (kept != null && identical(kept.$1, cues)) return kept.$2;
    final rows = sentenceRows(cues);
    _sentences = (cues, rows);
    return rows;
  }

  /// The translation of the whole [sentence] into the language set for
  /// translations, asked once; null when it is already in that language
  /// or could not be translated.
  Future<String?> _wholeTranslation(String sentence) => _wholeTranslations.putIfAbsent(sentence, () async {
        final prefs = widget.controller.preferences;
        final target = prefs.translateTarget;
        bool done(String line) => readsAs(line, target, chineseAsOne: prefs.chineseAsOne);
        if (done(sentence)) return null;
        try {
          final result = (await translateForeignLines(widget.controller.translator, sentence, target, done)).trim();
          return result.isEmpty || result == sentence.trim() ? null : result;
        } catch (_) {
          return null;
        }
      });

  void _toggleSentences() => setState(() {
        _bySentence = _readBySentence = !_bySentence;
        _current = -1;
        _match = -1;
        unawaited(_positions?.cancel());
        _positions = null;
      });

  /// Seeks to the next ([step] 1) or previous (-1) line that matches the
  /// search, as YouTube Digest's arrows do, and marks it.
  void _stepMatch(List<PairedCue> rows, List<int> shown, int step) {
    if (shown.isEmpty) return;
    final at = shown.indexOf(_current);
    final from = at >= 0 ? at : _match;
    final next = from < 0 ? (step > 0 ? 0 : shown.length - 1) : (from + step) % shown.length;
    setState(() {
      _match = next;
      _current = shown[next];
    });
    unawaited(widget.controller.seek(rows[shown[next]].cue.start));
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(next, shown.length));
  }

  @override
  void initState() {
    super.initState();
    _trackChanges = widget.player.stream.track.listen((_) => _reload());
    widget.controller.addListener(_secondChanged);
    widget.controller.learning.addListener(_learningChanged);
    _watchBook();
  }

  void _learningChanged() {
    _watchBook();
    _learningSeen++;
    if (mounted) setState(() {});
  }

  /// A word saved or removed changes which words are marked.
  VocabularyBook? _book;
  void _watchBook() {
    final book = widget.controller.learning.book;
    if (identical(book, _book)) return;
    _book?.removeListener(_learningChanged);
    _book = book;
    book?.addListener(_learningChanged);
  }

  /// The rows built, each with whether it was the playing line. When the
  /// playing line moves only its old and new rows are built again: building
  /// every row shown, each line cut into words with readings, took the
  /// window's thread long enough to drop frames of a 60 fps video.
  final _rows = <int, (bool, Widget)>{};
  Object? _rowsFor;
  int _learningSeen = 0;
  List<int>? _shown;
  (List<PairedCue>, String)? _shownFor;

  /// The lines that match the search, by index; null for all of them.
  /// Worked out once for each list and search, not each time the playing
  /// line moves.
  List<int>? _shownOf(List<PairedCue> cues) {
    if (_query.isEmpty) return null;
    final key = _shownFor;
    if (key != null && identical(key.$1, cues) && key.$2 == _query) return _shown;
    _shownFor = (cues, _query);
    return _shown = [
      for (final (i, cue) in cues.indexed)
        if (cue.cue.text.toLowerCase().contains(_query) || (cue.second?.toLowerCase().contains(_query) ?? false)) i,
    ];
  }

  /// [text] as words with pinyin a tap looks up, when it is Chinese and
  /// the learning pack's dictionary is there; otherwise plain.
  /// A line whose words a tap looks up; while searching, the matches
  /// marked instead.
  Widget _line(String text, TextStyle style, {required String? other, required Duration at, required ColorScheme colors}) {
    if (_query.isNotEmpty) return _marked(text, style, colors);
    if (!widget.controller.learningOn) return Text(text, style: style);
    final learning = widget.controller.learning;
    final tokens = learning.wordsOf(text);
    if (tokens == null) return Text(text, style: style);
    final book = learning.book;
    final known = book == null || !learning.unlocked ? null : knownWordsOf(book);
    final line = ChineseRubyLine(
      tokens: tokens,
      style: style,
      pinyin: learning.showPinyin,
      hard: learning.isHard,
      hardColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFFC23D) : const Color(0xFFB86E00),
      highlight: book == null ? null : (token) => book.contains(Learning.languageOf(token), token.key) || book.contains(Learning.languageOf(token), token.key.toLowerCase()),
      known: known?.knows,
      onWord: (token) => unawaited(showWordCard(context, widget.controller, token, sentence: text, translation: other, at: at)),
    );
    if (known == null || !known.oneNew(tokens)) return line;
    // One word away from understood: the line most worth learning from.
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Flexible(child: line),
      const SizedBox(width: 6),
      Tooltip(
        message: tr('One new word in this line: the easiest line to learn from'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(6)),
          child: Text('+1', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: colors.primary)),
        ),
      ),
    ]);
  }

  void _reload() => setState(() {
        _cues = widget.controller.listedSubtitleCues();
        _current = -1;
        unawaited(_positions?.cancel());
        _positions = null;
      });

  void _secondChanged() {
    final mode = widget.controller.preferences.subtitleListMode;
    if (identical(widget.controller.secondarySubtitle, _second) && widget.controller.secondaryTrackId == _secondTrack && mode == _mode) return;
    _second = widget.controller.secondarySubtitle;
    _secondTrack = widget.controller.secondaryTrackId;
    _mode = mode;
    _reload();
  }

  /// Both subtitles are on, so there is a choice of what to list.
  bool get _bothOn {
    final main = widget.player.state.track.subtitle;
    if (const {'no', 'auto'}.contains(main.id)) return false;
    // A translation is listed with its original lines too.
    return widget.controller.secondaryOn || widget.controller.listedOriginalOf(main) != null;
  }

  Widget _modeMenu(ColorScheme colors) => PopupMenuButton<SubtitleListMode>(
        tooltip: tr('List shows'),
        initialValue: _mode,
        onSelected: (mode) => unawaited(widget.controller.savePreferences(widget.controller.preferences.copyWith(subtitleListMode: mode))),
        itemBuilder: (context) => [
          for (final mode in SubtitleListMode.values) CheckedPopupMenuItem(value: mode, checked: mode == _mode, child: Text(mode.label)),
        ],
        icon: Icon(AppIcons.rows, color: colors.onSurfaceVariant),
      );

  @override
  void dispose() {
    widget.controller.removeListener(_secondChanged);
    widget.controller.learning.removeListener(_learningChanged);
    _book?.removeListener(_learningChanged);
    _trackChanges?.cancel();
    _positions?.cancel();
    _typing?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _listen(List<PairedCue> cues) {
    final starts = [for (final c in cues) c.cue];
    _positions?.cancel();
    void at(Duration position) {
      final index = cueIndexAt(starts, position);
      if (index == _current || !mounted) return;
      setState(() => _current = index);
      if (_follow && _query.isEmpty && index >= 0) WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(index, cues.length));
    }

    _positions = widget.player.stream.position.listen(at);
    WidgetsBinding.instance.addPostFrameCallback((_) => at(widget.player.state.position));
  }

  /// Scrolls the playing row to a third of the way down. Rows differ in
  /// height, so one not built yet is first jumped near by the average.
  /// Only this list moves: Scrollable.ensureVisible would also scroll the
  /// page around it, as a phone's watch page.
  void _reveal(int index, int count, {bool jump = false}) {
    if (!mounted || !_scroll.hasClients) return;
    if (_rowOffset() case final target?) {
      final position = _scroll.position;
      if ((target - position.pixels).abs() < 1) return;
      final duration = jump ? Duration.zero : Motion.of(const Duration(milliseconds: 200));
      duration == Duration.zero ? position.jumpTo(target) : unawaited(position.animateTo(target, duration: duration, curve: Ease.curve));
      return;
    }
    if (count == 0) return;
    final position = _scroll.position;
    final average = (position.maxScrollExtent + position.viewportDimension) / count;
    position.jumpTo((index * average - position.viewportDimension / 3).clamp(0.0, position.maxScrollExtent));
    // Once built, the row is put exactly in place.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = mounted && _scroll.hasClients ? _rowOffset() : null;
      if (target != null) _scroll.position.jumpTo(target);
    });
  }

  /// Where this list scrolls to show the playing row a third of the way
  /// down, or null when the row is not built.
  double? _rowOffset() {
    final row = _currentKey.currentContext?.findRenderObject();
    if (row == null || !row.attached) return null;
    final viewport = RenderAbstractViewport.maybeOf(row);
    if (viewport == null) return null;
    final position = _scroll.position;
    return viewport.getOffsetToReveal(row, 0.3).offset.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  /// Saves every line, with its translation, as a CSV file where the
  /// person picks: for Anki, a spreadsheet or a word list.
  Future<void> _export(List<PairedCue> cues) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final id = widget.controller.playing?.id ?? 'video';
    try {
      if (!await saveFileAs('lumtub-subtitles-$id.csv', utf8.encode(pairedCuesCsv(cues)), mime: 'text/csv', label: 'CSV', extension: 'csv')) return;
      messenger?.showSnackBar(SnackBar(content: Text(tr('Subtitles exported'))));
    } catch (e) {
      logError('Could not export the subtitles', e);
      messenger?.showSnackBar(SnackBar(content: Text(tr('Export failed: {0}', [friendlyFileError(e)]))));
    }
  }

  /// Copy, AI 讲解 and 记笔记 for line [i], where the person right-clicked
  /// or long-pressed it.
  Future<void> _menu(List<PairedCue> cues, int i, Offset at) async {
    final line = cues[i];
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final local = overlay.globalToLocal(at);
    // Part of a line picked with the mouse: what 讲解 and 记笔记 take.
    final part = _selected.trim();
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(local.dx, local.dy, overlay.size.width - local.dx, overlay.size.height - local.dy),
      items: [
        if (part.isNotEmpty && widget.controller.canSummarize)
          PopupMenuItem(value: 'explainPart', child: ListTile(dense: true, leading: Icon(AppIcons.lightbulb, size: 18), title: Text(tr('Explain the selection with AI')))),
        if (part.isNotEmpty)
          PopupMenuItem(value: 'notePart', child: ListTile(dense: true, leading: Icon(AppIcons.notePencil, size: 18), title: Text(tr('Save the selection as a note')))),
        if (part.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem(value: 'copy', child: ListTile(dense: true, leading: Icon(AppIcons.copy, size: 18), title: Text(tr('Copy')))),
        if (widget.controller.canSummarize) PopupMenuItem(value: 'explain', child: ListTile(dense: true, leading: Icon(AppIcons.lightbulb, size: 18), title: Text(tr('Explain with AI')))),
        PopupMenuItem(value: 'note', child: ListTile(dense: true, leading: Icon(AppIcons.notePencil, size: 18), title: Text(tr('Save as note')))),
      ],
    );
    if (!mounted || picked == null) return;
    final text = [line.cue.text, if (line.second != null) line.second!].join('\n');
    String words(PairedCue c) => c.cue.text;
    final before = [for (final c in cues.sublist(i > 3 ? i - 3 : 0, i)) words(c)];
    final after = [for (final c in cues.sublist(i + 1, i + 4 < cues.length ? i + 4 : cues.length)) words(c)];
    switch (picked) {
      case 'explainPart':
        await showLineExplanation(context, widget.controller, text: part, at: line.cue.start, before: [...before, line.cue.text], after: after);
      case 'notePart':
        await showNoteEditor(context, widget.controller, at: line.cue.start, quote: part, before: [...before, line.cue.text], after: after);
      case 'copy':
        _copy(line);
      case 'explain':
        await showLineExplanation(context, widget.controller, text: line.cue.text, at: line.cue.start, before: before, after: after);
      case 'note':
        await showNoteEditor(context, widget.controller, at: line.cue.start, quote: text, before: before, after: after);
    }
  }

  /// [text] with each place it has [_query] marked.
  Widget _marked(String text, TextStyle style, ColorScheme colors) {
    final query = _query;
    if (query.isEmpty) return Text(text, style: style);
    final lower = text.toLowerCase();
    // Lower case can change a string's length; marking then would be off.
    if (lower.length != text.length) return Text(text, style: style);
    final spans = <TextSpan>[];
    var from = 0;
    for (var at = lower.indexOf(query); at >= 0; at = lower.indexOf(query, at + query.length)) {
      if (at > from) spans.add(TextSpan(text: text.substring(from, at)));
      spans.add(TextSpan(text: text.substring(at, at + query.length), style: TextStyle(backgroundColor: colors.tertiaryContainer, color: colors.onTertiaryContainer)));
      from = at + query.length;
    }
    if (from < text.length) spans.add(TextSpan(text: text.substring(from)));
    return Text.rich(TextSpan(children: spans), style: style);
  }

  void _copy(PairedCue line) {
    unawaited(Clipboard.setData(ClipboardData(text: [line.cue.text, if (line.second != null) line.second!].join('\n'))));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('Subtitle copied')), duration: const Duration(seconds: 1)));
  }

  Widget _row(List<PairedCue> cues, int i, bool playing, ColorScheme colors) {
    final line = cues[i];
    final cue = line.cue;
    final swap = _mode == SubtitleListMode.secondOver && line.second != null;
    final top = swap ? line.second! : cue.text;
    final under = swap ? cue.text : line.second;
    return GestureDetector(
      key: playing ? _currentKey : null,
      onSecondaryTapUp: (details) => unawaited(_menu(cues, i, details.globalPosition)),
      onLongPressStart: (details) => unawaited(_menu(cues, i, details.globalPosition)),
      child: Material(
        color: playing ? colors.secondaryContainer : Colors.transparent,
        child: InkWell(
          onTap: () {
            // The tapped line lights up at once, before the
            // player gets there.
            setState(() {
              _follow = true;
              _current = i;
            });
            unawaited(widget.controller.seek(cue.start));
          },
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 52,
                child: Text(formatClock(cue.start), style: TextStyle(fontSize: 12, color: playing ? colors.onSecondaryContainer : colors.outline, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  _line(
                    top,
                    TextStyle(fontSize: 12, height: 1.4, color: playing ? colors.onSecondaryContainer : colors.onSurface, fontWeight: playing ? FontWeight.w600 : null),
                    other: under,
                    at: cue.start,
                    colors: colors,
                  ),
                  if (_bySentence && !swap)
                    // The whole sentence translated as one, in place of the
                    // second subtitle's lines joined, once it is there.
                    FutureBuilder<String?>(
                      future: _wholeTranslation(cue.text),
                      builder: (context, snapshot) {
                        final words = snapshot.data ?? under;
                        if (words == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _line(
                            words,
                            TextStyle(fontSize: 12, height: 1.4, color: playing ? colors.onSecondaryContainer.withValues(alpha: 0.8) : colors.onSurfaceVariant),
                            other: top,
                            at: cue.start,
                            colors: colors,
                          ),
                        );
                      },
                    )
                  else if (under != null) ...[
                    const SizedBox(height: 2),
                    _line(
                      under,
                      TextStyle(fontSize: 12, height: 1.4, color: playing ? colors.onSecondaryContainer.withValues(alpha: 0.8) : colors.onSurfaceVariant),
                      other: top,
                      at: cue.start,
                      colors: colors,
                    ),
                  ],
                ]),
              ),
              ValueListenableBuilder<int>(
                valueListenable: widget.controller.shadowTakes,
                builder: (context, takes, child) => widget.controller.hasTakeOf(cue)
                    ? IconButton(
                        tooltip: tr('Compare with the original'),
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        icon: Icon(AppIcons.userSound, color: colors.primary),
                        onPressed: () => unawaited(widget.controller.compareShadowing(cue)),
                      )
                    : const SizedBox.shrink(),
              ),
              IconButton(
                tooltip: tr('Copy'),
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: Icon(AppIcons.copy, color: colors.outline),
                onPressed: () => _copy(line),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// With a mouse, words can be picked out of the lines (a right click
  /// then offers to explain or keep just those); a finger long-presses a
  /// line for its menu instead, so touch lists stay as they are.
  Widget _selectable(Widget list) {
    const mouse = {TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS};
    if (!mouse.contains(defaultTargetPlatform)) return list;
    return SelectionArea(
      onSelectionChanged: (content) => _selected = content?.plainText ?? '',
      // The line's own menu (right click) carries 讲解 and 记笔记 for it.
      contextMenuBuilder: (context, state) => const SizedBox.shrink(),
      child: list,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<List<PairedCue>>(
      future: _cues,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final cues = _rowsOf(snapshot.data ?? const <PairedCue>[]);
        if (cues.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                const {'no', 'auto'}.contains(widget.player.state.track.subtitle.id) && widget.controller.secondarySubtitle == null ? tr('Turn on a subtitle first') : tr("This subtitle can't be listed"),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.outline),
              ),
            ),
          );
        }
        if (_positions == null) _listen(cues);
        // Anything a row shows but the playing line builds them all again.
        final rowsFor = Object.hash(cues, _query, _mode, _bySentence, colors, _learningSeen, Localizations.maybeLocaleOf(context), MediaQuery.textScalerOf(context));
        if (rowsFor != _rowsFor) {
          _rowsFor = rowsFor;
          _rows.clear();
        }
        final shown = _shownOf(cues);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(16, 0, _bothOn ? 4 : 16, 8),
            child: Row(children: [
              Expanded(
                child: LeavesByKeys(child: TextField(
                  decoration: InputDecoration(isDense: true, prefixIcon: Icon(AppIcons.magnifyingGlass, size: 20), hintText: tr('Search subtitles')),
                  onChanged: (v) {
                    // Filtering thousands of lines waits for a pause in typing.
                    _typing?.cancel();
                    _typing = Timer(const Duration(milliseconds: 250), () {
                      if (mounted) {
                        setState(() {
                          _query = v.trim().toLowerCase();
                          _match = -1;
                        });
                      }
                    });
                  },
                )),
              ),
              if (shown != null) ...[
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Text(
                    shown.isEmpty ? '0' : '${_match < 0 ? 0 : _match + 1}/${shown.length}',
                    style: TextStyle(fontSize: 12, color: colors.outline, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                IconButton(
                  tooltip: tr('Previous match'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(AppIcons.caretUp, size: 18),
                  onPressed: shown.isEmpty ? null : () => _stepMatch(cues, shown, -1),
                ),
                IconButton(
                  tooltip: tr('Next match'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(AppIcons.caretDown, size: 18),
                  onPressed: shown.isEmpty ? null : () => _stepMatch(cues, shown, 1),
                ),
              ],
              IconButton(
                tooltip: _bySentence ? tr('Show line by line') : tr('Read by whole sentence, translated as a whole'),
                isSelected: _bySentence,
                icon: Icon(AppIcons.bookOpenText, size: 20),
                onPressed: _toggleSentences,
              ),
              if (_bothOn) _modeMenu(colors),
              IconButton(
                tooltip: tr('Export as CSV'),
                icon: Icon(AppIcons.downloadSimple, size: 20),
                onPressed: () => unawaited(_export(cues)),
              ),
            ]),
          ),
          Expanded(
            // The way back floats over the list, so it stays in sight however
            // short the panel is.
            child: Stack(children: [
              Positioned.fill(child: StudyVeil(controller: widget.controller, child: NotificationListener<ScrollStartNotification>(
              // Following stops when the person drags the list, not when it
              // moves by itself or the page around it scrolls.
              onNotification: (n) {
                if (n.depth == 0 && n.dragDetails != null && _follow) setState(() => _follow = false);
                return false;
              },
              child: _selectable(ListView.builder(
                controller: _scroll,
                // Room under the last line for the way back to the playing one.
                padding: const EdgeInsets.only(bottom: 64),
                itemCount: shown?.length ?? cues.length,
                itemBuilder: (context, k) {
                  final i = shown == null ? k : shown[k];
                  final playing = i == _current;
                  if (_rows[i] case (final was, final row) when was == playing) return row;
                  final row = _row(cues, i, playing, colors);
                  _rows[i] = (playing, row);
                  return row;
                },
              )),
            )),),
              if (!_follow)
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  bottom: 12,
                  child: Center(
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        setState(() => _follow = true);
                        if (_current >= 0) WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(_current, cues.length));
                      },
                      icon: Icon(AppIcons.crosshair, size: 18),
                      label: Text(tr('Back to the current line')),
                    ),
                  ),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}
