// The overflow handling follows prism_ui's GroupTabs (FlClash), GPL-3.0.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'motion.dart';

/// One choice in a [ChipStrip].
typedef StripChoice = ({String label, IconData? icon});

/// A row of choice chips that stays one line however many there are. When
/// they outgrow the row it scrolls (by touch, a mouse drag or the wheel),
/// fades out at the edge with more past it, keeps the selected chip in
/// view, and gains a button listing every choice, so the long tail is
/// one tap away instead of pushing the page down line by line.
class ChipStrip extends StatefulWidget {
  const ChipStrip({super.key, required this.choices, required this.selected, required this.onSelected, this.title, this.onLongPress, this.trailing = const [], this.compact = false, this.tabs = false});
  final List<StripChoice> choices;
  final int selected;
  final ValueChanged<int> onSelected;

  /// What the list of every choice is headed with on a phone.
  final String? title;

  /// For a choice the user may remove, as custom topics.
  final void Function(int index)? onLongPress;

  /// Buttons after the row that never scroll away, as Add and Manage.
  final List<Widget> trailing;
  final bool compact;

  /// Drawn as text tabs underlined when selected, for a level above chips.
  final bool tabs;

  @override
  State<ChipStrip> createState() => _ChipStripState();
}

class _ChipStripState extends State<ChipStrip> {
  static const _fadeExtent = 32.0;
  final _scroll = ScrollController();
  final _hasMore = ValueNotifier(false);
  final _fade = ValueNotifier((start: 0.0, end: 0.0));
  final _menu = MenuController();
  final _contentKey = GlobalKey();
  (double, double)? _size;

  /// Whether the user scrolled the row since the selection changed.
  bool _moved = false;
  List<GlobalKey> _keys = [];

