import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../skins/skin.dart';
import 'theme.dart';

/// Paints one [SkinPaint] layer (not pictures, which [SkinLayers] shows as
/// widgets) into [rect].
void paintSkinLayer(Canvas canvas, Rect rect, SkinPaint layer) {
  switch (layer) {
    case SolidPaint(:final color):
      canvas.drawRect(rect, Paint()..color = color);
    case LinearPaint():
      canvas.drawRect(rect, Paint()..shader = layer.gradient.createShader(rect));
    case RadialPaint(:final center, :final radius, :final colors, :final stops):
      final c = Offset(rect.left + rect.width * center.dx, rect.top + rect.height * center.dy);
      final r = math.max(1.0, math.max(rect.width, rect.height) * radius);
      canvas.drawRect(rect, Paint()..shader = RadialGradient(colors: colors, stops: stops).createShader(Rect.fromCircle(center: c, radius: r)));
    case PatternPaint():
      _paintPattern(canvas, rect, layer);
    case ImagePaint():
      break;
  }
}

void _paintPattern(Canvas canvas, Rect rect, PatternPaint p, {Shader? fade}) {
  final paint = Paint()
    ..color = p.color
    ..isAntiAlias = false;
  if (fade != null) paint.shader = fade;
  final step = p.spacing;
  final size = p.size;
  canvas.save();
  canvas.clipRect(rect);
  if (p.angle != 0) {
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(p.angle * math.pi / 180);
    canvas.translate(-rect.center.dx, -rect.center.dy);
  }
  // Rotated patterns cover the box's diagonal.
  final cover = p.angle == 0 ? rect : Rect.fromCenter(center: rect.center, width: rect.longestSide * 1.5, height: rect.longestSide * 1.5);
  switch (p.type) {
    case 'lines' || 'scanlines':
      for (var y = cover.top; y < cover.bottom; y += step) {
        canvas.drawRect(Rect.fromLTWH(cover.left, y, cover.width, size), paint);
      }
    case 'grid':
      for (var y = cover.top; y < cover.bottom; y += step) {
        canvas.drawRect(Rect.fromLTWH(cover.left, y, cover.width, size), paint);
      }
      for (var x = cover.left; x < cover.right; x += step) {
        canvas.drawRect(Rect.fromLTWH(x, cover.top, size, cover.height), paint);
      }
    case 'dots':
      final points = <Offset>[];
      for (var y = cover.top; y < cover.bottom; y += step) {
        for (var x = cover.left; x < cover.right; x += step) {
          points.add(Offset(x, y));
        }
      }
      canvas.drawPoints(PointMode.points, points, paint..strokeWidth = size);
    case 'stitch':
      // Dashed seams [spacing] in from the top and bottom, as on leather.
      final dash = math.max(2.0, size * 3);
      for (final y in [rect.top + step, rect.bottom - step - size]) {
        for (var x = rect.left + step; x < rect.right - step; x += dash * 2) {
          canvas.drawRect(Rect.fromLTWH(x, y, math.min(dash, rect.right - step - x), size), paint);
        }
      }
    case 'grain':
      // Uneven lines, as the grain of wood.
      final random = math.Random(7);
      for (var y = cover.top; y < cover.bottom; y += step * (0.5 + random.nextDouble())) {
        final alpha = 0.35 + random.nextDouble() * 0.65;
        canvas.drawRect(Rect.fromLTWH(cover.left, y, cover.width, size * (0.6 + random.nextDouble() * 0.8)), Paint()
          ..color = p.color.withValues(alpha: p.color.a * alpha)
          ..shader = fade);
      }
    case 'checker':
      final path = Path();
      var row = 0;
      for (var y = cover.top; y < cover.bottom; y += step, row++) {
        for (var x = cover.left + (row.isOdd ? step : 0); x < cover.right; x += step * 2) {
          path.addRect(Rect.fromLTWH(x, y, step, step));
        }
      }
      canvas.drawPath(path, paint);
  }
  canvas.restore();
}

/// A box drawn as a [SkinSurface]: shadow, glow, fill, shine, bevel and
/// border, inside [radius] unless the surface sets its own.
class SurfaceDecoration extends Decoration {
  const SurfaceDecoration(this.surface, {this.radius = 0, this.warmth});
  final SkinSurface surface;
  final double radius;
  /// 护眼暖色's tint, multiplied into everything drawn.
  final Color? warmth;

  /// [surface] in [context]'s 护眼暖色.
  factory SurfaceDecoration.of(BuildContext context, SkinSurface surface, {double radius = 0}) =>
      SurfaceDecoration(surface, radius: radius, warmth: context.pictureWarmth);

