import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Shows and hides a bar or panel by sliding it in from its edge while the
/// page beside it gives up or takes back the room. A hidden one is not
/// built at all, so it takes no focus and nothing for a screen reader.
class AnimatedVisibility extends StatefulWidget {
  const AnimatedVisibility.rail({super.key, required this.visible, required this.child})
      : _axis = Axis.horizontal,
        _from = -1,
        _alignment = AlignmentDirectional.centerStart;
  const AnimatedVisibility.side({super.key, required this.visible, required this.child})
      : _axis = Axis.horizontal,
        _from = 1,
        _alignment = AlignmentDirectional.centerEnd;
  const AnimatedVisibility.topBar({super.key, required this.visible, required this.child})
      : _axis = Axis.vertical,
        _from = -1,
        _alignment = AlignmentDirectional.topCenter;
  const AnimatedVisibility.bottomBar({super.key, required this.visible, required this.child})
      : _axis = Axis.vertical,
        _from = 1,
        _alignment = AlignmentDirectional.bottomCenter;

  final bool visible;
  final Widget child;
  final Axis _axis;

  /// Which side of its place the child starts from: -1 before, 1 after.
  final double _from;
  final AlignmentGeometry _alignment;

  static const duration = Duration(milliseconds: 300);

  @override
  State<AnimatedVisibility> createState() => _AnimatedVisibilityState();
}

class _AnimatedVisibilityState extends State<AnimatedVisibility> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AnimatedVisibility.duration, value: widget.visible ? 1 : 0);
  late final Animation<double> _progress = CurvedAnimation(parent: _controller, curve: Ease.curve);
  Widget? _last;

  @override
  void didUpdateWidget(AnimatedVisibility old) {
    super.didUpdateWidget(old);
    if (widget.visible == old.visible) return;
    if (Motion.reduced) {
      _controller.value = widget.visible ? 1 : 0;
      return;
    }
    _controller.duration = Motion.of(AnimatedVisibility.duration);
    if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visible) _last = widget.child;
    final last = _last;
    final horizontal = widget._axis == Axis.horizontal;
    final rtl = horizontal && Directionality.of(context) == TextDirection.rtl;
    final child = last == null
        ? null
        : FadeTransition(
            opacity: _progress,
            child: IgnorePointer(
              ignoring: !widget.visible,
              child: ExcludeFocus(
                excluding: !widget.visible,
                child: ExcludeSemantics(excluding: !widget.visible, child: last),
              ),
            ),
          );
    return AnimatedBuilder(
      animation: _controller,
      child: child,
      builder: (context, child) {
        if (child == null || (!widget.visible && _controller.isDismissed)) return const SizedBox.shrink();
        final t = _progress.value;
        final away = (1 - t) * widget._from * (rtl ? -1 : 1);
        return ClipRect(
          clipBehavior: t < 1 ? Clip.hardEdge : Clip.none,
          child: Align(
            alignment: widget._alignment,
            widthFactor: horizontal ? t : null,
            heightFactor: horizontal ? null : t,
            child: FractionalTranslation(
              translation: horizontal ? Offset(away, 0) : Offset(0, away),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
