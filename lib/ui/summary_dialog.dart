import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../models.dart' show SubtitleKind;
import '../video_summary.dart' show VideoOverview;
import 'app_icons.dart';
import 'common.dart';
import 'linked_text.dart';
import 'pages/translation_settings_page.dart';
import 'theme.dart';
import 'video_notes.dart';

/// AI 总结 of the video playing, as AI 概览 (what it is about, chapters
/// and key quotes), with the person's notes on it under it. The times in
/// it seek the video.
Future<void> showVideoSummary(BuildContext context, AppController controller) =>
    showPanel<void>(context, (context) => _SummaryDialog(controller: controller));

class _SummaryDialog extends StatefulWidget {
  const _SummaryDialog({required this.controller});
  final AppController controller;

  @override
  State<_SummaryDialog> createState() => _SummaryDialogState();
}

class _SummaryDialogState extends State<_SummaryDialog> {
  String? _summary;

  /// Whether 语音识别 has subtitles for this video already.
  bool get _speechDone =>
      widget.controller.details?.subtitles.any((s) => s.kind == SubtitleKind.speech) ?? false;
  String? _error;
  (int, int)? _progress;

  @override
  void initState() {
    super.initState();
    final id = widget.controller.playing?.id;
    _summary = id == null ? null : widget.controller.summaryOf(id);
    if (_summary == null && widget.controller.canSummarize) unawaited(_run());
  }

  /// Subtitles from 语音识别 first, then the summary made again from them.
  Future<void> _fromSpeech() async {
    final controller = widget.controller;
    setState(() {
      _error = null;
      _summary = null;
    });
    try {
      await controller.recognizeSpeech();
      controller.forgetSummary(controller.playing?.id ?? '');
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
      return;
    }
    if (mounted) await _run();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _summary = null;
      _progress = null;
    });
    try {
      final summary = await widget.controller.summarize(onProgress: (done, total) {
        if (mounted) setState(() => _progress = (done, total));
      });
      if (mounted) setState(() => _summary = summary);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Out of the way so the moment shows; the summary is kept and opens
  /// again at once.
  void _seek(Duration time) {
    unawaited(widget.controller.seek(time));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final colors = context.colors;
    final summary = _summary;
    final Widget body;
    if (!controller.canSummarize) {
      body = Text(
          tr('AI summary uses the AI interface under Settings › Translation & AI (OpenAI, DeepSeek, Ollama and others). Set up the interface and key, then try again. Only the video title and subtitle text are sent.'),
          style: TextStyle(color: colors.onSurfaceVariant, height: 1.5));
    } else if (summary != null) {
      final overview = VideoOverview.parse(summary);
      body = overview != null
          ? _OverviewView(overview: overview, byAi: controller.chaptersByAi, onTime: _seek)
          : SelectionArea(
              child: LinkedText(summary,
                  style: const TextStyle(height: 1.6), onTime: _seek, onLink: openExternal));
    } else if (_error case final error?) {
      body = ErrorBanner(error, onRetry: _run);
    } else if (controller.speechJob.value != null) {
      body = ValueListenableBuilder(
        valueListenable: controller.speechJob,
        builder: (context, job, _) => Row(children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(
                  job == null
                      ? tr('Reading the subtitles and summarizing…')
                      : job.total > 1
                          ? '${job.stage} ${job.done} / ${job.total}'
                          : job.stage,
                  style: TextStyle(color: colors.onSurfaceVariant))),
        ]),
      );
    } else {
      final progress = _progress;
      body = Row(children: [
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(width: 12),
        Expanded(
            child: Text(
          progress == null || progress.$1 == 0
              ? tr('Reading the subtitles and summarizing…')
              : progress.$1 < progress.$2 - 1
                  ? tr('Long video, going through it in parts: {0} / {1}',
                      [progress.$1, progress.$2 - 1])
                  : tr('Putting it together…'),
          style: TextStyle(color: colors.onSurfaceVariant),
        )),
      ]);
    }
    return PanelDialog(
      scrollable: true,
      title: Row(children: [
        Icon(AppIcons.sparkleFill, color: colors.primary),
        const SizedBox(width: 8),
        Flexible(child: Text(tr('AI summary'), overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(4)),
          child: Text(tr('Experimental'),
              maxLines: 1, style: TextStyle(fontSize: 11, color: colors.outline)),
        ),
      ]),
      content: SizedBox(
        width: 560,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              body,
              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
              VideoNotesList(controller: controller, onSeek: _seek),
            ]),
      ),
      actions: [
        if (!controller.canSummarize)
          TextButton(
            onPressed: () async {
              await openTranslationSettings(context, controller);
              if (mounted) setState(() {});
              if (mounted && controller.canSummarize && _summary == null) unawaited(_run());
            },
            child: Text(tr('Set up AI service')),
          ),
        // Without subtitles the summary came from the description only.
        if (controller.canSummarize &&
            !AppController.hasOwnSubtitles(controller.details) &&
            !_speechDone &&
            controller.canRecognizeSpeech &&
            controller.speechJob.value == null &&
            (summary != null || _error != null))
          TextButton.icon(
              onPressed: _fromSpeech,
              icon: Icon(AppIcons.waveform, size: 18),
              label: Text(tr('Summarize again with speech recognition'))),
        if (summary != null)
          TextButton(
              onPressed: () => copyText(
                  context, VideoOverview.parse(summary)?.text ?? summary, tr('Summary copied')),
              child: Text(tr('Copy'))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
      ],
    );
  }
}

