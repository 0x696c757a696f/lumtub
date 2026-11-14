// Adapted from prism_ui (FlClash), GPL-3.0.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'motion.dart';

enum _Edge {
  start(Axis.horizontal, AlignmentDirectional.topStart, Offset(-1, 0)),
  bottom(Axis.vertical, AlignmentDirectional.bottomStart, Offset(0, 1));

  const _Edge(this.axis, this.alignment, this.hidden);
  final Axis axis;
  final AlignmentDirectional alignment;
  final Offset hidden;
}

/// The navigation rail or the bottom bar coming and going with the window's
/// width: it grows from its edge while sliding in and fading up, and the page
/// beside it gives up or takes back the room as it moves. A hidden one is not
/// built at all, so it takes no focus and says nothing to a screen reader.
class AnimatedVisibility extends StatefulWidget {
  const AnimatedVisibility.rail({super.key, required this.visible, required this.child}) : _edge = _Edge.start;
  const AnimatedVisibility.bottomBar({super.key, required this.visible, required this.child}) : _edge = _Edge.bottom;

  final bool visible;
  final Widget child;
  final _Edge _edge;

  static const duration = Duration(milliseconds: 300);

  @override
  State<AnimatedVisibility> createState() => _AnimatedVisibilityState();
}

class _AnimatedVisibilityState extends State<AnimatedVisibility> with SingleTickerProviderStateMixin {
  // Settling in, then speeding away: the same curve run backwards.
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  /// What is shown while it leaves: the last child it had while visible.
  late Widget _shown;
  late bool _built;

  @override
  void initState() {
    super.initState();
    _shown = widget.child;
    _built = widget.visible;
    _controller = AnimationController(vsync: this, value: widget.visible ? 1 : 0, duration: Motion.of(AnimatedVisibility.duration))..addStatusListener(_status);
    _animation = CurvedAnimation(parent: _controller, curve: Ease.curve);
  }

  @override
  void didUpdateWidget(AnimatedVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible) _shown = widget.child;
    if (widget.visible == oldWidget.visible) return;
    if (Motion.reduced) {
      _built = widget.visible;
      _controller.value = widget.visible ? 1 : 0;
      return;
    }
    _controller.duration = AnimatedVisibility.duration;
    if (widget.visible) {
      _built = true;
      unawaited(_controller.forward());
    } else if (_controller.isDismissed) {
      _built = false;
    } else {
      unawaited(_controller.reverse());
    }
  }

  void _status(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || widget.visible || !_built) return;
    setState(() => _built = false);
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edge = widget._edge;
    final content = !_built
        ? const SizedBox.shrink()
        : AnimatedBuilder(
            animation: _animation,
            // Clipped only while moving: settled, a shadow or a glow may
            // reach past it.
            builder: (context, child) {
              final factor = math.max(_animation.value, 0.0);
              return ClipRect(
                clipBehavior: _controller.isCompleted ? Clip.none : Clip.hardEdge,
                child: Align(
                  alignment: edge.alignment,
                  widthFactor: edge.axis == Axis.horizontal ? factor : null,
                  heightFactor: edge.axis == Axis.vertical ? factor : null,
                  child: child,
                ),
              );
            },
            child: FadeTransition(
              opacity: _animation,
              child: SlideTransition(
                position: _animation.drive(Tween(begin: edge.hidden, end: Offset.zero)),
                textDirection: Directionality.maybeOf(context),
                child: _shown,
              ),
            ),
          );
    final hidden = !widget.visible;
    return ExcludeSemantics(
      excluding: hidden,
      child: ExcludeFocus(excluding: hidden, child: IgnorePointer(ignoring: hidden, child: content)),
    );
  }
}
