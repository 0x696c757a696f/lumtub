// Settings widgets adapted from PiliNara (lib/pages/setting/widgets/).
//
// PiliNara: https://github.com/Starfallan/PiliNara
// Copyright (C) PiliNara contributors.
// Adapted for YTPlus under the GNU General Public License, version 3 or
// later. Changes: values are passed in and reported through callbacks
// instead of being read from and written to PiliNara's storage, and the
// GetX and SmartDialog dependencies are removed.

import 'package:flutter/material.dart';

TextStyle _titleStyle(ThemeData theme) => theme.textTheme.titleMedium!;
TextStyle _subtitleStyle(ThemeData theme) => theme.textTheme.labelMedium!.copyWith(color: theme.colorScheme.outline);

/// A plain settings row; tapping it usually opens a dialog. From PiliNara's
/// `NormalItem`.
class NormalItem extends StatelessWidget {
  const NormalItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      leading: leading,
      title: Text(title, style: _titleStyle(theme)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: _subtitleStyle(theme)),
      trailing: trailing,
    );
  }
}

/// A row with a switch; the whole row toggles it. From PiliNara's
/// `SetSwitchItem`.
class SwitchItem extends StatelessWidget {
  const SwitchItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      enabled: enabled,
      onTap: () => onChanged(!value),
      leading: leading,
      title: Text(title, style: _titleStyle(theme)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: _subtitleStyle(theme)),
      trailing: Transform.scale(
        scale: 0.8,
        alignment: Alignment.centerRight,
        child: Switch(value: value, onChanged: enabled ? onChanged : null),
      ),
    );
  }
}

/// A single-choice list in a dialog; returns the chosen value. From
/// PiliNara's `SelectDialog`.
class SelectDialog<T> extends StatelessWidget {
  const SelectDialog({super.key, this.value, required this.values, required this.title, this.subtitleBuilder});

  final T? value;
  final String title;
  final List<(T, String)> values;
  final Widget? Function(BuildContext context, int index)? subtitleBuilder;

  @override
  Widget build(BuildContext context) {
    final titleMedium = Theme.of(context).textTheme.titleMedium!;
    return AlertDialog(
      clipBehavior: Clip.hardEdge,
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          child: RadioGroup<T>(
            onChanged: (v) => Navigator.of(context).pop(v ?? value),
            groupValue: value,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(values.length, (index) {
                final item = values[index];
                return RadioListTile<T>(
                  dense: true,
                  value: item.$1,
                  title: Text(item.$2, style: titleMedium),
                  subtitle: subtitleBuilder?.call(context, index),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// A slider in a dialog; returns the value when confirmed. From PiliNara's
/// `SliderDialog`.
class SliderDialog extends StatefulWidget {
  const SliderDialog({
    super.key,
    required this.value,
    required this.title,
    required this.min,
    required this.max,
    this.divisions,
    this.suffix = '',
    this.precise = 1,
  });

  final double value;
  final String title;
  final double min;
  final double max;
  final int? divisions;
  final String suffix;
  final int precise;

  @override
  State<SliderDialog> createState() => _SliderDialogState();
}

class _SliderDialogState extends State<SliderDialog> {
  late double _tempValue = widget.value.clamp(widget.min, widget.max);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        contentPadding: const EdgeInsets.only(top: 20, left: 8, right: 8, bottom: 8),
        content: SizedBox(
          height: 40,
          child: Slider(
            value: _tempValue,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            label: '${_tempValue.toStringAsFixed(widget.precise)}${widget.suffix}',
            onChanged: (value) => setState(() => _tempValue = double.parse(value.toStringAsFixed(widget.precise))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: Text('取消', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ),
          TextButton(onPressed: () => Navigator.pop(context, _tempValue), child: const Text('确定')),
        ],
      );
}

/// Opens a [SelectDialog] and reports a changed choice.
Future<void> pickFromDialog<T>(BuildContext context, {required String title, required T value, required List<(T, String)> values, required ValueChanged<T> onSelected}) async {
  final result = await showDialog<T>(context: context, builder: (context) => SelectDialog<T>(title: title, value: value, values: values));
  if (result != null && result != value) onSelected(result);
}

/// Opens a [SliderDialog] and reports a changed value.
Future<void> pickWithSlider(
  BuildContext context, {
  required String title,
  required double value,
  required double min,
  required double max,
  int? divisions,
  String suffix = '',
  int precise = 0,
  required ValueChanged<double> onSelected,
}) async {
  final result = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(title: title, value: value, min: min, max: max, divisions: divisions, suffix: suffix, precise: precise),
  );
  if (result != null && result != value) onSelected(result);
}
