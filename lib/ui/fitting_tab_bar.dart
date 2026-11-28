import 'package:material_ui/material_ui.dart';

/// Text tabs that show every label whole whenever they can: tabs sharing
/// the width when the widest label fits its share, else tabs as wide as
/// their labels with less padding as room runs out, then slightly smaller
/// labels. Only when that still leaves no room do they scroll.
class FittingTabBar extends StatelessWidget {
  const FittingTabBar(
      {super.key, required this.controller, required this.labels, this.onTap, this.height});
  final TabController controller;
  final List<String> labels;
  final ValueChanged<int>? onTap;
  final double? height;

  static const _paddings = [16.0, 12.0, 8.0, 6.0];
  static const _smallest = 0.85;
  static const _size = 14.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final theme = Theme.of(context);
        // The chosen tab's label is the boldest, so every label is measured
        // as if chosen.
        final style = theme.tabBarTheme.labelStyle ?? theme.textTheme.titleSmall;
        final scaler = MediaQuery.textScalerOf(context);
        final widths = [
          for (final label in labels) _width(label, style, scaler, Directionality.of(context)),
        ];
        final room = constraints.maxWidth;
        final widest = widths.fold(0.0, (a, b) => a > b ? a : b);
        Widget bar({required bool scrollable, required double padding, double shrink = 1}) =>
            TabBar(
              controller: controller,
              onTap: onTap,
              isScrollable: scrollable,
              tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
              labelPadding: EdgeInsets.symmetric(horizontal: padding),
              dividerColor: Colors.transparent,
              tabs: [
                for (final label in labels)
                  Tab(
                      height: height,
                      child: Text(label,
                          maxLines: 1,
                          softWrap: false,
                          textScaler: shrink == 1
                              ? null
                              : TextScaler.linear(scaler.scale(_size) / _size * shrink))),
              ],
            );
        if (widest + 2 * _paddings.first <= room / labels.length) {
          return bar(scrollable: false, padding: _paddings.first);
        }
        final total = widths.fold(0.0, (a, b) => a + b);
        for (final padding in _paddings) {
          if (total + 2 * padding * labels.length <= room) {
            return bar(scrollable: true, padding: padding);
          }
        }
        // Then the labels a little smaller, as long as they stay easy to
        // read; past that, they scroll.
        final shrink = (room - 2 * _paddings.last * labels.length) / total;
        if (shrink >= _smallest) {
          return bar(scrollable: true, padding: _paddings.last, shrink: shrink);
        }
        return bar(scrollable: true, padding: _paddings.last);
      });

  static double _width(String text, TextStyle? style, TextScaler scaler, TextDirection direction) {
    final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1)
      ..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }
}
