import 'package:flutter/widgets.dart';

import 'motion.dart';

/// The page area's change from one page to the next. On a phone, between
/// the bottom bar's pages, the new page slides in a little from the side of
/// its tab while fading in, the old one leaving the other way; elsewhere
/// the pages only cross-fade. With animations reduced the page changes at
/// once. A page on its way out runs no animations and takes no focus.
class PageSwitcher extends StatefulWidget {
  const PageSwitcher({super.key, required this.pageKey, required this.child, this.index, this.slides = false});

  /// Names the page [child] is; a new name switches.
  final String pageKey;

  /// The page's place in the bottom bar, or null for a page not in it.
  final int? index;

  /// Whether a change between two of the bottom bar's pages slides.
  final bool slides;
  final Widget child;

  /// How far a page slides, as a part of its width.
  static const distance = 0.08;

  /// Whether the page around [context] is still coming in: what it shows
  /// then arrives with it, and needs no entrance of its own.
  static bool entering(BuildContext context) => context.getInheritedWidgetOfExactType<_Entering>()?.animation.status == AnimationStatus.forward;

  @override
  State<PageSwitcher> createState() => _PageSwitcherState();
}

class _PageSwitcherState extends State<PageSwitcher> {
  /// The way the shown page came in: 1 from the end side, -1 from the
  /// start side, 0 without sliding.
  int _entered = 0;

  /// The way each page on its way out left, by its name.
  final _left = <String, int>{};

  @override
  void didUpdateWidget(PageSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pageKey == oldWidget.pageKey) return;
    final from = oldWidget.index;
    final to = widget.index;
    final way = widget.slides && from != null && to != null ? (to - from).sign : 0;
    _entered = way;
    _left
      ..remove(oldWidget.pageKey)
      ..[oldWidget.pageKey] = way
      ..remove(widget.pageKey);
    while (_left.length > 8) {
      _left.remove(_left.keys.first);
    }
  }

  Widget _transition(Widget child, Animation<double> animation) {
    final key = child.key;
    final shown = key is ValueKey<String> && key.value == widget.pageKey;
    final way = shown ? _entered : (key is ValueKey<String> ? _left[key.value] ?? 0 : 0);
    // The one coming in starts on its tab's side; the one leaving ends on
    // the other side.
    final dx = PageSwitcher.distance * way * (shown ? 1 : -1);
    return _Entering(
      animation: animation,
      child: TickerMode(
        enabled: shown,
        child: ExcludeFocus(
          excluding: !shown,
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: animation.drive(Tween(begin: Offset(dx, 0), end: Offset.zero)),
              textDirection: Directionality.maybeOf(context),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    return AnimatedSwitcher(
      duration: Motion.of(slides ? Ease.move : Ease.fade),
      switchInCurve: slides ? Ease.curve : Curves.linear,
      switchOutCurve: slides ? Ease.curve : Curves.linear,
      // A new closure each time, so the pages already there are wrapped
      // again: the one that was shown is now on its way out.
      transitionBuilder: (child, animation) => _transition(child, animation),
      child: KeyedSubtree(key: PageStorageKey<String>(widget.pageKey), child: widget.child),
    );
  }
}

/// The animation a page comes in or leaves with, for [PageSwitcher.entering].
class _Entering extends InheritedWidget {
  const _Entering({required this.animation, required super.child});
  final Animation<double> animation;

  @override
  bool updateShouldNotify(_Entering oldWidget) => false;
}
