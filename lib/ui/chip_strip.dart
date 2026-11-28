import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'haptics.dart';
import 'motion.dart';

typedef StripChoice = ({String label, IconData? icon});

/// Choices in one line that scrolls sideways, as chips or as underlined
/// text tabs. When they do not all fit, the edges fade, the wheel and a
/// drag scroll them, a Show all button lists every one, and the selected
/// one is kept in view.
class ChipStrip extends StatefulWidget {
  const ChipStrip({
    super.key,
    required this.choices,
    required this.selected,
    required this.onSelected,
    this.title,
    this.onLongPress,
    this.trailing = const [],
    this.compact = false,
    this.tabs = false,
  });

  final List<StripChoice> choices;
  final int selected;
  final ValueChanged<int> onSelected;

  /// The heading of the Show all sheet on a phone.
  final String? title;

  /// A long press or right click on a chip.
  final void Function(int index)? onLongPress;

  /// Placed after the row; they never scroll away.
  final List<Widget> trailing;
  final bool compact;
  final bool tabs;

  @override
  State<ChipStrip> createState() => _ChipStripState();
}

class _ChipStripState extends State<ChipStrip> {
  static const _fade = 32.0;

  final _scroll = ScrollController();
  final _menu = MenuController();
  final _keys = <GlobalKey>[];
  bool _overflow = false;
  bool _userMoved = false;
  double? _extent;
  double? _viewport;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centre(animate: false));
  }

  @override
  void didUpdateWidget(ChipStrip old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected || old.choices.length != widget.choices.length) {
      _userMoved = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _centre(animate: true));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the row, and only the row, so the selected chip is in the middle
  /// or as near as the ends allow.
  void _centre({required bool animate}) {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions || widget.selected < 0 || widget.selected >= _keys.length) return;
    final chip = _keys[widget.selected].currentContext?.findRenderObject();
    final viewport = position.context.notificationContext?.findRenderObject();
    if (chip is! RenderBox || viewport is! RenderBox || !chip.attached || !viewport.attached) return;
    var from = chip.localToGlobal(Offset.zero, ancestor: viewport).dx;
    if (Directionality.of(context) == TextDirection.rtl) from = viewport.size.width - from - chip.size.width;
    final target = (position.pixels + from + chip.size.width / 2 - viewport.size.width / 2).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1) return;
    if (animate) {
      unawaited(Motion.scrollTo(_scroll, target, duration: Motion.of(Ease.move)));
    } else {
      _scroll.jumpTo(target);
    }
  }

  void _metricsChanged(ScrollMetrics metrics) {
    // Scrolling itself also notifies: only a change of room matters here.
    final settled = _extent == metrics.maxScrollExtent && _viewport == metrics.viewportDimension;
    _extent = metrics.maxScrollExtent;
    _viewport = metrics.viewportDimension;
    if (settled) return;
    // Sent after the frame, so the row may still be changed here.
    if (!_userMoved) _centre(animate: false);
    setState(() => _overflow = metrics.maxScrollExtent > 0);
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final position = _scroll.position;
    final delta = event.scrollDelta.dx != 0 ? event.scrollDelta.dx : event.scrollDelta.dy;
    final target = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _userMoved = true;
      if (_scroll.hasClients) _scroll.jumpTo(target);
    });
  }

  void _pick(int index) {
    if (index != widget.selected) Haptics.select();
    widget.onSelected(index);
  }

  Shader _edgeMask(Rect bounds) {
    final position = _scroll.hasClients && _scroll.position.hasContentDimensions ? _scroll.position : null;
    double edge(double extent) => 1 - (extent / _fade).clamp(0.0, 1.0);
    final start = position == null ? 1.0 : edge(position.pixels - position.minScrollExtent);
    final end = position == null ? 1.0 : edge(position.maxScrollExtent - position.pixels);
    final stop = math.min(0.5, _fade / math.max(bounds.width, 1));
    final black = Colors.black;
    return LinearGradient(
      begin: AlignmentDirectional.centerStart,
      end: AlignmentDirectional.centerEnd,
      colors: [black.withValues(alpha: start), black, black, black.withValues(alpha: end)],
      stops: [0, stop, 1 - stop, 1],
    ).createShader(bounds, textDirection: Directionality.of(context));
  }

  Widget _chip(BuildContext context, int i) {
    final choice = widget.choices[i];
    final selected = i == widget.selected;
    if (widget.tabs) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _pick(i),
          child: AnimatedContainer(
            duration: Motion.of(Ease.fade),
            curve: Ease.out,
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 2.5, color: selected ? colors.primary : Colors.transparent))),
            child: Text(
              choice.label,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? colors.onSurface : colors.onSurfaceVariant),
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onLongPress: widget.onLongPress == null ? null : () => widget.onLongPress!(i),
      onSecondaryTap: widget.onLongPress == null ? null : () => widget.onLongPress!(i),
      child: ChoiceChip(
        visualDensity: widget.compact ? VisualDensity.compact : null,
        avatar: choice.icon == null ? null : Icon(choice.icon, size: 18, color: chipForeground(context, selected)),
        label: Text(choice.label, maxLines: 1, softWrap: false),
        showCheckmark: false,
        selected: selected,
        onSelected: (_) => _pick(i),
      ),
    );
  }

  Widget _showAll(BuildContext context) {
    final button = IconButton(
      tooltip: tr('Show all'),
      icon: Icon(AppIcons.caretDown, size: 18),
      onPressed: isPhone(context)
          ? () async {
              final picked = await pickFromSheet<int>(
                context,
                [for (final (i, c) in widget.choices.indexed) (value: i, icon: c.icon, label: c.label, selected: i == widget.selected)],
                title: widget.title,
              );
              if (picked != null) widget.onSelected(picked);
            }
          : () => _menu.isOpen ? _menu.close() : _menu.open(),
    );
    if (isPhone(context)) return button;
    return MenuAnchor(
      controller: _menu,
      style: const MenuStyle(maximumSize: WidgetStatePropertyAll(Size(double.infinity, 420))),
      menuChildren: [
        for (final (i, c) in widget.choices.indexed)
          MenuItemButton(
            leadingIcon: i == widget.selected ? Icon(AppIcons.check, size: 18) : c.icon == null ? null : Icon(c.icon, size: 18),
            onPressed: () => widget.onSelected(i),
            child: Text(c.label),
          ),
      ],
      child: button,
    );
  }

  @override
  Widget build(BuildContext context) {
    while (_keys.length < widget.choices.length) {
      _keys.add(GlobalKey());
    }
    final gap = SizedBox(width: widget.tabs ? 18 : 8);
    final behavior = ScrollConfiguration.of(context);
    final row = ScrollConfiguration(
      behavior: behavior.copyWith(
        scrollbars: false,
        dragDevices: {...behavior.dragDevices, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if ((n is ScrollStartNotification && n.dragDetails != null) || (n is ScrollUpdateNotification && n.dragDetails != null)) _userMoved = true;
          return false;
        },
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) {
            _metricsChanged(n.metrics);
            return false;
          },
          child: Listener(
            onPointerSignal: _wheel,
            child: ListenableBuilder(
              listenable: _scroll,
              builder: (context, child) => ShaderMask(blendMode: BlendMode.dstIn, shaderCallback: _edgeMask, child: child),
              child: SingleChildScrollView(
                key: const PageStorageKey<String>('chips'),
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var i = 0; i < widget.choices.length; i++) ...[
                    KeyedSubtree(key: _keys[i], child: _chip(context, i)),
                    if (i < widget.choices.length - 1) gap,
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    return Row(children: [
      Expanded(child: row),
      if (_overflow) Padding(padding: const EdgeInsetsDirectional.only(start: 4), child: _showAll(context)),
      ...widget.trailing,
    ]);
  }
}
