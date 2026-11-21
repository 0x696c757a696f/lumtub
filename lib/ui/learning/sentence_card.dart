import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'dart:convert' show utf8;

import '../../app/app_controller.dart';
import '../../intelligence.dart' show Capability;
import '../../l10n/l10n.dart';
import '../../learning/anki_connect.dart';
import '../../learning/sentence_explainer.dart';
import '../../video_summary.dart' show summaryLanguage;
import '../app_icons.dart';
import '../common.dart';
import '../video_notes.dart';
import 'learning_page.dart' show showLearningLocked;

SentenceExplainer? _explainer;

SentenceExplainer? _explainerOf(AppController controller) {
  final directories = controller.directories;
  if (directories == null) return null;
  return _explainer ??= SentenceExplainer(cache: Directory('${directories.cache.path}${Platform.pathSeparator}explanations'));
}

/// Whether AI 讲这句 is worth offering: the person's own AI service is set
/// up, or the learning pack (or its trial) may ask the server's helper.
bool canExplainSentences(AppController controller) => controller.intelligence.can(Capability.complete) || controller.learning.unlocked;

/// The subtitle lines just before and after [at], for context.
Future<({List<String> before, List<String> after})> linesAround(AppController controller, Duration at) async {
  try {
    final cues = await controller.listedSubtitleCues();
    var i = cues.lastIndexWhere((c) => c.cue.start <= at + const Duration(milliseconds: 300));
    if (i < 0) i = 0;
    return (
      before: [for (final c in cues.sublist(i > 3 ? i - 3 : 0, i)) c.cue.text],
      after: [for (final c in cues.skip(i + 1).take(2)) c.cue.text],
    );
  } catch (_) {
    return (before: const <String>[], after: const <String>[]);
  }
}

/// AI 讲这句: the subtitle line [text], heard at [at], taken apart for a
/// learner in the interface language. A learning pack feature; without
/// the pack, the person's own AI service still gives the plain AI 讲解.
Future<void> showSentenceExplanation(BuildContext context, AppController controller,
    {required String text, required Duration at, List<String>? before, List<String>? after}) async {
  final learning = controller.learning;
  if (!learning.unlocked) {
    if (controller.intelligence.can(Capability.complete)) {
      final around = before == null || after == null ? await linesAround(controller, at) : null;
      if (!context.mounted) return;
      return showLineExplanation(context, controller, text: text, at: at, before: before ?? around!.before, after: after ?? around!.after);
    }
    return showLearningLocked(context, learning, title: tr('AI explains this line: a learning pack feature'));
  }
  final explainer = _explainerOf(controller);
  if (explainer == null) return;
  final around = before == null || after == null ? await linesAround(controller, at) : null;
  if (!context.mounted) return;
  final player = controller.player;
  final wasPlaying = player?.state.playing ?? false;
  if (wasPlaying) unawaited(player!.pause());
  await showDialog<void>(
    context: context,
    builder: (context) => _SentenceCard(
      controller: controller,
      explainer: explainer,
      text: text.trim(),
      at: at,
      before: before ?? around!.before,
      after: after ?? around!.after,
    ),
  );
  if (wasPlaying && controller.player == player) unawaited(player?.play());
}

class _SentenceCard extends StatefulWidget {
  const _SentenceCard({required this.controller, required this.explainer, required this.text, required this.at, required this.before, required this.after});
  final AppController controller;
  final SentenceExplainer explainer;
  final String text;
  final Duration at;
  final List<String> before;
  final List<String> after;

  @override
  State<_SentenceCard> createState() => _SentenceCardState();
}

class _SentenceCardState extends State<_SentenceCard> {
  SentenceExplanation? _answer;
  ExplainException? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run({bool fresh = false}) async {
    setState(() {
      _answer = null;
      _error = null;
    });
    final controller = widget.controller;
    final intelligence = controller.intelligence;
    final own = intelligence.can(Capability.complete);
    try {
      final answer = await widget.explainer.explain(
        widget.text,
        language: summaryLanguage,
        title: controller.details?.title.isNotEmpty == true ? controller.details!.title : controller.playing?.title ?? '',
        before: widget.before,
        after: widget.after,
        complete: own ? (system, user) => intelligence.complete(system, user, temperature: 0.2) : null,
        pass: own ? null : await controller.learning.serverPass(),
        fresh: fresh,
      );
      if (mounted) setState(() => _answer = answer);
    } on ExplainException catch (e) {
      if (mounted) setState(() => _error = e);
    } catch (e) {
      if (mounted) setState(() => _error = ExplainException('$e'));
    }
  }

