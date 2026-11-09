import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../player_settings.dart';
import 'pages/settings_subpages.dart' show openSubtitleSettings;
import 'player_panel.dart';
import 'subtitle_style.dart';
import 'app_icons.dart';

/// The subtitle look as a side panel over the player, so each change shows
/// on the video while it is made: sliders preview as they move and save
/// when let go, colours and switches apply on tap. Languages and the rest
/// stay on the 字幕设置 page.
Future<void> showSubtitleStylePanel(BuildContext context, AppController controller) => showPlayerPanel(
      context,
      title: tr('Subtitle style'),
      width: 420,
      actions: [
        Builder(
          builder: (inner) => TextButton.icon(
            onPressed: () {
              Navigator.of(inner).pop();
              openSubtitleSettings(context, controller);
            },
            icon: Icon(AppIcons.slidersHorizontal, size: 18),
            label: Text(tr('All subtitle settings')),
          ),
        ),
      ],
      builder: (context) => _StylePanel(controller: controller),
    );

class _StylePanel extends StatefulWidget {
  const _StylePanel({required this.controller});
  final AppController controller;

  @override
  State<_StylePanel> createState() => _StylePanelState();
}

class _StylePanelState extends State<_StylePanel> {
  bool _second = false;

  AppController get _controller => widget.controller;

  void _preview(PlayerSettings next) => _controller.previewSettings(next);

  void _save(PlayerSettings next) => _controller.saveSettings(next);

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _controller, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final s = _controller.settings;
    final colors = Theme.of(context).colorScheme;
    // mpv draws both subtitles in the first one's style.
    final second = _second && !s.libassSubtitles;
    final font = second ? s.secondaryFont : s.subtitleFont;
    final scale = second ? s.secondaryScale : s.subtitleScale;
    final color = second ? s.secondaryColor : s.subtitleColor;
    final opacity = second ? s.secondaryOpacity : s.subtitleOpacity;
    PlayerSettings look(PlayerSettings from, {String? font, double? scale, int? color, double? opacity}) => second
        ? from.copyWith(secondaryFont: font, secondaryScale: scale, secondaryColor: color, secondaryOpacity: opacity)
        : from.copyWith(subtitleFont: font, subtitleScale: scale, subtitleColor: color, subtitleOpacity: opacity);

    Widget label(String text, [String? value]) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(child: Text(text, style: Theme.of(context).textTheme.titleSmall)),
            if (value != null) Text(value, style: TextStyle(color: colors.outline)),
          ]),
        );

    Widget slider({required double value, required double min, required double max, required int divisions, required PlayerSettings Function(double) apply}) => Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: (v) => _preview(apply(v)),
          onChangeEnd: (v) => _save(apply(v)),
        );

    return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(tr('First subtitle'))),
            ButtonSegment(value: true, label: Text(tr('Second subtitle')), enabled: !s.libassSubtitles),
          ],
          selected: {second},
          onSelectionChanged: (v) => setState(() => _second = v.first),
        ),
      ),
      if (s.libassSubtitles)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(tr("While mpv draws subtitles, the second subtitle uses the first one's style."), style: TextStyle(fontSize: 12, color: colors.outline)),
        ),
      ListTile(
        title: Text(tr('Font')),
        trailing: Text(subtitleFontLabel(font), style: TextStyle(color: colors.primary)),
        onTap: () => pickSubtitleFont(context, font, (v) => _save(look(_controller.settings, font: v))),
      ),
      label(tr('Size'), '${scale.toStringAsFixed(1)}×'),
      slider(value: scale, min: 0.5, max: 3, divisions: 25, apply: (v) => look(_controller.settings, scale: (v * 10).round() / 10)),
      label(tr('Color'), subtitleColorLabel(color)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in subtitleColors)
            Tooltip(
              message: subtitleColorLabel(c),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: c == color ? null : () => _save(look(_controller.settings, color: c)),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Color(0xFF000000 | c),
                    shape: BoxShape.circle,
                    border: Border.all(color: c == color ? colors.primary : colors.outlineVariant, width: c == color ? 3 : 1),
                  ),
                ),
              ),
            ),
          ActionChip(
            label: Text(tr('Custom')),
            onPressed: () => pickSubtitleColor(context, color, (v) => _save(look(_controller.settings, color: v))),
          ),
        ]),
      ),
      label(tr('Opacity'), '${(opacity * 100).round()}%'),
      slider(value: opacity, min: 0.1, max: 1, divisions: 18, apply: (v) => look(_controller.settings, opacity: (v * 20).round() / 20)),
      const Divider(height: 24),
      label(tr('Subtitle position'), '${s.subtitlePosition}%'),
      slider(value: s.subtitlePosition.toDouble(), min: 0, max: 100, divisions: 100, apply: (v) => _controller.settings.copyWith(subtitlePosition: v.round())),
      label(tr('Outline thickness'), s.subtitleBorder.toStringAsFixed(1)),
      slider(value: s.subtitleBorder, min: 0, max: 8, divisions: 16, apply: (v) => _controller.settings.copyWith(subtitleBorder: v)),
      SwitchListTile(
        title: Text(tr('Background box')),
        value: s.subtitleBackground,
        onChanged: (v) => _save(_controller.settings.copyWith(subtitleBackground: v)),
      ),
      SwitchListTile(
        title: Text(tr('Bold')),
        value: s.subtitleBold,
        onChanged: (v) => _save(_controller.settings.copyWith(subtitleBold: v)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: OutlinedButton.icon(
          onPressed: () => _save(_controller.settings.withDefaultSubtitleStyle()),
          icon: Icon(AppIcons.arrowCounterClockwise, size: 18),
          label: Text(tr('Restore default style')),
        ),
      ),
    ]);
  }
}
