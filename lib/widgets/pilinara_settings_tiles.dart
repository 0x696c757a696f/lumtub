import 'package:flutter/material.dart';

/// Settings controls adapted from PiliNara's settings tiles.
///
/// Copyright (C) PiliNara contributors.
/// Adapted for YTPlus under GPL-3.0-or-later.  YTPlus keeps state and
/// persistence outside these widgets so no PiliNara storage dependency is
/// required.
class PiliNaraSettingSwitch extends StatelessWidget {
  const PiliNaraSettingSwitch({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final switchButton = Transform.scale(
      scale: 0.8,
      alignment: Alignment.centerRight,
      child: Switch(value: value, onChanged: onChanged),
    );
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      title: Text(title, style: theme.textTheme.titleMedium),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
      onTap: () => onChanged(!value),
      trailing: switchButton,
    );
  }
}

class PiliNaraSettingChoice extends StatelessWidget {
  const PiliNaraSettingChoice({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.choices,
    required this.onSelected,
  });

  final String title;
  final String? subtitle;
  final String value;
  final Map<String, String> choices;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: PopupMenuButton<String>(
          tooltip: title,
          onSelected: onSelected,
          itemBuilder: (context) => choices.entries
              .map((entry) => CheckedPopupMenuItem(
                    value: entry.key,
                    checked: entry.key == value,
                    child: Text(entry.value),
                  ))
              .toList(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(choices[value] ?? value, style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      );
}

/// Slider that follows the pointer locally and reports the value once the
/// drag ends, so settings are not saved and applied on every frame.
class PiliNaraSettingSlider extends StatefulWidget {
  const PiliNaraSettingSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.description,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;

  /// Label for a value, shown at the end of the title row.
  final String Function(double value) description;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  State<PiliNaraSettingSlider> createState() => _PiliNaraSettingSliderState();
}

class _PiliNaraSettingSliderState extends State<PiliNaraSettingSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = (_dragging ?? widget.value).clamp(widget.min, widget.max).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 9, 18, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Text(widget.title), const Spacer(), Text(widget.description(value), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))]),
          Slider(
            value: value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: (next) => setState(() => _dragging = next),
            onChangeEnd: (next) {
              setState(() => _dragging = null);
              widget.onChanged(next);
            },
          ),
        ],
      ),
    );
  }
}