  Future<void> _toAnki() async {
    final answer = _answer;
    if (answer == null) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final controller = widget.controller;
    final anki = AnkiConnect();
    try {
      File? sound;
      final book = controller.learning.book;
      if (book != null) {
        final key = 'line:${sha256.convert(utf8.encode('${controller.playing?.id}|${widget.at.inMilliseconds}|${widget.text}')).toString().substring(0, 24)}';
        await controller.keepWordSound(key, widget.at);
        sound = book.soundOf(key);
      }
      final title = controller.details?.title ?? controller.playing?.title ?? '';
      final id = controller.playing?.id;
      final link = id == null ? '' : 'https://www.youtube.com/watch?v=$id&t=${widget.at.inSeconds > 1 ? widget.at.inSeconds - 1 : 0}s';
      final added = await anki.sendSentence(
        front: widget.text,
        back: [answer.plain, if (link.isNotEmpty) '${title.isEmpty ? '' : '$title\n'}$link'].join('\n\n'),
        sound: sound,
      );
      messenger?.showSnackBar(SnackBar(content: Text(added ? tr('Sent to the Lumtub deck in Anki') : tr('This line is in the Lumtub deck already'))));
    } on AnkiException catch (e) {
      messenger?.showSnackBar(SnackBar(
        content: Text(e.notRunning ? tr('Anki did not answer. Open Anki with the AnkiConnect add-on (code 2055492159), or use the Anki file instead.') : tr('Anki said: {0}', [e.detail])),
      ));
    } finally {
      anki.close();
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final answer = _answer;
    final error = _error;
    return AlertDialog(
      title: Row(children: [
        Icon(AppIcons.lightbulb, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(tr('AI explains this line'))),
      ]),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: SelectionArea(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                child: Text(widget.text, style: theme.textTheme.titleMedium!.copyWith(height: 1.5)),
              ),
              const SizedBox(height: 16),
              if (answer != null)
                ExplanationView(answer)
              else if (error != null)
                _Problem(error: error, controller: widget.controller, onRetry: _run)
              else
                Row(children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  const SizedBox(width: 12),
                  Text(tr('Asking AI…'), style: TextStyle(color: colors.onSurfaceVariant)),
                ]),
              if (answer != null) ...[
                const SizedBox(height: 12),
                Text(tr('Written by AI and may be wrong.'), style: TextStyle(fontSize: 11, color: colors.outline)),
              ],
            ]),
          ),
        ),
      ),
      actions: [
        if (answer != null) ...[
          IconButton(tooltip: tr('Ask again'), icon: Icon(AppIcons.arrowClockwise, size: 18), onPressed: () => unawaited(_run(fresh: true))),
          IconButton(tooltip: tr('Copy'), icon: Icon(AppIcons.copy, size: 18), onPressed: () => unawaited(copyText(context, '${widget.text}\n\n${answer.plain}', tr('Copied')))),
          IconButton(
            tooltip: tr('Save as note'),
            icon: Icon(AppIcons.notePencil, size: 18),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final saved = await showNoteEditor(context, widget.controller, at: widget.at, quote: widget.text, body: answer.plain);
              if (saved) navigator.pop();
            },
          ),
          FilledButton.tonalIcon(
            icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(AppIcons.cards, size: 18),
            label: Text(tr('Send to Anki')),
            onPressed: _sending ? null : () => unawaited(_toAnki()),
          ),
        ],
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
      ],
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.error, required this.controller, required this.onRetry});
  final ExplainException error;
  final AppController controller;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(error.message, style: TextStyle(color: error.limit || error.needsPack ? colors.onSurface : colors.error, height: 1.5)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        if (error.needsPack)
          FilledButton(
            onPressed: () => unawaited(showLearningLocked(context, controller.learning, title: tr('AI explains this line: a learning pack feature'))),
            child: Text(tr('About the learning pack')),
          )
        else if (!error.limit)
          OutlinedButton(onPressed: onRetry, child: Text(tr('Try again'))),
      ]),
    ]);
  }
}

/// An explanation laid out in its parts, each under a small heading.
class ExplanationView extends StatelessWidget {
  const ExplanationView(this.answer, {super.key});
  final SentenceExplanation answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const body = TextStyle(height: 1.6);
    if (answer.text.isNotEmpty) return Text(answer.text, style: body);
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(text, style: theme.textTheme.labelLarge!.copyWith(color: colors.primary)),
        );
    Widget bullet(Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 9, right: 8), child: Container(width: 4, height: 4, decoration: BoxDecoration(color: colors.outline, shape: BoxShape.circle))),
            Expanded(child: child),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (answer.translation.isNotEmpty) Text(answer.translation, style: body.copyWith(fontWeight: FontWeight.w600)),
      if (answer.meaning.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(answer.meaning, style: body)),
      if (answer.grammar.isNotEmpty) ...[heading(tr('How it is built')), for (final g in answer.grammar) bullet(Text(g, style: body))],
      if (answer.why.isNotEmpty) ...[heading(tr('Why it is said this way')), Text(answer.why, style: body)],
      if (answer.others.isNotEmpty) ...[
        heading(tr('Other ways to say it')),
        for (final o in answer.others)
          bullet(Text.rich(TextSpan(children: [
            TextSpan(text: o.text, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (o.note.isNotEmpty) TextSpan(text: '  ${o.note}', style: TextStyle(color: colors.onSurfaceVariant)),
          ]), style: body)),
      ],
      if (answer.mistakes.isNotEmpty) ...[heading(tr('Common mistakes')), for (final m in answer.mistakes) bullet(Text(m, style: body))],
      if (answer.words.isNotEmpty) ...[
        heading(tr('Words to learn')),
        for (final w in answer.words)
          bullet(Text.rich(TextSpan(children: [
            TextSpan(text: w.word, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (w.reading.isNotEmpty) TextSpan(text: '  ${w.reading}', style: TextStyle(color: colors.primary)),
            if (w.meaning.isNotEmpty) TextSpan(text: '  ${w.meaning}'),
          ]), style: body)),
      ],
    ]);
  }
}
