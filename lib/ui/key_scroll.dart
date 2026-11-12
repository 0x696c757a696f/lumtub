import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Scrolling a page from the keyboard, as a browser does: a page at a
/// time or to either end, eased. A key held down carries on from where the
/// last press was heading instead of starting over, so it does not stutter.
abstract final class KeyScroll {
  /// The part of the view one page moves.
  static const page = 0.85;
  static const duration = Duration(milliseconds: 180);

  static final _heading = Expando<double>();

  /// The vertical list the focus is in, else the page's main one; null
  /// when there is none.
  static ScrollPosition? target() {
    final context = primaryFocus?.context;
    if (context == null) return null;
    final own = Scrollable.maybeOf(context, axis: Axis.vertical);
    if (own != null) return own.position;
    final primary = PrimaryScrollController.maybeOf(context);
    if (primary == null || !primary.hasClients) return null;
    return primary.positions.where((p) => p.axis == Axis.vertical).lastOrNull;
  }

  /// Down (positive) or up a page; false when there is nothing to scroll.
  static bool byPage(int direction) {
    final position = target();
    if (position == null) return false;
    final from = position.isScrollingNotifier.value ? _heading[position] ?? position.pixels : position.pixels;
    _go(position, from + direction * position.viewportDimension * page);
    return true;
  }

  /// To the top, or the bottom of what has loaded so far.
  static bool toEnd(bool bottom) {
    final position = target();
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
    if (Motion.reduced) {
      position.jumpTo(clamped);
      return;
    }
    _heading[position] = clamped;
    position.animateTo(clamped, duration: duration, curve: Curves.easeOutCubic);
  }
}
