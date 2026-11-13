// Adapted from prism_ui (FlClash), GPL-3.0: AnimatedGlyph.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'motion.dart';

/// A navigation icon that fills in when selected: the outlined and filled
/// faces cross-fade while the icon pops a little larger and back. Give the
/// same [FillIcon] as a destination's icon and selected icon, so the one
/// state carries across the change. With animations reduced it just swaps.
class FillIcon extends StatefulWidget {
  const FillIcon(this.outline, this.fill, {super.key, required this.selected});
  final IconData outline;
  final IconData fill;
  final bool selected;

  static const duration = Duration(milliseconds: 350);
  static const pop = 0.1;

  @override
  State<FillIcon> createState() => _FillIconState();
}

class _FillIconState extends State<FillIcon> with TickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(vsync: this, duration: FillIcon.duration, value: widget.selected ? 1 : 0);
  late final CurvedAnimation _eased = CurvedAnimation(parent: _fill, curve: Curves.easeInOutCubic);
  late final AnimationController _pop = AnimationController(vsync: this, duration: FillIcon.duration);
  late final Listenable _both = Listenable.merge([_eased, _pop]);

  @override
  void didUpdateWidget(FillIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
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
    _eased.dispose();
    _fill.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _both,
        builder: (context, _) {
          final fill = _eased.value;
          final scale = 1 + (_pop.isAnimating ? math.sin(math.pi * _pop.value) * FillIcon.pop : 0.0);
          final Widget face = fill <= 0
              ? Icon(widget.outline)
              : fill >= 1
                  ? Icon(widget.fill)
                  : Stack(alignment: Alignment.center, children: [
                      Opacity(opacity: 1 - fill, child: Icon(widget.outline)),
                      Opacity(opacity: fill, child: Icon(widget.fill)),
                    ]);
          return scale == 1 ? face : Transform.scale(scale: scale, child: face);
        },
      );
}
