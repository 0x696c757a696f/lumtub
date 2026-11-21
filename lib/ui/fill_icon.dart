import 'dart:math';

import 'package:flutter/material.dart';

import 'motion.dart';

/// An icon that is its outline when off and its filled form when on: the
/// filled face fades in as the icon pops slightly, the way a tab bar or a
/// like button answers a tap. Colour and size come from the ambient
/// [IconTheme]. Given as both a destination's icon and selectedIcon, one
/// State carries the change across.
class FillIcon extends StatefulWidget {
  const FillIcon(this.outline, this.fill, {super.key, required this.selected});
  final IconData outline;
  final IconData fill;
  final bool selected;

  static const duration = Duration(milliseconds: 350);

  /// How far the icon grows at the height of the pop.
  static const pop = 0.1;

  @override
  State<FillIcon> createState() => _FillIconState();
}

class _FillIconState extends State<FillIcon> with TickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(vsync: this, duration: FillIcon.duration, value: widget.selected ? 1 : 0);
  late final AnimationController _pop = AnimationController(vsync: this, duration: FillIcon.duration);

  @override
  void didUpdateWidget(FillIcon old) {
    super.didUpdateWidget(old);
    if (widget.selected == old.selected) return;
    if (Motion.reduced) {
      _fill.value = widget.selected ? 1 : 0;
      return;
    }
    if (widget.selected) {
      _fill.forward();
      if (!_pop.isAnimating) _pop.forward(from: 0);
    } else {
      _fill.reverse();
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([_fill, _pop]),
        builder: (context, _) {
          final f = Curves.easeInOutCubic.transform(_fill.value);
          final scale = 1 + sin(pi * _pop.value) * FillIcon.pop;
          final Widget icon = f == 0
              ? Icon(widget.outline)
              : f == 1
                  ? Icon(widget.fill)
                  : Stack(alignment: Alignment.center, children: [
                      Opacity(opacity: 1 - f, child: Icon(widget.outline)),
                      Opacity(opacity: f, child: Icon(widget.fill)),
                    ]);
          return scale == 1 ? icon : Transform.scale(scale: scale, child: icon);
        },
      );
}
