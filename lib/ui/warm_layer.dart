import 'dart:math';

import 'package:flutter/material.dart';

import '../appearance_settings.dart';
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

  /// What white becomes at [warmth]: the colour of a black body at its
  /// temperature ([AppearanceSettings.kelvinOf]) against one at 6500 K,
  /// the white of a screen, as night light tools such as f.lux take it.
  static Color tint(double warmth) {
    final w = warmth.clamp(0.0, 1.0);
    if (w == 0) return const Color(0xFFFFFFFF);
    final light = _blackBody(AppearanceSettings.kelvinOf(w).toDouble());
    final white = _blackBody(6500);
    return Color.from(alpha: 1, red: (light.$1 / white.$1).clamp(0, 1), green: (light.$2 / white.$2).clamp(0, 1), blue: (light.$3 / white.$3).clamp(0, 1));
  }

  /// A black body's colour at [kelvin], 1000 to 40000 K, by Tanner
  /// Helland's fit of the CIE 1964 colour matching data, on a scale of 255.
  static (double, double, double) _blackBody(double kelvin) {
    final t = kelvin / 100;
    final red = t <= 66 ? 255.0 : 329.698727446 * pow(t - 60, -0.1332047592);
    final green = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492);
    final blue = t >= 66 ? 255.0 : t <= 19 ? 0.0 : 138.5177312231 * log(t - 10) - 305.0447927307;
    return (red.clamp(0, 255).toDouble(), green.clamp(0, 255).toDouble(), blue.clamp(0, 255).toDouble());
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
/// colour moves toward a grey as bright as it, lit by the same lamp as
/// the video ([WarmLayer.tint]), so a palette passes through a quiet
/// neutral on its way to warm and keeps its contrast. White turns the
/// colour of lamplit paper too, as warm as a white picture: going by
/// lightness alone, it stayed white.
Color warmColor(Color color, double warmth) {
  final w = warmth.clamp(0.0, 1.0);
  if (w == 0) return color;
  // Lit by the lamp but as bright as before where it can be, so text
  // keeps its contrast even by candlelight.
  double brightness(double r, double g, double b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final grey = brightness(color.r, color.g, color.b);
  final lamp = WarmLayer.tint(w);
  final lift = grey / brightness(lamp.r, lamp.g, lamp.b);
  double lit(double channel) => (channel * lift).clamp(0.0, 1.0);
  final paper = Color.from(alpha: color.a, red: lit(lamp.r), green: lit(lamp.g), blue: lit(lamp.b));
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
