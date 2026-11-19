import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Scrolling a page from the keyboard, as a browser does: a page at a
/// time or to either end, eased. A key held down carries on from where the
/// last press was heading instead of starting over, so it does not stutter.
/// The list moved is the one under the mouse when it can scroll, as the
/// wheel would move, unless the keyboard moved the focus since the mouse
/// last moved; then it is the list the focus is in. Anywhere else, over the
/// navigation, the title bar or a gap between cards, with no focus in a
/// list, it is the page's main list, as a browser turns its page. A focus
/// the page left behind is brought to the first item in sight, so the
/// arrow keys go on from what is shown.
abstract final class KeyScroll {
  /// The part of the view one page moves.
  static const page = 0.85;
  static const duration = Duration(milliseconds: 180);

  static final _heading = Expando<double>();

  /// Marks the page area, from the app's shell: the lists a key may move
  /// are the ones in it.
  static final area = GlobalKey(debugLabel: 'page area');

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
    return _listAt(at, _pointerView, scrollable: false);
  }

  static ScrollPosition? _listAt(Offset at, int view, {required bool scrollable, RenderObject? within}) {
    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(result, at, view);
    ScrollPosition? first;
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderViewportBase || target.axis != Axis.vertical) continue;
      final offset = target.offset;
      if (offset is! ScrollPosition || !offset.hasContentDimensions) continue;
      if (within != null && !_inside(target, within)) continue;
      if (_canScroll(offset)) return offset;
      if (!scrollable) first ??= offset;
    }
    return first;
  }

  static bool _canScroll(ScrollPosition position) => position.maxScrollExtent > position.minScrollExtent;

  static bool _inside(RenderObject object, RenderObject ancestor) {
    for (RenderObject? at = object; at != null; at = at.parent) {
      if (identical(at, ancestor)) return true;
    }
    return false;
  }

  /// The vertical list the focus is in, if any.
  static ScrollPosition? _focused() {
    final context = primaryFocus?.context;
    return context == null ? null : Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
  }

  /// The page's main list: the largest one in the page area that can
  /// scroll, found where it shows, so a page on its way out, one kept out
  /// of sight and anything over the page are passed by.
  static ScrollPosition? mainList() {
    final context = area.currentContext;
    final box = context?.findRenderObject();
    if (context == null || box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty) return null;
    final view = View.maybeOf(context)?.viewId;
    if (view == null) return null;
    ScrollPosition? best;
    var bestArea = 0.0;
    for (final x in const [0.5, 0.25, 0.75, 0.1, 0.9]) {
      for (final y in const [0.5, 0.25, 0.75, 0.1, 0.9]) {
        final at = box.localToGlobal(Offset(box.size.width * x, box.size.height * y));
        final position = _listAt(at, view, scrollable: true, within: box);
        if (position == null || identical(position, best)) continue;
        final list = position.context.notificationContext?.findRenderObject();
        final size = list is RenderBox && list.hasSize ? list.size.width * list.size.height : 0.0;
        if (size > bestArea) {
          best = position;
          bestArea = size;
        }
      }
    }
    return best;
  }

  /// The list a key moves: the one under the mouse in the page area that
  /// can scroll or the one the focus is in, whichever moved last; else the
  /// page's main one, unless [main] is false. Null when there is none.
  static ScrollPosition? target({bool main = true}) {
    final focused = _focused();
    final usable = focused != null && _canScroll(focused) ? focused : null;
    if (usable == null || _pointerMoved > _focusMoved) {
      if (_pointed() case final pointed?) return pointed;
    }
    if (usable != null) return usable;
    if (main) {
      if (mainList() case final list?) return list;
    }
    if (focused != null) return focused;
    final context = primaryFocus?.context;
    if (context == null) return null;
    final primary = PrimaryScrollController.maybeOf(context);
    if (primary == null || !primary.hasClients) return null;
    return primary.positions.where((p) => p.axis == Axis.vertical).lastOrNull;
  }

  /// The list under the mouse that can scroll. Over the page area only
  /// one in it counts, so the navigation and the title bar turn the page
  /// itself; over a dialog on top, any in it.
  static ScrollPosition? _pointed() {
    final at = _pointer;
    if (at == null) return null;
    final context = area.currentContext;
    final box = context?.findRenderObject();
    if (context == null || box is! RenderBox || !box.attached) return _listAt(at, _pointerView, scrollable: true);
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    return _listAt(at, _pointerView, scrollable: true, within: onTop ? box : null);
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
  /// [main] lets a key with no list under the mouse or the focus turn the
  /// page's main list.
  static bool byPage(int direction, {bool main = true}) {
    final position = target(main: main);
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
