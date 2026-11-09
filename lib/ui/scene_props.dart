import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The glossy things of the 2000s look, painted for the skin scenes: glass
/// orbs with a world inside, the Earth, rainbow bubbles, glass stars,
/// shining discs, sprouts, tropical fish, jellyfish, dolphins, butterflies,
/// coral and the line where water meets air. Every one is lit from the top
/// left: a crescent of light on the upper rim, a softer one on the lower
/// rim, a shadow just inside the first, so nothing reads as flat.

const _white = Color(0xFFFFFFFF);

Paint _radial(Rect rect, List<Color> colors, {Alignment center = Alignment.center, List<double>? stops, double radius = 0.5}) =>
    Paint()..shader = RadialGradient(center: center, radius: radius, colors: colors, stops: stops).createShader(rect);

Paint _linear(Rect rect, List<Color> colors, {Alignment begin = Alignment.topCenter, Alignment end = Alignment.bottomCenter, List<double>? stops}) =>
    Paint()..shader = LinearGradient(begin: begin, end: end, colors: colors, stops: stops).createShader(rect);

/// The gloss every round thing gets: the bright crescent along the top,
/// the shadow just under it, and the light thrown back along the bottom.
void gloss(Canvas canvas, Offset c, double r, {double strength = 1, bool shadow = true}) {
  final top = Path()
    ..addOval(Rect.fromCircle(center: c, radius: r * 0.93))
    ..fillType = PathFillType.evenOdd;
  final cut = Path()..addOval(Rect.fromCircle(center: c + Offset(r * 0.08, r * 0.3), radius: r * 0.95));
  final crescent = Path.combine(PathOperation.difference, top, cut);
  final band = Rect.fromLTRB(c.dx - r, c.dy - r, c.dx + r, c.dy);
  canvas.drawPath(crescent, _linear(band, [_white.withValues(alpha: 0.95 * strength), _white.withValues(alpha: 0.15 * strength)]));
  if (shadow) {
    final under = Path.combine(PathOperation.difference, Path()..addOval(Rect.fromCircle(center: c + Offset(r * 0.08, r * 0.3), radius: r * 0.95)),
        Path()..addOval(Rect.fromCircle(center: c + Offset(r * 0.1, r * 0.42), radius: r * 0.94)));
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.drawPath(under, Paint()
      ..color = const Color(0xFF00203A).withValues(alpha: 0.12 * strength)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.03));
    canvas.restore();
  }
  // The light thrown back up from below.
  final low = Rect.fromCenter(center: c + Offset(0, r * 0.62), width: r * 1.2, height: r * 0.5);
  canvas.drawOval(low, _radial(low, [_white.withValues(alpha: 0.45 * strength), _white.withValues(alpha: 0)]));
  // A small sharp glint.
  canvas.drawCircle(c + Offset(-r * 0.42, -r * 0.5), r * 0.07, Paint()..color = _white.withValues(alpha: 0.9 * strength));
}

/// A soap bubble: clear, with a thin rim that shifts through the rainbow.
void rainbowBubble(Canvas canvas, Offset c, double r, {double opacity = 1}) {
  final rect = Rect.fromCircle(center: c, radius: r);
  canvas.drawCircle(c, r, _radial(rect, [_white.withValues(alpha: 0.02 * opacity), _white.withValues(alpha: 0.06 * opacity), _white.withValues(alpha: 0.5 * opacity)], stops: const [0, 0.78, 1]));
  canvas.drawCircle(
    c,
    r * 0.94,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, r * 0.09)
      ..shader = SweepGradient(colors: [
        const Color(0xFFFF7AD9).withValues(alpha: 0.45 * opacity),
        const Color(0xFFFFE27A).withValues(alpha: 0.4 * opacity),
        const Color(0xFF7AFFB0).withValues(alpha: 0.4 * opacity),
        const Color(0xFF7AD8FF).withValues(alpha: 0.5 * opacity),
        const Color(0xFFB07AFF).withValues(alpha: 0.45 * opacity),
        const Color(0xFFFF7AD9).withValues(alpha: 0.45 * opacity),
      ], transform: const GradientRotation(0.6)).createShader(rect)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.6, r * 0.04)),
  );
  final hl = Rect.fromCenter(center: c + Offset(-r * 0.32, -r * 0.42), width: r * 0.8, height: r * 0.42);
  canvas.save();
  canvas.translate(hl.center.dx, hl.center.dy);
  canvas.rotate(-0.5);
  canvas.translate(-hl.center.dx, -hl.center.dy);
  canvas.drawOval(hl, _linear(hl, [_white.withValues(alpha: 0.9 * opacity), _white.withValues(alpha: 0)]));
  canvas.restore();
  canvas.drawCircle(c + Offset(r * 0.45, r * 0.45), r * 0.1, Paint()..color = _white.withValues(alpha: 0.6 * opacity));
}

