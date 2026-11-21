import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'motion.dart';

/// Gives [child], a placeholder made of [SkeletonBox]es, a highlight that
/// sweeps across it. Only the painted pixels are tinted, so the shapes stay
/// still. Put a whole grid in one Skeleton so a single animation drives it.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});
  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (!Motion.reduced) _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final glow = surface.withAlpha(60);
    final clear = surface.withAlpha(0);
    final controller = _controller;
    final child = RepaintBoundary(child: widget.child);
    Widget shine(double t) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => ui.Gradient.linear(
            Offset(0, bounds.height * 0.35),
            Offset(bounds.width, bounds.height * 0.95),
            [clear, glow, glow, clear],
            const [0.1, 0.3, 0.5, 0.7],
            TileMode.clamp,
            Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, bounds.width * t, 0, 0, 1]),
          ),
          child: child,
        );
    if (controller == null) return shine(0.5);
    return AnimatedBuilder(animation: controller, builder: (context, _) => shine(-0.5 + 2 * controller.value));
  }
}

/// A rounded block standing in for text or a picture while it loads.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 12, this.radius = 4});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: DecoratedBox(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(radius))),
      );
}

/// Shows [child] only once [delay] has passed, so a load that finishes
/// quickly never flashes a placeholder.
class DelayedReveal extends StatefulWidget {
  const DelayedReveal({super.key, this.delay = DelayedReveal.wait, required this.child});
  final Duration delay;
  final Widget child;

  static const wait = Duration(milliseconds: 400);
  static const enter = Duration(milliseconds: 300);

  @override
  State<DelayedReveal> createState() => _DelayedRevealState();
}

class _DelayedRevealState extends State<DelayedReveal> {
  Timer? _timer;
  late bool _shown = widget.delay <= Duration.zero;

  @override
  void initState() {
    super.initState();
    if (!_shown) {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _shown ? Entrance(duration: DelayedReveal.enter, curve: Easing.emphasizedDecelerate, child: widget.child) : const SizedBox.shrink();
}
