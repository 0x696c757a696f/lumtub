import 'dart:async';

import 'package:flutter/material.dart';

import 'key_scroll.dart';

/// 下拉刷新 around a page, with touch or a touchpad, and the same refresh
/// for a second press of the page's navigation button or F5. The mouse
/// wheel only scrolls, as it does elsewhere on the desktop.
class PullToRefresh extends StatefulWidget {
  const PullToRefresh({super.key, required this.enabled, required this.onRefresh, required this.child});

  /// Off on pages with nothing to load again; the page keeps its state
  /// either way.
  final bool enabled;
  final Future<void> Function() onRefresh;
  final Widget child;

  static final _shown = <_PullToRefreshState>[];

  /// Scrolls the page shown to its top; already there, loads it again
  /// when [refresh] allows. False when no page is shown.
  static bool topOrRefresh({required bool refresh}) {
    final page = _shown.lastOrNull;
    if (page == null) return false;
    final position = page._position();
    if (position != null && position.pixels > position.minScrollExtent + 1) {
      KeyScroll.toEnd(false, of: position);
      return true;
    }
    if (refresh) page.refresh();
    return true;
  }

  /// Loads the page shown again with the spinner showing; false when it
  /// has nothing to load.
  static bool refresh() {
    final page = _shown.lastOrNull;
    if (page == null || !page.widget.enabled) return false;
    page.refresh();
    return true;
  }

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh> {
  final _indicator = GlobalKey<RefreshIndicatorState>();
  Future<void>? _running;

  @override
  void initState() {
    super.initState();
    PullToRefresh._shown.add(this);
  }

  @override
  void dispose() {
    PullToRefresh._shown.remove(this);
    super.dispose();
  }

  void refresh() {
    if (!widget.enabled || _running != null) return;
    final position = _position();
    if (position != null && position.pixels > position.minScrollExtent) position.jumpTo(position.minScrollExtent);
    unawaited(_indicator.currentState?.show());
  }

  Future<void> _refresh() {
    return _running ??= widget.onRefresh().whenComplete(() => _running = null);
  }

  /// The page's main list: the tallest vertical one in it.
  ScrollPosition? _position() {
    if (!mounted) return null;
    ScrollPosition? found;
    void visit(Element element) {
      if (element case StatefulElement(state: final ScrollableState scrollable)) {
        final position = scrollable.position;
        if (position.axis == Axis.vertical && position.hasViewportDimension && (found == null || position.viewportDimension > found!.viewportDimension)) found = position;
      }
      element.visitChildren(visit);
    }
    context.visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        key: _indicator,
        onRefresh: _refresh,
        notificationPredicate: (notification) => widget.enabled && notification.depth == 0 && notification.metrics.axis == Axis.vertical,
        child: widget.child,
      );
}