/// A clear glass ball with [inside] painted in it, bent a little towards
/// the middle as glass would, darker and bluer at the rim.
void glassOrb(Canvas canvas, Offset c, double r, {void Function(Canvas canvas, Rect inside)? inside, Color tint = const Color(0xFF9FE6FF), bool night = false}) {
  final rect = Rect.fromCircle(center: c, radius: r);
  // Its shadow and the light it gathers on what is below.
  final shade = Rect.fromCenter(center: c + Offset(0, r * 1.08), width: r * 1.6, height: r * 0.22);
  canvas.drawOval(shade, _radial(shade, [const Color(0xFF00304A).withValues(alpha: night ? 0.3 : 0.18), const Color(0x0000304A)]));
  canvas.save();
  canvas.clipPath(Path()..addOval(rect));
  if (inside != null) {
    // The world inside, shrunk at the edges as if seen through the curve.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1.08, 1.08);
    canvas.translate(-c.dx, -c.dy);
    inside(canvas, rect);
    canvas.restore();
  } else {
    canvas.drawCircle(c, r, _radial(rect, [tint.withValues(alpha: 0.1), tint.withValues(alpha: 0.35)]));
  }
  // The glass itself: clear in the middle, deep at the rim.
  canvas.drawCircle(c, r, _radial(rect, [tint.withValues(alpha: 0), tint.withValues(alpha: 0.05), Color.lerp(tint, const Color(0xFF0A4A8A), 0.5)!.withValues(alpha: 0.55)], stops: const [0, 0.7, 1]));
  canvas.restore();
  canvas.drawCircle(c, r, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, r * 0.02)
    ..color = _white.withValues(alpha: 0.7));
  gloss(canvas, c, r, strength: night ? 0.6 : 1);
}

/// The Earth as a glossy marble: deep blue seas, green land, a few swirls
/// of cloud and a glowing rim of air. [green] makes it the leafy planet
/// of the eco posters.
void globe(Canvas canvas, Offset c, double r, {bool night = false, bool green = false, double turn = 0}) {
  final rect = Rect.fromCircle(center: c, radius: r);
  canvas.drawCircle(c, r * 1.12, _radial(Rect.fromCircle(center: c, radius: r * 1.12), [const Color(0x0000C8FF), const Color(0x0000C8FF), (night ? const Color(0xFF3FA8FF) : const Color(0xFFBFF4FF)).withValues(alpha: 0.6), const Color(0x0000C8FF)], stops: const [0, 0.82, 0.9, 1]));
  canvas.save();
  canvas.clipPath(Path()..addOval(rect));
  canvas.drawCircle(c, r, _radial(rect, green ? const [Color(0xFF7FE3FF), Color(0xFF1D9BD8), Color(0xFF0A4F94)] : const [Color(0xFF5FC8FF), Color(0xFF1570C8), Color(0xFF062F6E)], center: const Alignment(-0.35, -0.4), radius: 0.85));
  // Land: soft rounded masses, as on a toy globe.
  final land = Paint()
    ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: green ? const [Color(0xFFB8F26A), Color(0xFF4DBA2A), Color(0xFF1F7A1A)] : const [Color(0xFF9EDB6A), Color(0xFF4FA83A), Color(0xFF7A8A3A)]).createShader(rect)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.012);
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(turn);
  final shallows = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.07
    ..color = const Color(0xFF8FF0FF).withValues(alpha: night ? 0.3 : 0.6)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.03);
  for (final shape in _continents) {
    final points = [
      for (final o in shape)
        () {
          final q = Offset(o.dx * r * 0.82, o.dy * r * 0.82);
          // Pressed towards the rim, as on a sphere.
          final d = q.distance / r;
          return d == 0 ? q : q * (math.sin(math.min(d, 1) * math.pi / 2) / d);
        }(),
    ];
    final p = Path()..moveTo((points.last.dx + points.first.dx) / 2, (points.last.dy + points.first.dy) / 2);
    for (var i = 0; i < points.length; i++) {
      final next = points[(i + 1) % points.length];
      final mid = (points[i] + next) / 2;
      p.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    p.close();
    canvas.drawPath(p, shallows);
    canvas.drawPath(p, land);
    // Mountains and forest: darker patches inside the land.
    canvas.save();
    canvas.clipPath(p);
    final b = p.getBounds();
    canvas.drawOval(Rect.fromLTWH(b.left + b.width * 0.3, b.top + b.height * 0.25, b.width * 0.4, b.height * 0.35), Paint()
      ..color = (green ? const Color(0xFF1F7A1A) : const Color(0xFF6A7A2A)).withValues(alpha: 0.45)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.05));
    canvas.restore();
  }
  canvas.restore();
  // Swirls of cloud.
  final cloud = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = _white.withValues(alpha: night ? 0.3 : 0.6)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.04);
  for (final (dx, dy, w, a0, sweep) in const [(-0.3, -0.45, 0.5, 3.6, 1.6), (0.25, 0.1, 0.42, 0.2, 1.9), (-0.1, 0.55, 0.36, 3.3, 1.2), (0.45, -0.3, 0.3, 4.2, 1.3), (0.1, -0.15, 0.22, 1.2, 2.4), (-0.5, 0.2, 0.2, 5.0, 1.8), (0.4, 0.5, 0.25, 2.6, 1.5)]) {
    cloud.strokeWidth = r * 0.06;
    canvas.drawArc(Rect.fromCircle(center: c + Offset(dx * r, dy * r), radius: w * r), a0, sweep, false, cloud);
  }
  // Night side.
  canvas.drawCircle(c, r, _radial(rect, [const Color(0x00000000), const Color(0x00000000), const Color(0xFF02102A).withValues(alpha: night ? 0.75 : 0.45)], center: const Alignment(-0.45, -0.5), radius: 1.15, stops: const [0, 0.55, 1]));
  canvas.restore();
  gloss(canvas, c, r, strength: night ? 0.55 : 0.9, shadow: false);
}

