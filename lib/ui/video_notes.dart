import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../local_db.dart' show VideoNote;
import 'app_icons.dart';
import 'common.dart';

/// AI 讲解 of a subtitle line, read with the lines around it, with a way
/// to keep the explanation as a note at the line's time.
Future<void> showLineExplanation(BuildContext context, AppController controller, {required String text, required Duration at, List<String> before = const [], List<String> after = const []}) =>
    showDialog<void>(context: context, builder: (context) => _Explanation(controller: controller, text: text, at: at, before: before, after: after));

class _Explanation extends StatefulWidget {
  const _Explanation({required this.controller, required this.text, required this.at, required this.before, required this.after});
  final AppController controller;
  final String text;
  final Duration at;
  final List<String> before;
  final List<String> after;

  @override
  State<_Explanation> createState() => _ExplanationState();
}

class _ExplanationState extends State<_Explanation> {
  String? _answer;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    setState(() {
      _answer = null;
      _error = null;
    });
    try {
      final answer = await widget.controller.explainLine(widget.text, before: widget.before, after: widget.after);
      if (mounted) setState(() => _answer = answer);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final answer = _answer;
    return AlertDialog(
      title: Row(children: [
        Icon(AppIcons.lightbulb, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(tr('AI explanation'))),
      ]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: SelectionArea(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              _Quote(at: widget.at, text: widget.text),
              const SizedBox(height: 16),
              if (answer != null)
                Text(answer, style: const TextStyle(height: 1.6))
              else if (_error case final error?)
                ErrorBanner(error, onRetry: _run)
              else
                Row(children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  const SizedBox(width: 12),
                  Text(tr('Asking AI…'), style: TextStyle(color: colors.onSurfaceVariant)),
                ]),
            ]),
          ),
        ),
      ),
      actions: [
        if (answer != null) TextButton(onPressed: () => copyText(context, answer, tr('Copied')), child: Text(tr('Copy'))),
        if (answer != null)
          TextButton.icon(
            icon: Icon(AppIcons.notePencil, size: 18),
            label: Text(tr('Save as note')),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final saved = await showNoteEditor(context, widget.controller, at: widget.at, quote: widget.text, body: answer);
              if (saved) navigator.pop();
            },
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
      ],
    );
  }
}

/// A note on the playing video at [at], or a change to [note]: the
/// subtitle words, which can be cut down to the part that matters, and
/// what the person has to say, which AI can tidy up. True once kept.
Future<bool> showNoteEditor(BuildContext context, AppController controller, {Duration at = Duration.zero, String quote = '', String body = '', VideoNote? note}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => _NoteEditor(controller: controller, at: note?.at ?? at, quote: note?.quote ?? quote, body: note?.body ?? body, note: note),
    ) ??
    false;

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({required this.controller, required this.at, required this.quote, required this.body, this.note});
  final AppController controller;
  final Duration at;
  final String quote;
  final String body;
  final VideoNote? note;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _quote = TextEditingController(text: widget.quote);
  late final _body = TextEditingController(text: widget.body);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _quote.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _tidy() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tidied = await widget.controller.tidyNote(_quote.text, _body.text);
      if (mounted && tidied.isNotEmpty) _body.text = tidied;
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_quote.text.trim().isEmpty && _body.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = widget.note;
      if (note == null) {
        await widget.controller.addNote(at: widget.at, quote: _quote.text, body: _body.text);
      } else {
        await widget.controller.changeNote(note, quote: _quote.text, body: _body.text);
      }
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('Note saved')), duration: const Duration(seconds: 2)));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(AppIcons.notePencil, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(widget.note == null ? tr('Note at {0}', [formatClock(widget.at)]) : tr('Edit note'))),
      ]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _quote,
              minLines: 1,
              maxLines: 6,
              decoration: InputDecoration(labelText: tr('Said in the video'), helperText: tr('Cut it down to the part that matters')),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _body,
              autofocus: widget.body.isEmpty,
              minLines: 3,
              maxLines: 12,
              decoration: InputDecoration(labelText: tr('Your note'), alignLabelWithHint: true),
            ),
            if (_error case final error?) ...[const SizedBox(height: 12), ErrorBanner(error)],
          ]),
        ),
      ),
      actions: [
        if (widget.controller.canSummarize)
          TextButton.icon(
            onPressed: _busy ? null : _tidy,
            icon: Icon(AppIcons.sparkle, size: 18),
            label: Text(tr('Tidy up with AI')),
          ),
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
        FilledButton(onPressed: _busy ? null : _save, child: Text(tr('Save'))),
      ],
    );
  }
}