class _OverviewView extends StatelessWidget {
  const _OverviewView({required this.overview, required this.byAi, required this.onTime});
  final VideoOverview overview;

  /// Whether the chapters are on the progress bar, the video having none.
  final bool byAi;
  final ValueChanged<Duration> onTime;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final heading = Theme.of(context).textTheme.titleSmall;
    final time =
        TextStyle(color: colors.primary, fontFeatures: const [FontFeature.tabularFigures()]);
    Widget row(Duration at, Widget child) => InkWell(
          onTap: () => onTime(at),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 64, child: Text(formatClock(at), style: time)),
              Expanded(child: child),
            ]),
          ),
        );
    return SelectionArea(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (overview.about.isNotEmpty) ...[
              Text(tr('Summary by AI'), style: heading),
              Text(tr('Written by AI and may be wrong. The quotes below are what was said.'),
                  style: TextStyle(fontSize: 12, color: colors.outline)),
              const SizedBox(height: 4),
              Text(overview.about, style: const TextStyle(height: 1.6)),
            ],
            if (overview.chapters.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(tr('Chapters'), style: heading),
              if (byAi)
                Text(
                    tr('The video has no chapters of its own, so these are shown on the progress bar.'),
                    style: TextStyle(fontSize: 12, color: colors.outline)),
              const SizedBox(height: 4),
              for (final c in overview.chapters)
                row(
                  c.start,
                  c.summary.isEmpty
                      ? Text(c.title, style: const TextStyle(height: 1.5))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                              Text(c.title,
                                  style: const TextStyle(height: 1.5, fontWeight: FontWeight.w600)),
                              Text(c.summary,
                                  style: TextStyle(height: 1.5, color: colors.onSurfaceVariant)),
                            ]),
                ),
            ],
            if (overview.quotes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(tr('Key quotes'), style: heading),
              Text(tr('Word for word from the subtitles; a tap plays the moment.'),
                  style: TextStyle(fontSize: 12, color: colors.outline)),
              const SizedBox(height: 4),
              for (final q in overview.quotes)
                row(
                  q.at,
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('“${q.text}”',
                            style: const TextStyle(height: 1.5, fontStyle: FontStyle.italic)),
                        if (q.translation.isNotEmpty)
                          Text(q.translation,
                              style: TextStyle(height: 1.5, color: colors.onSurfaceVariant)),
                        if (!q.found)
                          Text(tr('Not found in the subtitles as quoted: AI may have reworded it.'),
                              style: TextStyle(fontSize: 12, color: colors.error)),
                      ]),
                ),
            ],
          ]),
    );
  }
}