  double get _radius => surface.radius ?? radius;

  @override
  EdgeInsetsGeometry get padding => EdgeInsets.all(surface.bevel != null ? surface.bevel!.width * (surface.bevel!.innerLight != null ? 2 : 1) : 0);

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) => Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(_radius)));

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) => true;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _SurfacePainter(this);

  @override
  bool operator ==(Object other) => other is SurfaceDecoration && identical(other.surface, surface) && other.radius == radius && other.warmth == warmth;

  @override
  int get hashCode => Object.hash(identityHashCode(surface), radius, warmth);
}

class _SurfacePainter extends BoxPainter {
  _SurfacePainter(this.decoration);
  final SurfaceDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final rect = offset & size;
    if (decoration.warmth case final tint?) {
      canvas.saveLayer(rect.inflate(24), Paint()..colorFilter = ColorFilter.mode(tint, BlendMode.modulate));
      paintSurface(canvas, rect, decoration.surface, decoration._radius);
      canvas.restore();
    } else {
      paintSurface(canvas, rect, decoration.surface, decoration._radius);
    }
  }
}

/// Paints [s] into [rect] with corners of [radius].
void paintSurface(Canvas canvas, Rect rect, SkinSurface s, double radius) {
  final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
  for (final shadow in s.shadows) {
    canvas.drawRRect(rrect.shift(shadow.offset).inflate(shadow.spreadRadius), shadow.toPaint());
  }
  if (s.glow case final glow?) {
    canvas.drawRRect(rrect.inflate(1), Paint()
      ..color = glow
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10));
  }
  canvas.save();
  if (radius > 0) canvas.clipRRect(rrect);
  for (final layer in s.fill) {
    paintSkinLayer(canvas, rect, layer);
  }
  if (s.gloss > 0) {
    // The shine of gel: a white wash over the top half, brightest at the top.
    // Rounded gel keeps the shine off its curved sides; a square bar is lit
    // edge to edge, or its ends look a different colour.
    final inset = radius <= 0 ? 0.0 : math.min(rect.width * 0.04, radius);
    final shine = Rect.fromLTRB(rect.left + inset, rect.top + 1, rect.right - inset, rect.top + rect.height * 0.5);
    final r = math.min(radius, shine.height);
    canvas.drawRRect(
      RRect.fromRectAndCorners(shine, topLeft: Radius.circular(r), topRight: Radius.circular(r), bottomLeft: Radius.circular(r * 0.5), bottomRight: Radius.circular(r * 0.5)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.9 * s.gloss), Colors.white.withValues(alpha: 0.12 * s.gloss)],
        ).createShader(shine),
    );
  }
  if (s.bevel case final b?) _paintBevel(canvas, rect, b);
  canvas.restore();
  if (s.border case final color?) {
    final w = s.borderWidth;
    final paint = Paint()..color = color;
    final sides = s.borderSides;
    if (sides == null) {
      canvas.drawRRect(rrect.deflate(w / 2), Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w);
    } else {
      if (sides.contains('top')) canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, w), paint);
      if (sides.contains('bottom')) canvas.drawRect(Rect.fromLTWH(rect.left, rect.bottom - w, rect.width, w), paint);
      if (sides.contains('left')) canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, w, rect.height), paint);
      if (sides.contains('right')) canvas.drawRect(Rect.fromLTWH(rect.right - w, rect.top, w, rect.height), paint);
    }
  }
}

void _paintBevel(Canvas canvas, Rect rect, SkinBevel b) {
  void edge(Rect r, double w, Color topLeft, Color bottomRight) {
    final light = Paint()
      ..color = topLeft
      ..isAntiAlias = false;
    final dark = Paint()
      ..color = bottomRight
      ..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width, w), light);
    canvas.drawRect(Rect.fromLTWH(r.left, r.top, w, r.height), light);
    canvas.drawRect(Rect.fromLTWH(r.left, r.bottom - w, r.width, w), dark);
    canvas.drawRect(Rect.fromLTWH(r.right - w, r.top, w, r.height), dark);
  }

  final w = b.width;
  final (outerLight, outerDark) = b.sunk ? (b.dark, b.light) : (b.light, b.dark);
  edge(rect, w, outerLight, outerDark);
  if (b.innerLight != null && b.innerDark != null) {
    final (innerLight, innerDark) = b.sunk ? (b.innerDark!, b.innerLight!) : (b.innerLight!, b.innerDark!);
    edge(rect.deflate(w), w, innerLight, innerDark);
  }
}