const _continents = [
  // A long, bending land from top to bottom on the left.
  [Offset(-0.7, -0.62), Offset(-0.5, -0.74), Offset(-0.3, -0.68), Offset(-0.2, -0.52), Offset(-0.34, -0.4), Offset(-0.26, -0.28), Offset(-0.38, -0.16), Offset(-0.5, -0.2), Offset(-0.62, -0.34), Offset(-0.78, -0.4)],
  [Offset(-0.3, -0.06), Offset(-0.12, 0.02), Offset(-0.06, 0.2), Offset(-0.16, 0.44), Offset(-0.26, 0.7), Offset(-0.36, 0.62), Offset(-0.38, 0.38), Offset(-0.46, 0.16)],
  // A broad land on the right, with a long peninsula down.
  [Offset(0.08, -0.62), Offset(0.3, -0.76), Offset(0.6, -0.66), Offset(0.8, -0.48), Offset(0.66, -0.3), Offset(0.5, -0.32), Offset(0.4, -0.18), Offset(0.26, -0.2), Offset(0.12, -0.36)],
  [Offset(0.14, -0.08), Offset(0.36, -0.1), Offset(0.48, 0.08), Offset(0.44, 0.34), Offset(0.3, 0.58), Offset(0.2, 0.42), Offset(0.12, 0.16)],
  // Islands.
  [Offset(0.6, 0.42), Offset(0.76, 0.4), Offset(0.8, 0.54), Offset(0.64, 0.6)],
  [Offset(0.56, 0.1), Offset(0.64, 0.06), Offset(0.68, 0.16), Offset(0.6, 0.2)],
];

