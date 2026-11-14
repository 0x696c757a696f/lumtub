import 'package:flutter/widgets.dart';

import 'motion.dart';
import 'page_switcher.dart';

/// Content taking the place of a spinner, a placeholder or an error: it
/// fades in while settling from a hair smaller to its full size, once, when
/// it is first built. Content that comes with its page, content built with
/// [enabled] false and anything while animations are reduced is simply
/// there. Settled, it costs no layer.
class Reveal extends StatefulWidget {
  const Reveal({super.key, this.enabled = true, required this.child});

  /// Read when it is first built only.
  final bool enabled;
  final Widget child;

  static const scale = 0.98;

  /// Whether content built now at [context] should come in.
  static bool animates(BuildContext context, {bool enabled = true}) => enabled && !Motion.reduced && !PageSwitcher.entering(context);

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    final animates = Reveal.animates(context, enabled: widget.enabled);
    _controller = AnimationController(vsync: this, duration: Ease.fade, value: animates ? 0 : 1);
    _opacity = CurvedAnimation(parent: _controller, curve: Ease.out);
    _scale = Tween(begin: Reveal.scale, end: 1.0).animate(_opacity);
    if (animates) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _opacity, child: ScaleTransition(scale: _scale, child: widget.child));
}

/// [Reveal] for a sliver, such as a grid of results: it only fades, as one
/// layer for the whole sliver, never card by card.
class SliverReveal extends StatefulWidget {
  const SliverReveal({super.key, this.enabled = true, required this.sliver});
  final bool enabled;
  final Widget sliver;

  @override
  State<SliverReveal> createState() => _SliverRevealState();
}

class _SliverRevealState extends State<SliverReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    final animates = Reveal.animates(context, enabled: widget.enabled);
    _controller = AnimationController(vsync: this, duration: Ease.fade, value: animates ? 0 : 1);
    _opacity = CurvedAnimation(parent: _controller, curve: Ease.out);
    if (animates) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SliverFadeTransition(opacity: _opacity, sliver: widget.sliver);
}

/// One of two or more faces, such as a button's icon for on and off: a
/// change fades the new one in as it grows to size, over the old one fading
/// out. The faces need keys, or icons, that tell them apart.
class Swap extends StatelessWidget {
  const Swap({super.key, this.scale = 0.8, required this.child});
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: Motion.of(Ease.fade),
        switchInCurve: Ease.out,
        switchOutCurve: Ease.out,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: Tween(begin: scale, end: 1.0).animate(animation), child: child),
        ),
        child: child,
      );
}
