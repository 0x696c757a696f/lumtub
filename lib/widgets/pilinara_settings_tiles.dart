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

class PiliNaraSettingSlider extends StatelessWidget {
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
  final String description;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 9, 18, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Text(title), const Spacer(), Text(description, style: const TextStyle(color: Colors.white54))]),
            Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ],
        ),
      );
}