/// A puffy star of clear coloured glass.
void glassStar(Canvas canvas, Offset c, double r, Color color, {double turn = -math.pi / 2}) {
  final path = Path();
  for (var i = 0; i <= 10; i++) {
    final a = turn + i * math.pi / 5;
    final rr = i.isEven ? r : r * 0.5;
    final p = c + Offset(math.cos(a), math.sin(a)) * rr;
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      final pa = turn + (i - 0.5) * math.pi / 5;
      final pr = i.isEven ? r * 0.62 : r * 0.62;
      final ctrl = c + Offset(math.cos(pa), math.sin(pa)) * pr;
      path.quadraticBezierTo(ctrl.dx, ctrl.dy, p.dx, p.dy);
    }
  }
  final rect = Rect.fromCircle(center: c, radius: r);
  canvas.drawPath(path.shift(Offset(r * 0.06, r * 0.1)), Paint()
    ..color = Color.lerp(color, const Color(0xFF001830), 0.6)!.withValues(alpha: 0.25)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.08));
  canvas.drawPath(path, _radial(rect, [Color.lerp(color, _white, 0.55)!.withValues(alpha: 0.85), color.withValues(alpha: 0.75), Color.lerp(color, const Color(0xFF001A40), 0.35)!.withValues(alpha: 0.95)], center: const Alignment(-0.2, -0.3), radius: 0.7));
  canvas.save();
  canvas.clipPath(path);
  final hl = Rect.fromLTRB(c.dx - r, c.dy - r, c.dx + r * 0.6, c.dy - r * 0.05);
  canvas.drawOval(hl, _linear(hl, [_white.withValues(alpha: 0.75), _white.withValues(alpha: 0)]));
  canvas.restore();
  canvas.drawPath(path, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.8, r * 0.04)
    ..color = _white.withValues(alpha: 0.55));
}

/// A shining disc: silver with rainbow light running round it, a clear hub
/// and a bright streak where the light catches.
void disc(Canvas canvas, Offset c, double r, {double turn = 0, Color label = const Color(0x00000000), double dim = 0}) {
  final rect = Rect.fromCircle(center: c, radius: r);
  canvas.drawCircle(c + Offset(r * 0.04, r * 0.07), r, Paint()
    ..color = const Color(0x33001830)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06));
  canvas.drawCircle(c, r, _radial(rect, const [Color(0xFFF6F8FA), Color(0xFFD5DCE4), Color(0xFFAEB8C4)]));
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = SweepGradient(transform: GradientRotation(turn), colors: const [
        Color(0x00FFFFFF), Color(0x66FF8AE0), Color(0x66FFE08A), Color(0x668AFFC0), Color(0x668AD8FF), Color(0x00FFFFFF),
        Color(0x00FFFFFF), Color(0x55B08AFF), Color(0x558AD8FF), Color(0x558AFFB8), Color(0x55FFE08A), Color(0x00FFFFFF),
      ]).createShader(rect),
  );
  if (label.a > 0) {
    canvas.drawCircle(c, r * 0.72, Paint()..color = label);
  }
  // Grooves.
  for (var k = 0.45; k < 0.98; k += 0.06) {
    canvas.drawCircle(c, r * k, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = _white.withValues(alpha: 0.18));
  }
  // The clear hub.
  canvas.drawCircle(c, r * 0.3, Paint()..color = const Color(0xFFE9EEF3));
  canvas.drawCircle(c, r * 0.3, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.02
    ..color = const Color(0xFFB8C2CE));
  canvas.drawCircle(c, r * 0.12, Paint()..color = const Color(0x66A8C8E0));
  canvas.drawCircle(c, r * 0.12, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.025
    ..color = const Color(0xFFCBD3DD));
  // The streak of light across it.
  final streak = Path()
    ..moveTo(c.dx, c.dy)
    ..arcTo(rect, turn - 2.3, 0.35, false)
    ..close();
  canvas.drawPath(streak, Paint()
    ..color = _white.withValues(alpha: 0.55)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.04));
  final streak2 = Path()
    ..moveTo(c.dx, c.dy)
    ..arcTo(rect, turn + 0.85, 0.3, false)
    ..close();
  canvas.drawPath(streak2, Paint()
    ..color = _white.withValues(alpha: 0.35)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.04));
  // In the dark it only catches a little light.
  if (dim > 0) canvas.drawCircle(c, r, Paint()..color = const Color(0xFF061430).withValues(alpha: dim));
}