  @override
  void initState() {
    super.initState();
    _keys = [for (final _ in widget.choices) GlobalKey()];
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(jump: true));
  }

  @override
  void didUpdateWidget(ChipStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.choices.length != widget.choices.length) _keys = [for (final _ in widget.choices) GlobalKey()];
    if (oldWidget.selected != widget.selected || oldWidget.choices.length != widget.choices.length) {
      _moved = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _hasMore.dispose();
    _fade.dispose();
    super.dispose();
  }

  /// Brings the selected chip to the middle of the row, or as near as the
  /// row's ends allow.
  void _reveal({bool jump = false}) {
    if (!mounted || !_scroll.hasClients) return;
    final index = widget.selected;
    if (index < 0 || index >= _keys.length) return;
    final chip = _keys[index].currentContext?.findRenderObject();
    final content = _contentKey.currentContext?.findRenderObject();
    if (chip is! RenderBox || content is! RenderBox || !chip.attached) return;
    // Only this row moves: Scrollable.ensureVisible would scroll the page too.
    final position = _scroll.position;
    final start = chip.localToGlobal(Offset.zero, ancestor: content).dx;
    final target = (start + chip.size.width / 2 - position.viewportDimension / 2).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1) return;
    final duration = jump ? Duration.zero : Motion.of(Ease.move);
    duration == Duration.zero ? position.jumpTo(target) : position.animateTo(target, duration: duration, curve: Ease.curve);
  }

  bool _onMetrics(ScrollMetrics metrics) {
    if (metrics.axis != Axis.horizontal) return false;
    _fade.value = (
      start: (metrics.extentBefore / _fadeExtent).clamp(0.0, 1.0),
      end: (metrics.extentAfter / _fadeExtent).clamp(0.0, 1.0),
    );
    _hasMore.value = metrics.maxScrollExtent > 0;
    // The row settles over a few frames (the Show all button, fonts, the
    // page around it): until the user moves it, keep the selection centred.
    final size = (metrics.viewportDimension, metrics.maxScrollExtent);
    if (size != _size) {
      _size = size;
      if (!_moved) WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(jump: true));
    }
    return false;
  }

  /// A mouse wheel turned over the row scrolls it sideways while it can
  /// go that way; at either end the page scrolls instead.
  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final delta = event.scrollDelta.dx != 0 ? event.scrollDelta.dx : event.scrollDelta.dy;
    final position = _scroll.position;
    final target = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _moved = true;
      position.jumpTo(target);
    });
  }

  Shader _edges(Rect bounds, ({double start, double end}) fade) {
    final stop = math.min(0.5, _fadeExtent / math.max(1, bounds.width));
    return LinearGradient(
      begin: AlignmentDirectional.centerStart,
      end: AlignmentDirectional.centerEnd,
      colors: [Colors.black.withValues(alpha: 1 - fade.start), Colors.black, Colors.black, Colors.black.withValues(alpha: 1 - fade.end)],
      stops: [0, stop, 1 - stop, 1],
    ).createShader(bounds, textDirection: Directionality.of(context));
  }

  Future<void> _pickAll() async {
    if (isPhone(context)) {
      final picked = await pickFromSheet<int>(context, [
        for (final (i, c) in widget.choices.indexed) (value: i, icon: c.icon, label: c.label, selected: i == widget.selected),
      ], title: widget.title);
      if (picked != null) widget.onSelected(picked);
    } else {
      _menu.isOpen ? _menu.close() : _menu.open();
    }
  }

  Widget _chip(int i) {
    final choice = widget.choices[i];
    final selected = i == widget.selected;
    if (widget.tabs) {
      final scheme = Theme.of(context).colorScheme;
      return KeyedSubtree(
        key: _keys[i],
        child: InkWell(
          onTap: () => widget.onSelected(i),
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: Motion.of(Ease.fade),
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: selected ? scheme.primary : Colors.transparent, width: 2.5))),
            child: Text(choice.label, maxLines: 1, style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
            )),
          ),
        ),
      );
    }
    final chip = ChoiceChip(
      avatar: choice.icon == null ? null : Icon(choice.icon, size: 18, color: chipForeground(context, selected)),
      label: Text(choice.label, maxLines: 1),
      showCheckmark: false,
      visualDensity: widget.compact ? VisualDensity.compact : null,
      selected: selected,
      onSelected: (_) => widget.onSelected(i),
    );
    final long = widget.onLongPress;
    return KeyedSubtree(
      key: _keys[i],
      child: long == null ? chip : GestureDetector(onLongPress: () => long(i), onSecondaryTap: () => long(i), child: chip),
    );
  }

  Widget _more() => MenuAnchor(
        controller: _menu,
        style: const MenuStyle(maximumSize: WidgetStatePropertyAll(Size(double.infinity, 420))),
        menuChildren: [
          for (final (i, c) in widget.choices.indexed)
            MenuItemButton(
              leadingIcon: Icon(i == widget.selected ? AppIcons.check : c.icon, size: 18),
              onPressed: () => widget.onSelected(i),
              child: Text(c.label),
            ),
        ],
        child: IconButton(tooltip: tr('Show all'), icon: Icon(AppIcons.caretDown, size: 18), onPressed: _pickAll),
      );

  @override
  Widget build(BuildContext context) {
    final row = ScrollConfiguration(
      // A mouse can drag the row too, as a finger does.
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, dragDevices: {...ScrollConfiguration.of(context).dragDevices, PointerDeviceKind.mouse, PointerDeviceKind.trackpad}),
      child: Listener(
        onPointerSignal: _onWheel,
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) => _onMetrics(n.metrics),
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (n) {
              if (n.dragDetails != null) _moved = true;
              return _onMetrics(n.metrics);
            },
            child: ValueListenableBuilder(
              valueListenable: _fade,
              builder: (context, fade, child) => fade.start == 0 && fade.end == 0
                  ? child!
                  : ShaderMask(blendMode: BlendMode.dstIn, shaderCallback: (bounds) => _edges(bounds, fade), child: child),
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: Row(key: _contentKey, children: [
                  for (var i = 0; i < widget.choices.length; i++)
                    Padding(padding: EdgeInsetsDirectional.only(end: i == widget.choices.length - 1 ? 0 : widget.tabs ? 18 : 8), child: _chip(i)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    return Row(children: [
      Flexible(child: row),
      ValueListenableBuilder(
        valueListenable: _hasMore,
        builder: (context, more, _) => more ? Padding(padding: const EdgeInsetsDirectional.only(start: 4), child: _more()) : const SizedBox.shrink(),
      ),
      ...widget.trailing,
    ]);
  }
}