/// [SkinPaint] layers filling their box, pictures included.
class SkinLayers extends StatelessWidget {
  const SkinLayers(this.layers, {super.key});
  final List<SkinPaint> layers;

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        for (final layer in layers)
          if (layer is ImagePaint)
            Opacity(
              opacity: layer.opacity,
              child: Image(
                image: layer.builtIn ? AssetImage(layer.path) as ImageProvider : FileImage(File(layer.path)),
                fit: switch (layer.fit) {
                  'contain' => BoxFit.contain,
                  'fill' => BoxFit.fill,
                  'tile' => BoxFit.none,
                  _ => BoxFit.cover,
                },
                repeat: layer.fit == 'tile' ? ImageRepeat.repeat : ImageRepeat.noRepeat,
                alignment: layer.fit == 'tile' ? Alignment.topLeft : Alignment.center,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            )
          else
            CustomPaint(painter: _LayerPainter(layer)),
      ]);
}

class _LayerPainter extends CustomPainter {
  _LayerPainter(this.layer);
  final SkinPaint layer;

  @override
  void paint(Canvas canvas, Size size) => paintSkinLayer(canvas, Offset.zero & size, layer);

  @override
  bool shouldRepaint(_LayerPainter old) => !identical(old.layer, layer);
}

/// The window's background and ornaments under [child], and those meant
/// to lie over everything above it.
/// Under 低占用模式 ([plain]) the ornaments are left out. 护眼暖色 tints
/// it all like the video.
class SkinBackdrop extends StatelessWidget {
  const SkinBackdrop({super.key, required this.skin, required this.child, this.plain = false});
  final Skin skin;
  final Widget child;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final decorations = plain ? const <SkinDecoration>[] : skin.decorations;
    final below = decorations.where((d) => !d.above).toList();
    final above = decorations.where((d) => d.above).toList();
    final warmth = context.pictureWarmth;
    Widget warm(Widget child) => warmth == null ? child : ColorFiltered(colorFilter: ColorFilter.mode(warmth, BlendMode.modulate), child: child);
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(child: warm(Stack(fit: StackFit.expand, children: [
        // Pure black in dark mode replaces the page of a skin that follows
        // the theme mode, as it does Lumtub's own.
        ColoredBox(color: skin.followsThemeMode && Theme.of(context).colorScheme.surface == Colors.black ? Colors.black : skin.colors.page),
        if (skin.background.isNotEmpty) SkinLayers(skin.background),
        if (below.isNotEmpty) CustomPaint(painter: SkinDecorationPainter(below)),
      ]))),
      child,
      if (above.isNotEmpty) IgnorePointer(child: RepaintBoundary(child: warm(CustomPaint(painter: SkinDecorationPainter(above))))),
    ]);
  }
}