/// Two glossy leaves on a short stem.
void sprout(Canvas canvas, Offset foot, double size, {bool night = false}) {
  final stem = Path()
    ..moveTo(foot.dx, foot.dy)
    ..quadraticBezierTo(foot.dx + size * 0.05, foot.dy - size * 0.5, foot.dx, foot.dy - size * 0.75);
  canvas.drawPath(stem, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = size * 0.07
    ..strokeCap = StrokeCap.round
    ..color = night ? const Color(0xFF3E8A4A) : const Color(0xFF5CBF2A));
  for (final side in [-1.0, 1.0]) {
    final base = Offset(foot.dx, foot.dy - size * 0.72);
    final tip = base + Offset(side * size * 0.62, -size * 0.3);
    final leaf = Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(base.dx + side * size * 0.2, base.dy - size * 0.42, tip.dx, tip.dy)
      ..quadraticBezierTo(base.dx + side * size * 0.42, base.dy + size * 0.06, base.dx, base.dy)
      ..close();
    final b = leaf.getBounds();
    canvas.drawPath(leaf, _linear(b, night ? const [Color(0xFF6FD08A), Color(0xFF1E6A3A)] : const [Color(0xFFD6FF8A), Color(0xFF6CD13A), Color(0xFF2E9A1E)], begin: Alignment.topCenter, end: Alignment.bottomCenter));
    // The vein and the shine.
    canvas.drawLine(base, Offset.lerp(base, tip, 0.85)!, Paint()
      ..strokeWidth = size * 0.02
      ..color = _white.withValues(alpha: 0.45));
    canvas.save();
    canvas.clipPath(leaf);
    canvas.drawOval(Rect.fromLTWH(b.left, b.top, b.width * 0.8, b.height * 0.45), Paint()..color = _white.withValues(alpha: 0.35));
    canvas.restore();
  }
}

enum FishKind { clown, tang, angel, gold }

/// A glossy tropical fish facing right (or left when [flip]).
void tropicalFish(Canvas canvas, Offset at, double length, FishKind kind, {bool flip = false, bool night = false}) {
  canvas.save();
  canvas.translate(at.dx, at.dy);
  if (flip) canvas.scale(-1, 1);
  final h = switch (kind) { FishKind.angel => length * 0.75, FishKind.tang => length * 0.52, _ => length * 0.42 };
  final body = Path()
    ..moveTo(length * 0.5, 0)
    ..cubicTo(length * 0.42, -h * 0.75, -length * 0.15, -h * 0.85, -length * 0.36, -h * 0.05)
    ..lineTo(-length * 0.36, h * 0.05)
    ..cubicTo(-length * 0.15, h * 0.85, length * 0.42, h * 0.75, length * 0.5, 0)
    ..close();
  final tail = Path()
    ..moveTo(-length * 0.3, 0)
    ..quadraticBezierTo(-length * 0.5, -h * 0.2, -length * 0.62, -h * 0.62)
    ..quadraticBezierTo(-length * 0.52, 0, -length * 0.62, h * 0.62)
    ..quadraticBezierTo(-length * 0.5, h * 0.2, -length * 0.3, 0)
    ..close();
  final fin = Path()
    ..moveTo(length * 0.1, -h * 0.6)
    ..quadraticBezierTo(-length * 0.1, -h * (kind == FishKind.angel ? 1.5 : 1.05), -length * 0.3, -h * 0.35)
    ..close();
  final rect = Rect.fromLTRB(-length * 0.62, -h, length * 0.5, h);
  final (main, deep, finColor) = switch (kind) {
    FishKind.clown => (const Color(0xFFFF8A1A), const Color(0xFFE0500A), const Color(0xFFFF7A10)),
    FishKind.tang => (const Color(0xFF2A6BFF), const Color(0xFF0B2FA0), const Color(0xFFFFD21A)),
    FishKind.angel => (const Color(0xFFFFE23A), const Color(0xFF1A6ACF), const Color(0xFF3AA8FF)),
    FishKind.gold => (const Color(0xFFFFA42A), const Color(0xFFE8650A), const Color(0xFFFFC870)),
  };
  if (night) canvas.drawCircle(Offset.zero, length * 0.7, _radial(Rect.fromCircle(center: Offset.zero, radius: length * 0.7), [main.withValues(alpha: 0.25), main.withValues(alpha: 0)]));
  final finPaint = Paint()..color = finColor.withValues(alpha: kind == FishKind.gold ? 0.7 : 0.95);
  canvas.drawPath(tail, finPaint);
  canvas.drawPath(fin, finPaint);
  canvas.drawPath(body, _linear(rect, [Color.lerp(main, _white, 0.35)!, main, deep], stops: const [0, 0.45, 1]));
  canvas.save();
  canvas.clipPath(body);
  switch (kind) {
    case FishKind.clown:
      // White bands edged in black.
      for (final x in [0.28, 0.0, -0.26]) {
        final band = Rect.fromCenter(center: Offset(length * x, 0), width: length * 0.1, height: h * 2.2);
        canvas.drawRRect(RRect.fromRectAndRadius(band.inflate(length * 0.018), Radius.circular(length * 0.06)), Paint()..color = const Color(0xFF1A1010));
        canvas.drawRRect(RRect.fromRectAndRadius(band, Radius.circular(length * 0.05)), Paint()..color = _white);
      }
    case FishKind.tang:
      // A dark sweep along the side.
      final sweep = Path()
        ..moveTo(length * 0.35, -h * 0.25)
        ..quadraticBezierTo(0, -h * 0.65, -length * 0.3, -h * 0.1)
        ..quadraticBezierTo(-length * 0.05, h * 0.05, length * 0.15, -h * 0.05)
        ..quadraticBezierTo(0, -h * 0.25, length * 0.35, -h * 0.25);
      canvas.drawPath(sweep, Paint()..color = const Color(0xFF0A1440));
    case FishKind.angel:
      // Blue stripes over yellow.
      for (var x = -0.3; x < 0.5; x += 0.13) {
        canvas.drawLine(Offset(length * x, -h), Offset(length * (x - 0.08), h), Paint()
          ..strokeWidth = length * 0.04
          ..color = const Color(0xFF1A6ACF).withValues(alpha: 0.85));
      }
    case FishKind.gold:
      break;
  }
  // The shine along the back.
  canvas.drawOval(Rect.fromLTRB(-length * 0.12, -h * 0.62, length * 0.38, -h * 0.18), Paint()..color = _white.withValues(alpha: 0.5));
  canvas.restore();
  canvas.drawCircle(Offset(length * 0.3, -h * 0.12), length * 0.055, Paint()..color = _white);
  canvas.drawCircle(Offset(length * 0.31, -h * 0.12), length * 0.035, Paint()..color = const Color(0xFF0A1420));
  canvas.drawCircle(Offset(length * 0.295, -h * 0.14), length * 0.012, Paint()..color = _white);
  canvas.restore();
}

