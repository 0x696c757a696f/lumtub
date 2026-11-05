import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme.dart';

/// 护眼暖色 over the video: each colour is multiplied, so black stays black
/// and white turns the colour of paper under a lamp; blue goes down most,
/// green a little, red not at all. One rectangle drawn over the picture,
/// so it costs next to nothing. The rest of the window is warmed in its
/// colour scheme instead ([warmScheme]), so a palette keeps its accent and
/// the colour of what is chosen.
class WarmLayer extends StatelessWidget {
  const WarmLayer({super.key, required this.child, this.behind = false});

  /// Under [behind], the light goes beneath [child]: video controls stay
  /// as they are while the picture under them is warmed.
  final Widget child;
  final bool behind;

  /// What white becomes at [warmth].
  static Color tint(double warmth) {
    final w = warmth.clamp(0.0, 1.0);
    return Color.from(alpha: 1, red: 1, green: 1 - 0.12 * w, blue: 1 - 0.40 * w);
  }

  @override
  Widget build(BuildContext context) {
    final warmth = Theme.of(context).extension<AppTones>()?.warmth ?? 0;
    final light = Positioned.fill(
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: warmth),
          duration: Motion.of(const Duration(milliseconds: 1200)),
          curve: Curves.easeInOut,
          builder: (context, value, _) => value <= 0.001 ? const SizedBox.shrink() : CustomPaint(painter: _Warm(tint(value))),
        ),
      ),
    );
    return Stack(fit: StackFit.passthrough, children: behind ? [light, child] : [child, light]);
  }
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

/// [color] under the warm light of [warmth], for the window's own
/// colours. A multiply would turn a pale blue page olive; instead each
/// colour moves toward lamplit paper of the same lightness, so a palette
/// passes through a quiet neutral on its way to warm and keeps its
/// contrast.
Color warmColor(Color color, double warmth) {
  final w = warmth.clamp(0.0, 1.0);
  if (w == 0) return color;
  final lightness = HSLColor.fromColor(color).lightness;
  final paper = HSLColor.fromAHSL(color.a, 34, 0.55, lightness).toColor();
  return Color.lerp(color, paper, 0.7 * w)!;
}

/// [scheme] under the warm light: page, cards, text and borders fully;
/// the accent and what is chosen only a touch, so they stay clean instead
/// of going grey, and still look lit by the same lamp.
ColorScheme warmScheme(ColorScheme scheme, double warmth) {
  Color w(Color c) => warmColor(c, warmth);
  Color half(Color c) => warmColor(c, warmth / 4);
  return scheme.copyWith(
    primary: half(scheme.primary),
    primaryContainer: half(scheme.primaryContainer),
    secondaryContainer: half(scheme.secondaryContainer),
    tertiaryContainer: half(scheme.tertiaryContainer),
    onPrimaryContainer: w(scheme.onPrimaryContainer),
    secondary: w(scheme.secondary),
    onSecondary: w(scheme.onSecondary),
    onSecondaryContainer: w(scheme.onSecondaryContainer),
    onTertiaryContainer: w(scheme.onTertiaryContainer),
    surface: w(scheme.surface),
    onSurface: w(scheme.onSurface),
    onSurfaceVariant: w(scheme.onSurfaceVariant),
    surfaceDim: w(scheme.surfaceDim),
    surfaceBright: w(scheme.surfaceBright),
    surfaceContainerLowest: w(scheme.surfaceContainerLowest),
    surfaceContainerLow: w(scheme.surfaceContainerLow),
    surfaceContainer: w(scheme.surfaceContainer),
    surfaceContainerHigh: w(scheme.surfaceContainerHigh),
    surfaceContainerHighest: w(scheme.surfaceContainerHighest),
    outline: w(scheme.outline),
    outlineVariant: w(scheme.outlineVariant),
    inverseSurface: w(scheme.inverseSurface),
    onInverseSurface: w(scheme.onInverseSurface),
  );
}
