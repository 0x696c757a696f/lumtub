import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../danmaku.dart';
import '../l10n/l10n.dart';
import 'player_panel.dart';

/// 弹幕 on or off and how they look, as a side panel over the player, so
/// each change shows on the picture while it is made.
Future<void> showDanmakuPanel(BuildContext context, AppController controller) => showPlayerPanel(
      context,
      title: tr('弹幕'),
      width: 380,
      builder: (context) => DanmakuPanel(controller: controller),
    );

class DanmakuPanel extends StatefulWidget {
  const DanmakuPanel({super.key, required this.controller});
  final AppController controller;

  @override
  State<DanmakuPanel> createState() => _DanmakuPanelState();
}

class _DanmakuPanelState extends State<DanmakuPanel> {
  /// What a slider shows while it moves; saved when it is let go.
  DanmakuSettings? _moving;

  AppController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _controller, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final saved = _controller.preferences.danmaku;
    final s = _moving ?? saved;
    final colors = Theme.of(context).colorScheme;
    void save(DanmakuSettings next) {
      setState(() => _moving = null);
      _controller.setDanmaku(next);
    }

    Widget label(String text, String value) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(child: Text(text, style: Theme.of(context).textTheme.titleSmall)),
            Text(value, style: TextStyle(color: colors.outline)),
          ]),
        );
    Widget slider(double value, double min, double max, int divisions, DanmakuSettings Function(double) apply) => Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: s.enabled ? (v) => setState(() => _moving = apply(v)) : null,
          onChangeEnd: s.enabled ? (v) => save(apply(v)) : null,
        );

    return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
      SwitchListTile(
        title: Text(tr('显示弹幕')),
        subtitle: Text(tr('直播聊天和聊天回放从画面上飘过')),
        value: s.enabled,
        onChanged: (on) => save(s.copyWith(enabled: on)),
      ),
      label(tr('不透明度'), '${(s.opacity * 100).round()}%'),
      slider(s.opacity, 0.2, 1, 16, (v) => s.copyWith(opacity: v)),
      label(tr('字号'), s.size.round().toString()),
      slider(s.size, 24, 72, 24, (v) => s.copyWith(size: v.roundToDouble())),
      label(tr('飘过用时'), tr('{0} 秒', [s.seconds.round()])),
      slider(s.seconds, 4, 20, 16, (v) => s.copyWith(seconds: v.roundToDouble())),
      label(tr('显示区域'), ''),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: SegmentedButton<double>(
          segments: [
            ButtonSegment(value: 0.25, label: Text(tr('上 1/4'))),
            ButtonSegment(value: 0.5, label: Text(tr('上半屏'))),
            ButtonSegment(value: 1.0, label: Text(tr('全屏'))),
          ],
          selected: {DanmakuSettings.areas.reduce((a, b) => (a - s.area).abs() <= (b - s.area).abs() ? a : b)},
          onSelectionChanged: s.enabled ? (v) => save(s.copyWith(area: v.first)) : null,
        ),
      ),
      SwitchListTile(
        title: Text(tr('显示超级留言和会员消息')),
        value: s.paid,
        onChanged: s.enabled ? (on) => save(s.copyWith(paid: on)) : null,
      ),
    ]);
  }
}
