import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../search_options.dart' show SearchDuration;
import 'app_icons.dart';
import 'common.dart';
import 'theme.dart';

/// What a [SortMenu] entry does besides picking an order.
enum _Extra { reverse, arrange }

/// A button naming the order a list is in, with a menu of the others; it
/// can also turn the list around and open a dialog to drag it into order.
class SortMenu<T extends Enum> extends StatelessWidget {
  const SortMenu({
    super.key,
    required this.values,
    required this.value,
    required this.labelOf,
    required this.onSelected,
    this.reversed,
    this.onReversed,
    this.onArrange,
    this.tooltip,
    this.compact = false,
  });

  final List<T> values;
  final T value;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;
  /// Whether the list is shown last to first; with [onReversed], the menu
  /// offers 倒序.
  final bool? reversed;
  final ValueChanged<bool>? onReversed;
  /// Opens the dialog that drags the list into the user's own order.
  final VoidCallback? onArrange;
  final String? tooltip;
  /// Only the icon, for a crowded row.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final back = reversed ?? false;
    final icon = Icon(back ? AppIcons.sortDescending : AppIcons.sortAscending, size: 18);
    final label = back ? tr('{0}, reversed', [labelOf(value)]) : labelOf(value);
    return PopupMenuButton<Object>(
      tooltip: tooltip ?? tr('Sort'),
      onSelected: (picked) {
        switch (picked) {
          case _Extra.reverse:
            onReversed?.call(!back);
          case _Extra.arrange:
            onArrange?.call();
          case final T order:
            if (order != value) onSelected(order);
        }
      },
      itemBuilder: (context) => [
        for (final order in values) CheckedPopupMenuItem<Object>(value: order, checked: order == value, child: Text(labelOf(order))),
        if (onReversed != null || onArrange != null) const PopupMenuDivider(),
        if (onReversed != null) CheckedPopupMenuItem<Object>(value: _Extra.reverse, checked: back, child: Text(tr('Reverse order'))),
        if (onArrange != null)
          PopupMenuItem<Object>(
            value: _Extra.arrange,
            child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(AppIcons.dotsSixVertical), title: Text(tr('Arrange by dragging…'), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ),
      ],
      child: compact
          ? Padding(padding: const EdgeInsets.all(8), child: icon)
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                icon,
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
    );
  }
}

/// A dialog listing [items] to drag into order; it answers the new order,
/// or null when cancelled.
Future<List<T>?> showArrangeDialog<T extends Object>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T item) labelOf,
  String Function(T item)? detailOf,
}) =>
    showDialog<List<T>>(context: context, builder: (_) => _ArrangeDialog<T>(title: title, items: items, labelOf: labelOf, detailOf: detailOf));

class _ArrangeDialog<T extends Object> extends StatefulWidget {
  const _ArrangeDialog({required this.title, required this.items, required this.labelOf, this.detailOf});
  final String title;
  final List<T> items;
  final String Function(T item) labelOf;
  final String Function(T item)? detailOf;

  @override
  State<_ArrangeDialog<T>> createState() => _ArrangeDialogState<T>();
}

class _ArrangeDialogState<T extends Object> extends State<_ArrangeDialog<T>> {
  late final _items = [...widget.items];

  void _move(int from, int to) => setState(() => _items.insert(to, _items.removeAt(from)));

  @override
  Widget build(BuildContext context) {
    final detailOf = widget.detailOf;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: dialogWidth(context, 460),
        height: 480,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Drag to reorder, pin to move to the top.'), style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 8),
          Expanded(child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: _items.length,
            onReorderItem: _move,
            itemBuilder: (context, i) {
              final item = _items[i];
              return ListTile(
                key: ObjectKey(item),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.all(4), child: Icon(AppIcons.dotsSixVertical))),
                title: Text(widget.labelOf(item), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: detailOf == null ? null : Text(detailOf(item), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(tooltip: tr('Move to top'), icon: Icon(AppIcons.alignTop), onPressed: i == 0 ? null : () => _move(i, 0)),
              );
            },
          )),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, _items), child: Text(tr('Save'))),
      ],
    );
  }
}

/// A button naming the length of video a list shows, with a menu of the
/// others, as YouTube's search filter has them.
class LengthMenu extends StatelessWidget {
  const LengthMenu({super.key, required this.value, required this.onSelected});

  final SearchDuration value;
  final ValueChanged<SearchDuration> onSelected;

  @override
  Widget build(BuildContext context) {
    final on = value != SearchDuration.any;
    final color = on ? context.colors.primary : context.colors.onSurface;
    return PopupMenuButton<SearchDuration>(
      tooltip: tr('Duration'),
      onSelected: (picked) {
        if (picked != value) onSelected(picked);
      },
      itemBuilder: (context) => [
        for (final length in SearchDuration.values) CheckedPopupMenuItem(value: length, checked: length == value, child: Text(length.label)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(AppIcons.timer, size: 18, color: color),
          const SizedBox(width: 6),
          Text(value.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
