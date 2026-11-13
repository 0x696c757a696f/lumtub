import 'package:flutter/material.dart';

/// A row of [SegmentedButton] segments that never hides one behind the edge
/// without a way to see it. Every segment is as wide as the widest label, so
/// six long labels can outgrow the window: then, while each segment still
/// gets [minSegment], labels break over two lines to fit; on narrower
/// screens the row scrolls and the selected segment is scrolled into view.
class FittingSegments<T> extends StatefulWidget {
  const FittingSegments({super.key, required this.values, required this.label, required this.selected, required this.onSelected, this.minSegment = 112});
  final List<T> values;
  final String Function(T value) label;
  final T selected;
  final ValueChanged<T> onSelected;
  final double minSegment;

  @override
  State<FittingSegments<T>> createState() => _FittingSegmentsState<T>();
}

class _FittingSegmentsState<T> extends State<FittingSegments<T>> {
  final _selectedKey = GlobalKey();
  T? _shown;

  void _reveal() {
    if (_shown == widget.selected) return;
    _shown = widget.selected;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _selectedKey.currentContext;
      if (context != null && mounted) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 200));
    });
  }

  Widget _button(int lines) => SegmentedButton<T>(
        showSelectedIcon: false,
        segments: [
          for (final v in widget.values)
            ButtonSegment(
              value: v,
              label: Text(widget.label(v), key: v == widget.selected ? _selectedKey : null, maxLines: lines, softWrap: lines > 1, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
            ),
        ],
        selected: {widget.selected},
        onSelectionChanged: (value) => widget.onSelected(value.first),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth / widget.values.length >= widget.minSegment) {
          _shown = null;
          return Align(alignment: AlignmentDirectional.centerStart, child: _button(2));
        }
        _reveal();
        return SingleChildScrollView(scrollDirection: Axis.horizontal, child: _button(1));
      });
}