/// A see-through jellyfish with trailing ribbons.
void jellyfish(Canvas canvas, Offset top, double size, {bool night = false}) {
  final color = night ? const Color(0xFF9F8CFF) : const Color(0xFFB8E8FF);
  final bell = Rect.fromCenter(center: top + Offset(0, size * 0.25), width: size, height: size * 0.6);
  canvas.drawPath(Path()..addArc(bell, math.pi, math.pi)..close(), _radial(bell, [color.withValues(alpha: 0.35), color.withValues(alpha: 0.7)], center: const Alignment(0, 0.6), radius: 0.8));
  for (var i = 0; i < 5; i++) {
    final x = bell.left + bell.width * (0.15 + i * 0.175);
    final p = Path()..moveTo(x, bell.center.dy);
    for (var k = 1; k <= 6; k++) {
      p.lineTo(x + math.sin(k * 1.1 + i) * size * 0.06, bell.center.dy + k * size * 0.18);
    }
    canvas.drawPath(p, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.03
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.45));
  }
  canvas.drawOval(Rect.fromCenter(center: bell.center - Offset(size * 0.15, size * 0.15), width: size * 0.4, height: size * 0.14), Paint()..color = _white.withValues(alpha: 0.55));
  if (night) canvas.drawCircle(bell.center, size, _radial(Rect.fromCircle(center: bell.center, radius: size), [color.withValues(alpha: 0.25), color.withValues(alpha: 0)]));
}