/// Subtitle words with the time they are said.
class _Quote extends StatelessWidget {
  const _Quote({required this.at, required this.text, this.onTap});
  final Duration at;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final quote = Container(
      padding: const EdgeInsetsDirectional.only(start: 12),
      decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: colors.outlineVariant, width: 3))),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '${formatClock(at)}  ', style: TextStyle(color: colors.primary, fontFeatures: const [FontFeature.tabularFigures()])),
        TextSpan(text: text, style: TextStyle(color: colors.onSurfaceVariant)),
      ]), style: const TextStyle(height: 1.5)),
    );
    return onTap == null ? quote : InkWell(onTap: onTap, child: quote);
  }
}

/// The notes on the playing video, in the order of the video: a tap goes
/// to the moment, each can be changed or deleted, all can be copied.
class VideoNotesList extends StatefulWidget {
  const VideoNotesList({super.key, required this.controller, required this.onSeek});
  final AppController controller;
  final ValueChanged<Duration> onSeek;

  @override
  State<VideoNotesList> createState() => _VideoNotesListState();
}

class _VideoNotesListState extends State<VideoNotesList> {
  late Future<List<VideoNote>> _notes = _load();

  Future<List<VideoNote>> _load() => widget.controller.notesOf(widget.controller.playing?.id ?? '');

  void _changed() {
    if (mounted) setState(() => _notes = _load());
  }

  @override
  void initState() {
    super.initState();
    widget.controller.notesChanged.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.notesChanged.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<List<VideoNote>>(
      future: _notes,
      builder: (context, snapshot) {
        final notes = snapshot.data ?? const <VideoNote>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text(tr('My notes'), style: Theme.of(context).textTheme.titleSmall)),
            if (notes.isNotEmpty)
              IconButton(
                tooltip: tr('Copy all notes'),
                visualDensity: VisualDensity.compact,
                icon: Icon(AppIcons.copy, size: 18),
                onPressed: () => copyText(context, notesText(widget.controller.details?.title ?? notes.first.title, notes), tr('Notes copied')),
              ),
            IconButton(
              tooltip: tr('Add a note here'),
              visualDensity: VisualDensity.compact,
              icon: Icon(AppIcons.plus, size: 18),
              onPressed: () => unawaited(showNoteEditor(context, widget.controller, at: widget.controller.player?.state.position ?? Duration.zero)),
            ),
          ]),
          if (notes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr('Right-click or long-press a line in the subtitle list to explain it with AI or keep it as a note.'), style: TextStyle(fontSize: 12, color: colors.outline, height: 1.5)),
            ),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    _Quote(at: note.at, text: note.quote.isEmpty ? '' : note.quote, onTap: () => widget.onSeek(note.at)),
                    if (note.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: SelectableText(note.body, style: const TextStyle(height: 1.5))),
                  ]),
                ),
                PopupMenuButton<String>(
                  tooltip: tr('More'),
                  icon: Icon(AppIcons.dotsThreeVertical, size: 18, color: colors.outline),
                  onSelected: (action) async {
                    if (action == 'edit') {
                      await showNoteEditor(context, widget.controller, note: note);
                    } else if (action == 'delete') {
                      await widget.controller.forgetNote(note);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
                    PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
                  ],
                ),
              ]),
            ),
        ]);
      },
    );
  }
}

/// [notes] on the video [title] as Markdown, for copying.
String notesText(String title, List<VideoNote> notes) => [
      '# $title',
      for (final note in notes)
        [
          if (note.quote.isNotEmpty) '> [${formatClock(note.at)}] ${note.quote.replaceAll('\n', ' ')}' else '[${formatClock(note.at)}]',
          if (note.body.isNotEmpty) note.body,
        ].join('\n\n'),
    ].join('\n\n');
