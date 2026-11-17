import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Scrolling a page from the keyboard, as a browser does: a page at a
/// time or to either end, eased. A key held down carries on from where the
/// last press was heading instead of starting over, so it does not stutter.
/// The list moved is the one under the mouse, as the wheel would move,
/// unless the keyboard moved the focus since the mouse last moved; then it
/// is the list the focus is in. A focus the page left behind is brought
/// to the first item in sight, so the arrow keys go on from what is shown.
abstract final class KeyScroll {
  /// The part of the view one page moves.
  static const page = 0.85;
  static const duration = Duration(milliseconds: 180);

  static final _heading = Expando<double>();

  static Offset? _pointer;
  static int _pointerView = 0;
  static int _pointerMoved = 0;
  static int _focusMoved = 0;
  static int _clock = 0;
  static bool _routed = false;
  static FocusManager? _focusManager;
  static FocusNode? _lastFocus;

  /// Starts following the mouse and the focus, from the app's shell.
  static void watch() {
    if (!_routed) {
      _routed = true;
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    }
    final manager = FocusManager.instance;
    if (!identical(manager, _focusManager)) {
      _focusManager = manager;
      manager.addListener(_onFocus);
    }
  }

  static void _onPointer(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse && event.kind != PointerDeviceKind.trackpad) return;
    if (event is PointerRemovedEvent) {
      _pointer = null;
      return;
    }
    if (event is! PointerHoverEvent && event is! PointerDownEvent && event is! PointerScrollEvent && event is! PointerPanZoomStartEvent) return;
    if (_pointer == event.position && event is PointerHoverEvent) return;
    _pointer = event.position;
    _pointerView = event.viewId;
    _pointerMoved = ++_clock;
  }

  static void _onFocus() {
    final now = FocusManager.instance.primaryFocus;
    if (identical(now, _lastFocus)) return;
    _lastFocus = now;
    _focusMoved = ++_clock;
  }

  /// The innermost vertical list under the mouse that can scroll, else the
  /// innermost one there; null when the mouse is not over the window.
  static ScrollPosition? underPointer() {
    final at = _pointer;
    if (at == null) return null;
    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(result, at, _pointerView);
    ScrollPosition? first;
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderViewportBase || target.axis != Axis.vertical) continue;
      final offset = target.offset;
      if (offset is! ScrollPosition || !offset.hasContentDimensions) continue;
      if (offset.maxScrollExtent > offset.minScrollExtent) return offset;
      first ??= offset;
    }
    return first;
  }

  /// The vertical list the focus is in, if any.
  static ScrollPosition? _focused() {
    final context = primaryFocus?.context;
    return context == null ? null : Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
  }

  /// The list a key moves: the one under the mouse or the one the focus
  /// is in, whichever moved last; else the page's main one. Null when
  /// there is none.
  static ScrollPosition? target() {
    final focused = _focused();
    if (focused == null || _pointerMoved > _focusMoved) {
      if (underPointer() case final pointed?) return pointed;
    }
    if (focused != null) return focused;
    final context = primaryFocus?.context;
    if (context == null) return null;
    final primary = PrimaryScrollController.maybeOf(context);
    if (primary == null || !primary.hasClients) return null;
    return primary.positions.where((p) => p.axis == Axis.vertical).lastOrNull;
  }

  /// When the focus was in [position]'s list and has scrolled out of
  /// sight, it moves to the first item there is room for in sight, so the
  /// arrow keys carry on from what is shown instead of jumping back.
  static void _bringFocus(ScrollPosition position) {
    final focus = primaryFocus;
    final context = focus?.context;
    if (focus == null || context == null || !context.mounted || _focused() != position) return;
    final list = position.context.notificationContext?.findRenderObject();
    if (list is! RenderBox || !list.attached || !list.hasSize) return;
    final view = MatrixUtils.transformRect(list.getTransformTo(null), Offset.zero & list.size);
    bool inSight(Rect rect) => rect.top >= view.top - 1 && rect.bottom <= view.bottom + 1;
    if (inSight(focus.rect)) return;
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    FocusNode? best;
    for (final node in focus.nearestScope?.traversalDescendants ?? const <FocusNode>[]) {
      final at = node.context;
      if (at == null || !node.canRequestFocus || Scrollable.maybeOf(at, axis: Axis.vertical)?.position != position) continue;
      final rect = node.rect;
      if (rect.isEmpty || !inSight(rect)) continue;
      if (best == null) {
        best = node;
        continue;
      }
      final other = best.rect;
      final higher = rect.top < other.top - 1;
      final sameRow = (rect.top - other.top).abs() <= 1;
      if (higher || (sameRow && (rtl ? rect.right > other.right : rect.left < other.left))) best = node;
    }
    best?.requestFocus();
  }

  /// Down (positive) or up a page; false when there is nothing to scroll.
  static bool byPage(int direction) {
    final position = target();
    if (position == null) return false;
    final from = position.isScrollingNotifier.value ? _heading[position] ?? position.pixels : position.pixels;
    _go(position, from + direction * position.viewportDimension * page);
    return true;
  }

  /// Back to the top of the vertical list in [context] (the first one
  /// under it), else of the one it sits in: what pressing a tab or a title
  /// that is already shown does. False when there is no list to scroll.
  static bool toTopAt(BuildContext context) {
    ScrollableState? found;
    void look(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is ScrollableState && (element.state as ScrollableState).position.axis == Axis.vertical) {
        found = element.state as ScrollableState;
        return;
      }
      element.visitChildElements(look);
    }

    context.visitChildElements(look);
    final position = found?.position ?? Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (position == null) return false;
    return toEnd(false, of: position);
  }

  /// To the top, or the bottom of what has loaded so far.
  static bool toEnd(bool bottom, {ScrollPosition? of}) {
    final position = of ?? target();
    if (position == null) return false;
    final to = bottom ? position.maxScrollExtent : position.minScrollExtent;
    // Far away, jump to a page short of it so the lists in between are not
    // all laid out on the way, then ease in.
    final view = position.viewportDimension;
    if ((to - position.pixels).abs() > view * 3 && !Motion.reduced) position.jumpTo(bottom ? to - view : to + view);
    _go(position, to);
    return true;
  }

  static void _go(ScrollPosition position, double to) {
    final clamped = to.clamp(position.minScrollExtent, position.maxScrollExtent);
    void settled() => WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_heading[position] == clamped || Motion.reduced) _bringFocus(position);
        });
    if (Motion.reduced) {
      position.jumpTo(clamped);
      settled();
      return;
    }
    _heading[position] = clamped;
    position.animateTo(clamped, duration: duration, curve: Curves.easeOutCubic).then((_) => settled());
  }
}
