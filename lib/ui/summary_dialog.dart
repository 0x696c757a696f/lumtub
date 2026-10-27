import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../models.dart' show SubtitleKind;
import 'common.dart';
import 'linked_text.dart';
import 'pages/translation_settings_page.dart';
import 'theme.dart';

/// AI 总结 of the video playing. The times in it seek the video.
Future<void> showVideoSummary(BuildContext context, AppController controller) => showDialog<void>(
      context: context,
      builder: (context) => _SummaryDialog(controller: controller),
    );

class _SummaryDialog extends StatefulWidget {
  const _SummaryDialog({required this.controller});
  final AppController controller;

  @override
  State<_SummaryDialog> createState() => _SummaryDialogState();
}

class _SummaryDialogState extends State<_SummaryDialog> {
  String? _summary;

  /// Whether 语音识别 has subtitles for this video already.
  bool get _speechDone => widget.controller.details?.subtitles.any((s) => s.kind == SubtitleKind.speech) ?? false;
  String? _error;
  (int, int)? _progress;

  @override
  void initState() {
    super.initState();
    final id = widget.controller.playing?.id;
    _summary = id == null ? null : widget.controller.summaryOf(id);
    if (_summary == null && widget.controller.canSummarize) _run();
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
      if (mounted) setState(() => _error = '$e');
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

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final colors = context.colors;
    final summary = _summary;
    final Widget body;
    if (!controller.canSummarize) {
      body = Text(tr('AI 总结使用“设置 › 翻译与 AI”里的 AI 接口（OpenAI、DeepSeek、Ollama 等）。设置好接口和密钥后再试。只会发送视频标题和字幕文字。'), style: TextStyle(color: colors.onSurfaceVariant, height: 1.5));
    } else if (summary != null) {
      body = SingleChildScrollView(
        child: SelectionArea(
          child: LinkedText(summary, style: const TextStyle(height: 1.6), onTime: (time) {
            // Out of the way so the moment shows; the summary is kept and
            // opens again at once.
            controller.player?.seek(time);
            Navigator.pop(context);
          }, onLink: openExternal),
        ),
      );
    } else if (_error case final error?) {
      body = ErrorBanner(error, onRetry: _run);
    } else if (controller.speechJob.value != null) {
      body = ValueListenableBuilder(
        valueListenable: controller.speechJob,
        builder: (context, job, _) => Row(children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 14),
          Expanded(child: Text(job == null ? tr('正在读取字幕并总结…') : job.total > 1 ? '${job.stage} ${job.done} / ${job.total}' : job.stage, style: TextStyle(color: colors.onSurfaceVariant))),
        ]),
      );
    } else {
      final progress = _progress;
      body = Row(children: [
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(width: 14),
        Expanded(child: Text(
          progress == null || progress.$1 == 0 ? tr('正在读取字幕并总结…') : progress.$1 < progress.$2 - 1 ? tr('视频较长，正在分段整理：{0} / {1}', [progress.$1, progress.$2 - 1]) : tr('正在汇总…'),
          style: TextStyle(color: colors.onSurfaceVariant),
        )),
      ]);
    }
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.auto_awesome_rounded, color: colors.primary),
        const SizedBox(width: 10),
        Text(tr('AI 总结')),
      ]),
      content: SizedBox(width: 560, child: body),
      actions: [
        if (!controller.canSummarize)
          TextButton(
            onPressed: () async {
              await openTranslationSettings(context, controller);
              if (mounted) setState(() {});
              if (mounted && controller.canSummarize && _summary == null) _run();
            },
            child: Text(tr('设置 AI 接口')),
          ),
        // Without subtitles the summary came from the description only.
        if (controller.canSummarize && !AppController.hasOwnSubtitles(controller.details) && !_speechDone && controller.canRecognizeSpeech && controller.speechJob.value == null && (summary != null || _error != null))
          TextButton.icon(onPressed: _fromSpeech, icon: const Icon(Icons.graphic_eq_rounded, size: 18), label: Text(tr('用语音识别重新总结'))),
        if (summary != null) TextButton(onPressed: () => copyText(context, summary, tr('已复制总结')), child: Text(tr('复制'))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('关闭'))),
      ],
    );
  }
}
