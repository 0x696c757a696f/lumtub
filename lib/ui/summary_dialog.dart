import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
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
  String? _error;
  (int, int)? _progress;

  @override
  void initState() {
    super.initState();
    final id = widget.controller.playing?.id;
    _summary = id == null ? null : widget.controller.summaryOf(id);
    if (_summary == null && widget.controller.canSummarize) _run();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
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
      body = Text(tr('AI 总结使用“翻译服务”里设置的 AI 接口（OpenAI、DeepSeek、Ollama 等）。设置好接口和密钥后再试。只会发送视频标题和字幕文字。'), style: TextStyle(color: colors.onSurfaceVariant, height: 1.5));
    } else if (summary != null) {
      body = SingleChildScrollView(
        child: SelectionArea(
          child: LinkedText(summary, style: const TextStyle(height: 1.6), onTime: (time) => controller.player?.seek(time), onLink: openExternal),
        ),
      );
    } else if (_error case final error?) {
      body = ErrorBanner(error, onRetry: _run);
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
        if (summary != null) TextButton(onPressed: () => copyText(context, summary, tr('已复制总结')), child: Text(tr('复制'))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('关闭'))),
      ],
    );
  }
}
