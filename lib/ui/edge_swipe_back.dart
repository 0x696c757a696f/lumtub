import 'package:material_ui/material_ui.dart';

import 'motion.dart';

/// iOS's swipe from the left edge back to the page before: the page
/// follows the finger, and goes back when let go far or fast enough. Pages
/// in Lumtub are not routes of their own, so the system's swipe does not
/// reach them. In a right-to-left language the swipe starts at the right
/// edge.
class EdgeSwipeBack extends StatefulWidget {
  const EdgeSwipeBack({super.key, required this.enabled, required this.canGoBack, required this.onBack, required this.child});
  final bool enabled;
  final bool Function() canGoBack;
  final VoidCallback onBack;
  final Widget child;

  /// How far in from the edge a swipe may start.
  static const edge = 20.0;

  @override
  State<EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<EdgeSwipeBack> with SingleTickerProviderStateMixin {
  late final _offset = AnimationController(vsync: this, lowerBound: 0, upperBound: double.infinity, value: 0);
  bool _dragging = false;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _start(DragStartDetails details) {
    _dragging = widget.canGoBack();
    if (_dragging) _offset.stop();
  }

  void _update(DragUpdateDetails details, bool rtl) {
    if (!_dragging) return;
    final delta = details.primaryDelta ?? 0;
    _offset.value = (_offset.value + (rtl ? -delta : delta)).clamp(0, double.infinity);
  }

  Future<void> _end(DragEndDetails details, double width, bool rtl) async {
    if (!_dragging) return;
    _dragging = false;
    final velocity = (details.primaryVelocity ?? 0) * (rtl ? -1 : 1);
    final duration = Motion.of(const Duration(milliseconds: 220));
    if (_offset.value > width / 3 || velocity > 700) {
      await _offset.animateTo(width, duration: duration, curve: Curves.easeOut);
      if (!mounted) return;
      widget.onBack();
      _offset.value = 0;
    } else {
      await _offset.animateTo(0, duration: duration, curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return Stack(children: [
        AnimatedBuilder(
          animation: _offset,
          builder: (context, child) => Transform.translate(offset: Offset(rtl ? -_offset.value : _offset.value, 0), child: child),
          child: widget.child,
        ),
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: EdgeSwipeBack.edge,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _start,
            onHorizontalDragUpdate: (details) => _update(details, rtl),
            onHorizontalDragEnd: (details) => _end(details, width, rtl),
            onHorizontalDragCancel: () {
              if (!_dragging) return;
              _dragging = false;
              _offset.animateTo(0, duration: Motion.of(const Duration(milliseconds: 220)));
            },
          ),
        ),
      ]);
    });
  }
}
