import 'package:flutter/material.dart';

import 'chip_strip.dart';
import 'haptics.dart';

/// A [SegmentedButton] while every segment fits its label on one line, and
/// text tabs in a [ChipStrip] once they would not: the segments are all as
/// wide as the widest label, so six long labels outgrow a window long
/// before tabs would, and a cut-off or crushed label is never shown.
class FittingSegments<T> extends StatelessWidget {
  const FittingSegments({super.key, required this.values, required this.label, required this.selected, required this.onSelected});
  final List<T> values;
  final String Function(T value) label;
  final T selected;
  final ValueChanged<T> onSelected;

  /// A segment's padding and border beside its label.
  static const _segmentExtra = 34.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final style = Theme.of(context).textTheme.labelLarge;
        final scaler = MediaQuery.textScalerOf(context);
        var widest = 0.0;
        for (final v in values) {
          final painter = TextPainter(text: TextSpan(text: label(v), style: style), textDirection: Directionality.of(context), textScaler: scaler, maxLines: 1)..layout();
          if (painter.width > widest) widest = painter.width;
          painter.dispose();
        }
        if ((widest + _segmentExtra) * values.length <= constraints.maxWidth) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              segments: [for (final v in values) ButtonSegment(value: v, label: Text(label(v), maxLines: 1, softWrap: false))],
              selected: {selected},
              onSelectionChanged: (value) {
                Haptics.select();
                onSelected(value.first);
              },
            ),
          );
        }
        return ChipStrip(
          tabs: true,
          choices: [for (final v in values) (label: label(v), icon: null)],
          selected: values.indexOf(selected),
          onSelected: (i) => onSelected(values[i]),
        );
      });
}