/// A leaping dolphin, glossy grey-blue, facing right.
void dolphin(Canvas canvas, Offset at, double length, {bool flip = false, bool night = false}) {
  canvas.save();
  canvas.translate(at.dx, at.dy);
  if (flip) canvas.scale(-1, 1);
  canvas.rotate(-0.35);
  final l = length;
  final body = Path()
    ..moveTo(l * 0.55, l * 0.02)
    ..quadraticBezierTo(l * 0.62, l * 0.0, l * 0.48, -l * 0.03)
    ..cubicTo(l * 0.3, -l * 0.16, -l * 0.15, -l * 0.17, -l * 0.42, -l * 0.02)
    ..lineTo(-l * 0.58, -l * 0.12)
    ..quadraticBezierTo(-l * 0.54, 0, -l * 0.6, l * 0.1)
    ..lineTo(-l * 0.42, l * 0.03)
    ..cubicTo(-l * 0.1, l * 0.12, l * 0.3, l * 0.1, l * 0.55, l * 0.02)
    ..close();
  final fin = Path()
    ..moveTo(l * 0.02, -l * 0.13)
    ..quadraticBezierTo(-l * 0.02, -l * 0.3, -l * 0.14, -l * 0.27)
    ..quadraticBezierTo(-l * 0.08, -l * 0.18, -l * 0.12, -l * 0.12)
    ..close();
  final flipper = Path()
    ..moveTo(l * 0.15, l * 0.06)
    ..quadraticBezierTo(l * 0.08, l * 0.2, -l * 0.02, l * 0.2)
    ..quadraticBezierTo(l * 0.04, l * 0.1, l * 0.02, l * 0.07)
    ..close();
  final rect = Rect.fromLTRB(-l * 0.6, -l * 0.3, l * 0.6, l * 0.2);
  final colors = night ? const [Color(0xFF9FB8E0), Color(0xFF4A6A9A), Color(0xFF223A60)] : const [Color(0xFFE6F2FF), Color(0xFF8FB4DA), Color(0xFF4F78A8)];
  final paint = _linear(rect, colors, stops: const [0, 0.5, 1]);
  canvas.drawPath(fin, paint);
  canvas.drawPath(body, paint);
  canvas.drawPath(flipper, Paint()..color = colors[2]);
  // The pale belly and the shine on the back.
  canvas.save();
  canvas.clipPath(body);
  canvas.drawOval(Rect.fromLTRB(-l * 0.35, l * 0.0, l * 0.5, l * 0.14), Paint()..color = _white.withValues(alpha: 0.6));
  canvas.drawOval(Rect.fromLTRB(-l * 0.2, -l * 0.15, l * 0.35, -l * 0.07), Paint()..color = _white.withValues(alpha: 0.65));
  canvas.restore();
  canvas.drawCircle(Offset(l * 0.36, -l * 0.04), l * 0.014, Paint()..color = const Color(0xFF102030));
  canvas.restore();
}

/// A butterfly of blue glass, wings a little open.
void butterfly(Canvas canvas, Offset at, double size, {Color color = const Color(0xFF3AA8FF), double turn = 0}) {
  canvas.save();
  canvas.translate(at.dx, at.dy);
  canvas.rotate(turn);
  for (final side in [-1.0, 1.0]) {
    final upper = Path()
      ..moveTo(0, 0)
      ..cubicTo(side * size * 0.2, -size * 0.7, side * size * 0.95, -size * 0.75, side * size * 0.8, -size * 0.15)
      ..quadraticBezierTo(side * size * 0.5, size * 0.05, 0, 0)
      ..close();
    final lower = Path()
      ..moveTo(0, size * 0.02)
      ..cubicTo(side * size * 0.55, size * 0.05, side * size * 0.6, size * 0.55, side * size * 0.25, size * 0.5)
      ..quadraticBezierTo(side * size * 0.05, size * 0.4, 0, size * 0.02)
      ..close();
    for (final wing in [lower, upper]) {
      final b = wing.getBounds();
      canvas.drawPath(wing, _radial(b, [Color.lerp(color, _white, 0.6)!.withValues(alpha: 0.85), color.withValues(alpha: 0.8), Color.lerp(color, const Color(0xFF001A50), 0.4)!.withValues(alpha: 0.95)], center: Alignment(-side * 0.6, 0.6), radius: 1));
      canvas.drawPath(wing, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, size * 0.03)
        ..color = _white.withValues(alpha: 0.6));
    }
  }
  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, size * 0.1), width: size * 0.09, height: size * 0.6), Radius.circular(size)), Paint()..color = Color.lerp(color, const Color(0xFF001A50), 0.5)!);
  canvas.restore();
}

/// A tuft of soft coral: rounded branches with glossy tips.
void coral(Canvas canvas, Offset foot, double size, Color color, math.Random random) {
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = color;
  void branch(Offset from, double angle, double length, int depth) {
    final to = from + Offset(math.cos(angle), math.sin(angle)) * length;
    paint.strokeWidth = size * 0.11 * (1 + depth * 0.3);
    final bend = Offset(math.cos(angle + 0.5), math.sin(angle + 0.5)) * length * 0.15;
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo((from.dx + to.dx) / 2 + bend.dx, (from.dy + to.dy) / 2 + bend.dy, to.dx, to.dy);
    canvas.drawPath(path, paint);
    if (depth == 0) {
      gelOrb(canvas, to, size * 0.075, Color.lerp(color, _white, 0.25)!);
      return;
    }
    branch(to, angle - 0.45 - random.nextDouble() * 0.35, length * 0.75, depth - 1);
    branch(to, angle + 0.45 + random.nextDouble() * 0.35, length * 0.75, depth - 1);
  }

  paint.style = PaintingStyle.stroke;
  branch(foot, -math.pi / 2 + (random.nextDouble() - 0.5) * 0.4, size * 0.32, 2);
}

