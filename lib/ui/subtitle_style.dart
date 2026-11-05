import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../player_settings.dart';
import '../widgets/pilinara_settings_tiles.dart';
import 'pages/watch_page.dart' show subtitleViewFor;

/// Font families this system installs, offered before a typed name, each
/// with the name to translate, or null for one shown as it is written.
List<(String, String?)> get subtitleFonts => Platform.isMacOS ? _macFonts : Platform.isLinux ? _linuxFonts : _windowsFonts;

const _macFonts = [
  ('', 'Default'),
  ('PingFang SC', 'PingFang'),
  ('Hiragino Sans GB', 'Hiragino Sans GB'),
  ('Songti SC', 'SimSun'),
  ('Kaiti SC', 'KaiTi'),
  ('PingFang TC', 'PingFang (Traditional)'),
  ('Helvetica Neue', null),
  ('Arial', null),
  ('Verdana', null),
  ('Georgia', null),
  ('Hiragino Sans', null),
  ('Apple SD Gothic Neo', null),
];

const _linuxFonts = [
  ('', 'Default'),
  ('Noto Sans CJK SC', null),
  ('Noto Serif CJK SC', null),
  ('WenQuanYi Micro Hei', 'WenQuanYi Micro Hei'),
  ('Noto Sans CJK TC', null),
  ('Noto Sans', null),
  ('DejaVu Sans', null),
  ('Liberation Sans', null),
  ('Noto Sans CJK JP', null),
  ('Noto Sans CJK KR', null),
];

const _windowsFonts = [
  ('', 'Default'),
  ('Microsoft YaHei', 'Microsoft YaHei'),
  ('DengXian', 'DengXian'),
  ('SimHei', 'Sans-serif (Hei)'),
  ('SimSun', 'SimSun'),
  ('KaiTi', 'KaiTi'),
  ('Microsoft JhengHei', 'Microsoft JhengHei'),
  ('Segoe UI', null),
  ('Arial', null),
  ('Verdana', null),
  ('Georgia', null),
  ('Yu Gothic', null),
  ('Malgun Gothic', null),
];

const subtitleColors = [
  0xFFFFFF, 0xFFE7A8, 0xFFF59D, 0xFFEB3B, 0xFFC107, 0xFF9800, 0xF48FB1,
  0x80DEEA, 0x4FC3F7, 0xA5D6A7, 0x69F0AE, 0xB0BEC5,
];

String subtitleFontLabel(String font) {
  for (final (name, label) in subtitleFonts) {
    if (name == font) return label == null ? name : tr(label);
  }
  return font;
}

String subtitleColorLabel(int color) => '#${color.toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// A preset family, or one typed in.
Future<void> pickSubtitleFont(BuildContext context, String current, ValueChanged<String> onSelected) async {
  const custom = '\u0000custom';
  final known = subtitleFonts.any((f) => f.$1 == current);
  final chosen = await showDialog<String>(
    context: context,
    builder: (context) => SelectDialog<String>(
      title: tr('Font'),
      value: known ? current : custom,
      values: [
        for (final (name, label) in subtitleFonts) (name, label == null ? name : tr(label)),
        (custom, known ? tr('Other font…') : tr('Other font: {0}', [current])),
      ],
    ),
  );
  if (chosen == null || !context.mounted) return;
  if (chosen != custom) {
    if (chosen != current) onSelected(chosen);
    return;
  }
  final typed = await showDialog<String>(
    context: context,
    builder: (context) => TextEditDialog(
      title: tr('Other font'),
      initialText: known ? '' : current,
      hintText: tr('Name of an installed font, such as Noto Sans SC'),
      helper: (text) => Text(
        text.trim().isNotEmpty && PlayerSettings.cleanFont(text).isEmpty ? tr('A font name cannot contain commas, semicolons or quotes') : tr('The default font is used when Windows does not have this one'),
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
      ),
    ),
  );
  if (typed != null) onSelected(PlayerSettings.cleanFont(typed));
}

/// A swatch, or a typed #RRGGBB.
Future<void> pickSubtitleColor(BuildContext context, int current, ValueChanged<int> onSelected) async {
  final chosen = await showDialog<int>(context: context, builder: (context) => _ColorDialog(current: current));
  if (chosen != null && chosen != current) onSelected(chosen);
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.current});
  final int current;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late int _color = widget.current;
  late final _text = TextEditingController(text: subtitleColorLabel(widget.current));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  static int? _parse(String text) {
    final hex = text.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
    return int.parse(hex, radix: 16);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(tr('Color')),
      content: SizedBox(
        width: 300,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final color in subtitleColors)
              Tooltip(
                message: subtitleColorLabel(color),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() {
                    _color = color;
                    _text.text = subtitleColorLabel(color);
                  }),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(0xFF000000 | color),
                      shape: BoxShape.circle,
                      border: Border.all(color: color == _color ? colors.primary : colors.outlineVariant, width: color == _color ? 3 : 1),
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            decoration: InputDecoration(
              isDense: true,
              labelText: tr('Custom color'),
              hintText: '#RRGGBB',
              prefixIcon: Padding(
                padding: const EdgeInsets.all(8),
                child: Container(width: 16, height: 16, decoration: BoxDecoration(color: Color(0xFF000000 | _color), shape: BoxShape.circle, border: Border.all(color: colors.outlineVariant))),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            onChanged: (text) {
              final parsed = _parse(text);
              if (parsed != null) setState(() => _color = parsed);
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: Navigator.of(context).pop, child: Text(tr('Cancel'), style: TextStyle(color: colors.outline))),
        TextButton(onPressed: () => Navigator.pop(context, _color), child: Text(tr('OK'))),
      ],
    );
  }
}

/// Both subtitles over a dark picture, as 字幕设置 has them now.
class SubtitlePreview extends StatelessWidget {
  const SubtitlePreview({super.key, required this.settings});
  final PlayerSettings settings;

  @override
  Widget build(BuildContext context) {
    final view = subtitleViewFor(settings.copyWith(libassSubtitles: false));
    // The player scales subtitles to its size; the preview is about a third
    // of a 1080p picture.
    TextStyle shrink(TextStyle style) => style.copyWith(fontSize: (style.fontSize ?? 32) * 0.45);
    return Container(
      height: 150,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF37474F), Color(0xFF101418)]),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(tr('The second subtitle shows here'), textAlign: TextAlign.center, style: shrink(view.secondaryStyle ?? view.style)),
        const SizedBox(height: 2),
        Text(tr('The first subtitle shows here'), textAlign: TextAlign.center, style: shrink(view.style)),
      ]),
    );
  }
}

/// Opacity as a percentage slider.
Future<void> pickSubtitleOpacity(BuildContext context, double current, ValueChanged<double> onSelected) => pickWithSlider(
      context,
      title: tr('Opacity'),
      value: (current * 100).roundToDouble(),
      min: 10,
      max: 100,
      divisions: 18,
      suffix: '%',
      onSelected: (v) => onSelected(v.round() / 100),
    );