/// A box drawn as [surface] (or nothing when null) round [child].
class SkinBox extends StatelessWidget {
  const SkinBox({super.key, required this.surface, this.radius = 0, this.padding, required this.child});
  final SkinSurface? surface;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = surface;
    if (s == null) return padding == null ? child : Padding(padding: padding!, child: child);
    return DecoratedBox(
      decoration: SurfaceDecoration.of(context, s, radius: radius),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}

class SkinDecorationPainter extends CustomPainter {
  SkinDecorationPainter(this.decorations);
  final List<SkinDecoration> decorations;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    for (final d in decorations) {
      switch (d) {
        case BubblesDecoration():
          _bubbles(canvas, size, d);
        case SparklesDecoration():
          _sparkles(canvas, size, d);
        case PerspectiveGridDecoration():
          _perspectiveGrid(canvas, size, d);
        case BeamDecoration():
          _beam(canvas, size, d);
        case WavesDecoration():
          _waves(canvas, size, d);
        case PatternDecoration(:final paint, :final fade):
          final shader = switch (fade) {
            'top' => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [paint.color.withValues(alpha: 0), paint.color]).createShader(rect),
            'bottom' => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [paint.color, paint.color.withValues(alpha: 0)]).createShader(rect),
            _ => null,
          };
          _paintPattern(canvas, rect, paint, fade: shader);
      }
    }
  }

  void _bubbles(Canvas canvas, Size size, BubblesDecoration d) {
    final random = math.Random(d.seed);
    for (var i = 0; i < d.count; i++) {
      // Bubbles keep to the edges, where the content is thinnest.
      final edge = random.nextBool();
      // The left edge holds the side rail's labels, so bubbles there sit
      // just to its right.
      final x = edge ? (random.nextBool() ? 0.08 + random.nextDouble() * 0.08 : 0.88 + random.nextDouble() * 0.12) : 0.08 + random.nextDouble() * 0.92;
      final y = edge ? random.nextDouble() : (random.nextBool() ? random.nextDouble() * 0.15 : 0.85 + random.nextDouble() * 0.15);
      final r = 8 + random.nextDouble() * 40;
      final c = Offset(x * size.width, y * size.height);
      final circle = Rect.fromCircle(center: c, radius: r);
      canvas.drawCircle(c, r, Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, d.tint, Colors.white.withValues(alpha: 0.75)],
          stops: const [0.58, 0.82, 1],
        ).createShader(circle));
      canvas.drawCircle(c + Offset(-r * 0.35, -r * 0.4), r * 0.18, Paint()
        ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.95), Colors.white.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c + Offset(-r * 0.35, -r * 0.4), radius: r * 0.18)));
    }
  }

  void _sparkles(Canvas canvas, Size size, SparklesDecoration d) {
    final random = math.Random(d.seed);
    for (var i = 0; i < d.count; i++) {
      final c = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height * 0.6);
      final r = 4 + random.nextDouble() * 7;
      final path = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
        ..close();
      if (d.glow case final glow?) {
        canvas.drawPath(path, Paint()
          ..color = glow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      }
      canvas.drawPath(path, Paint()..color = d.color);
    }
  }

  void _perspectiveGrid(Canvas canvas, Size size, PerspectiveGridDecoration d) {
    final horizon = size.height * d.horizon;
    final floor = Rect.fromLTRB(0, horizon, size.width, size.height);
    final paint = Paint()
      ..strokeWidth = 1
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [d.color.withValues(alpha: 0), d.color]).createShader(floor);
    final vanish = Offset(size.width / 2, horizon);
    final lines = (size.width / d.spacing).ceil() * 3;
    for (var i = -lines; i <= lines; i++) {
      canvas.drawLine(vanish, Offset(size.width / 2 + i * d.spacing * 2, size.height), paint);
    }
    // Rows close up towards the horizon.
    for (var t = 1.0; t > 0.02; t *= 0.78) {
      final y = horizon + (size.height - horizon) * t;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _waves(Canvas canvas, Size size, WavesDecoration d) {
    final random = math.Random(d.seed);
    for (var i = 0; i < d.count; i++) {
      final base = size.height * d.position + (random.nextDouble() - 0.5) * size.height * 0.2;
      final amplitude = size.height * (0.04 + random.nextDouble() * 0.06);
      final thickness = size.height * (0.05 + random.nextDouble() * 0.08);
      final phase = random.nextDouble() * math.pi * 2;
      final turns = 0.6 + random.nextDouble() * 0.8;
      double y(double x, double shift) => base + shift + math.sin(x / size.width * math.pi * 2 * turns + phase) * amplitude;
      const steps = 48;
      final top = Path()..moveTo(0, y(0, 0));
      final ribbon = Path()..moveTo(0, y(0, 0));
      for (var s = 1; s <= steps; s++) {
        final x = size.width * s / steps;
        top.lineTo(x, y(x, 0));
        ribbon.lineTo(x, y(x, 0));
      }
      for (var s = steps; s >= 0; s--) {
        final x = size.width * s / steps;
        ribbon.lineTo(x, y(x, thickness * (0.6 + 0.4 * math.cos(x / size.width * math.pi + phase))));
      }
      ribbon.close();
      final bounds = Rect.fromLTRB(0, base - amplitude, size.width, base + amplitude + thickness);
      canvas.drawPath(ribbon, Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [d.color, d.color.withValues(alpha: 0)],
        ).createShader(bounds));
      canvas.drawPath(top, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.7));
    }
  }

  void _beam(Canvas canvas, Size size, BeamDecoration d) {
    canvas.save();
    final center = Offset(size.width / 2, size.height * d.position);
    canvas.translate(center.dx, center.dy);
    canvas.rotate(d.angle * math.pi / 180);
    final band = Rect.fromCenter(center: Offset.zero, width: size.longestSide * 1.6, height: size.height * 0.4);
    canvas.drawRect(band, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [d.color.withValues(alpha: 0), d.color.withValues(alpha: d.color.a * 0.4), d.color, d.color.withValues(alpha: d.color.a * 0.4), d.color.withValues(alpha: 0)],
        stops: const [0.3, 0.47, 0.5, 0.53, 0.7],
      ).createShader(band));
    canvas.restore();
  }

  @override
  bool shouldRepaint(SkinDecorationPainter old) => !identical(old.decorations, decorations);
}