/// Where water meets air, seen from the side: the surface line rolling,
/// lit along its crest, with spray thrown up and droplets above it. Below
/// it, [water] fills down to the bottom.
void waterline(Canvas canvas, Size size, double level, math.Random random, {required List<Color> water, bool night = false}) {
  final crest = <Offset>[];
  for (var i = 0; i <= 160; i++) {
    final x = size.width * i / 160;
    final u = x / size.width * math.pi * 2;
    crest.add(Offset(x, level + math.sin(u * 1.6 + 0.7) * size.height * 0.018 + math.sin(u * 4.3 + 2) * size.height * 0.008));
  }
  final body = Path()..moveTo(0, size.height);
  for (final p in crest) {
    body.lineTo(p.dx, p.dy);
  }
  body
    ..lineTo(size.width, size.height)
    ..close();
  final below = Rect.fromLTRB(0, level - size.height * 0.03, size.width, size.height);
  canvas.drawPath(body, _linear(below, water.map((c) => c.withValues(alpha: c.a * 0.94)).toList()));
  canvas.save();
  canvas.clipPath(body);
  // Light dancing on the floor of the water.
  final caustic = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = _white.withValues(alpha: night ? 0.08 : 0.22)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
  for (var i = 0; i < 70; i++) {
    final c = Offset(random.nextDouble() * size.width, level + random.nextDouble() * (size.height - level));
    final w = 14 + random.nextDouble() * 34;
    canvas.drawOval(Rect.fromCenter(center: c, width: w, height: w * 0.45), caustic);
  }
  // Just under the surface: a bright band.
  canvas.drawRect(Rect.fromLTRB(0, level - size.height * 0.03, size.width, level + size.height * 0.06),
      _linear(Rect.fromLTRB(0, level - size.height * 0.03, size.width, level + size.height * 0.06), [_white.withValues(alpha: night ? 0.2 : 0.55), _white.withValues(alpha: 0)]));
  canvas.restore();
  // The crest: a bright edge, then a softer glow over it.
  canvas.drawPath(Path()..addPolygon(crest, false), Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 7
    ..color = _white.withValues(alpha: night ? 0.2 : 0.55)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
  canvas.drawPath(Path()..addPolygon(crest, false), Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8
    ..color = _white.withValues(alpha: night ? 0.5 : 0.95));
  // Spray: thin arcs of droplets thrown up from a few points.
  for (var s = 0; s < 4; s++) {
    final from = crest[(20 + random.nextInt(120))];
    for (var k = 0; k < 14; k++) {
      final a = -math.pi / 2 + (random.nextDouble() - 0.5) * 1.6;
      final d = size.height * (0.02 + random.nextDouble() * 0.07);
      final r = 1.5 + random.nextDouble() * 4.5;
      final c = from + Offset(math.cos(a), math.sin(a)) * d;
      canvas.drawCircle(c, r, _radial(Rect.fromCircle(center: c, radius: r), [_white.withValues(alpha: 0.2), _white.withValues(alpha: night ? 0.35 : 0.85)], stops: const [0.3, 1]));
      canvas.drawCircle(c - Offset(r * 0.3, r * 0.35), r * 0.28, Paint()..color = _white);
    }
  }
}

/// A round gel ball, coloured right through, as candy-like buttons were.
void gelOrb(Canvas canvas, Offset c, double r, Color color) {
  final rect = Rect.fromCircle(center: c, radius: r);
  canvas.drawCircle(c + Offset(r * 0.05, r * 0.12), r, Paint()
    ..color = Color.lerp(color, const Color(0xFF002010), 0.6)!.withValues(alpha: 0.3)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12));
  canvas.drawCircle(c, r, _radial(rect, [Color.lerp(color, _white, 0.55)!, color, Color.lerp(color, const Color(0xFF002A10), 0.45)!], center: const Alignment(0.1, 0.35), radius: 0.75));
  gloss(canvas, c, r);
}
