import 'package:flutter/material.dart';

import 'motion.dart';

/// 护眼暖色: the window, video included, under a warm light. Each colour is
/// multiplied, so black stays black and white turns the colour of paper
/// under a lamp; blue goes down most, green a little, red not at all. It is
/// one rectangle drawn over the window, so it costs next to nothing.
class WarmLayer extends StatelessWidget {
  const WarmLayer({super.key, required this.warmth, required this.child});

  /// 0 for none, up to 1 for the warmest.
  final double warmth;
  final Widget child;

  /// What white becomes at [warmth].
  static Color tint(double warmth) {
    final w = warmth.clamp(0.0, 1.0);
    return Color.from(alpha: 1, red: 1, green: 1 - 0.12 * w, blue: 1 - 0.40 * w);
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.passthrough, children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: warmth),
              duration: Motion.of(const Duration(milliseconds: 1200)),
              curve: Curves.easeInOut,
              builder: (context, value, _) => value <= 0.001 ? const SizedBox.shrink() : CustomPaint(painter: _Warm(tint(value))),
            ),
          ),
        ),
      ]);
}

class _Warm extends CustomPainter {
  _Warm(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(Offset.zero & size, Paint()
    ..color = color
    ..blendMode = BlendMode.multiply);

  @override
  bool shouldRepaint(_Warm old) => old.color != color;
}
