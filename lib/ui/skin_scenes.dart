import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show PointMode;

import 'package:material_ui/material_ui.dart';

import 'scene_props.dart';
import 'skin_paint.dart' show noiseShader;

/// Landscapes painted behind a skin: a meadow under the sky, the open sky,
/// the sea seen from under water, and northern lights over mountains. Each
/// has a day and a night version. They are drawn once for each size and
/// kept as a picture, so scrolling and hovering never paint them again.
enum SkinScene {
  meadow,
  sky,
  underwater,
  aurora,
  city,
  collage,
  dunes;

  static final _byName = {for (final s in values) s.name: s};
  static SkinScene? byName(String? name) => _byName[name];
}

/// The colours a scene is made of, for checking what is read over it.
List<Color> sceneTones(SkinScene scene, {required bool night}) => switch ((scene, night)) {
      (SkinScene.meadow, false) => [..._MeadowDay.sky, ..._MeadowDay.hills.expand((h) => h)],
      (SkinScene.meadow, true) => [..._MeadowNight.sky, ..._MeadowNight.hills.expand((h) => h)],
      (SkinScene.sky, false) => [..._SkyDay.sky],
      (SkinScene.sky, true) => [..._SkyNight.sky],
      (SkinScene.underwater, false) => [..._SeaDay.water],
      (SkinScene.underwater, true) => [..._SeaNight.water],
      (SkinScene.aurora, _) => [..._Aurora.sky],
      (SkinScene.city, false) => [..._MeadowDay.sky, ..._MeadowDay.hills.expand((h) => h), ..._City.glassDay],
      (SkinScene.city, true) => [..._MeadowNight.sky, ..._MeadowNight.hills.expand((h) => h), ..._City.glassNight],
      (SkinScene.collage, false) => [..._Collage.day, ..._Collage.props],
      (SkinScene.collage, true) => [..._Collage.night, ..._Collage.propsNight],
      (SkinScene.dunes, false) => [..._DunesDay.sky, ..._DunesDay.dunes.expand((d) => d)],
      (SkinScene.dunes, true) => [..._DunesNight.sky, ..._DunesNight.dunes.expand((d) => d)],
    };

class ScenePainter extends CustomPainter {
  ScenePainter(this.scene, {required this.night, this.seed = 1});
  final SkinScene scene;
  final bool night;
  final int seed;

  /// Pictures by scene and size; the last flag says whether the size is a
  /// [step] one, stretched while the window is being resized.
  static final _cache = <(SkinScene, bool, int, int, int, bool), ui.Picture>{};

  /// While the window is being resized, scenes are recorded in steps of
  /// this many pixels and stretched the little rest of the way, so a
  /// resize records one only now and then, not at every size it passes
  /// through. Once the size has rested for [settle], the scene is
  /// recorded at its exact size: a still window never shows it stretched.
  static const step = 64;
  static const settle = Duration(milliseconds: 200);

  /// Tells whoever paints scenes to paint again once a resize has rested.
  static final settled = ValueNotifier<int>(0);

  static final _sincePaint = Stopwatch();
  static (int, int)? _lastSize;
  static (int, int)? _restedSize;
  static Timer? _settling;

  /// How many scenes have been recorded, for tests.
  @visibleForTesting
  static int recordings = 0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final exact = (size.width.round(), size.height.round());
    final resizing = _lastSize != null && _lastSize != exact && _sincePaint.isRunning && _sincePaint.elapsed < settle;
    _lastSize = exact;
    _sincePaint
      ..reset()
      ..start();
    final kept = _cache.remove((scene, night, seed, exact.$1, exact.$2, false));
    if (kept != null || !resizing || _restedSize == exact) {
      _draw(canvas, size, kept, exact, stepped: false);
      return;
    }
    final stepped = ((size.width / step).ceil() * step, (size.height / step).ceil() * step);
    _draw(canvas, size, _cache.remove((scene, night, seed, stepped.$1, stepped.$2, true)), stepped, stepped: true);
    _settling?.cancel();
    _settling = Timer(settle, () {
      _restedSize = exact;
      settled.value++;
    });
  }

  void _draw(Canvas canvas, Size size, ui.Picture? picture, (int, int) at, {required bool stepped}) {
    final width = at.$1, height = at.$2;
    if (picture == null) {
      final recorded = Size(width.toDouble(), height.toDouble());
      recordings++;
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder);
      final random = math.Random(seed);
      switch (scene) {
        case SkinScene.meadow:
          _meadow(c, recorded, random, night);
        case SkinScene.sky:
          _sky(c, recorded, random, night);
        case SkinScene.underwater:
          _underwater(c, recorded, random, night);
        case SkinScene.aurora:
          _aurora(c, recorded, random);
        case SkinScene.city:
          _city(c, recorded, random, night);
        case SkinScene.collage:
          _collage(c, recorded, random, night);
        case SkinScene.dunes:
          _dunes(c, recorded, random, night);
      }
      picture = recorder.endRecording();
      // A window is one size at a time; keep a few for resizing back,
      // dropping the one used longest ago.
      if (_cache.length > 6) _cache.remove(_cache.keys.first)?.dispose();
    }
    _cache[(scene, night, seed, width, height, stepped)] = picture;
    canvas.save();
    canvas.scale(size.width / width, size.height / height);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ScenePainter old) => old.scene != scene || old.night != night || old.seed != seed;
}

// ── Shared pieces ──────────────────────────────────────────────────────────

void _verticalGradient(Canvas canvas, Rect rect, List<Color> colors, [List<double>? stops]) {
  canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors, stops: stops).createShader(rect));
}

void _glow(Canvas canvas, Offset center, double radius, Color color) {
  final rect = Rect.fromCircle(center: center, radius: radius);
  canvas.drawCircle(center, radius, Paint()..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(rect));
}

Path _below(List<Offset> ridge, Size size) {
  final path = Path()..moveTo(ridge.first.dx, size.height);
  for (final p in ridge) {
    path.lineTo(p.dx, p.dy);
  }
  return path
    ..lineTo(ridge.last.dx, size.height)
    ..close();
}

/// A heaped cloud: a dome of overlapping puffs over a row of smaller ones,
/// lit white from above and shading softly towards its base.
void _cloud(Canvas canvas, Offset at, double width, math.Random random, {required Color light, required Color shade, double opacity = 1}) {
  final puffs = <(Offset, double)>[];
  final count = 5 + random.nextInt(4);
  for (var i = 0; i < count; i++) {
    final t = count == 1 ? 0.5 : i / (count - 1);
    final r = width * (0.1 + 0.17 * math.sin((0.15 + t * 0.7) * math.pi)) * (0.85 + random.nextDouble() * 0.3);
    puffs.add((Offset(at.dx - width * 0.38 + width * 0.76 * t, at.dy - r * (0.55 + random.nextDouble() * 0.25)), r));
  }
  // The rounded base.
  for (var i = 0; i < 7; i++) {
    final t = i / 6;
    final r = width * 0.085 * (0.8 + random.nextDouble() * 0.3);
    puffs.add((Offset(at.dx - width * 0.42 + width * 0.84 * t, at.dy - r * 0.2), r));
  }
  final bounds = Rect.fromLTRB(at.dx - width * 0.6, at.dy - width * 0.42, at.dx + width * 0.6, at.dy + width * 0.1);
  canvas.saveLayer(bounds.inflate(24), Paint()..color = Colors.white.withValues(alpha: opacity));
  final body = Path();
  for (final (c, r) in puffs) {
    body.addOval(Rect.fromCircle(center: c, radius: r));
  }
  canvas.drawPath(
    body,
    Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [light, light, shade], stops: const [0, 0.5, 1]).createShader(bounds)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.012),
  );
  // Each puff's lit crown.
  for (final (c, r) in puffs.take(count)) {
    final top = Rect.fromCircle(center: c - Offset(r * 0.12, r * 0.28), radius: r * 0.7);
    canvas.drawCircle(top.center, top.width / 2, Paint()..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0)]).createShader(top));
  }
  canvas.restore();
}

void _stars(Canvas canvas, Size size, math.Random random, {required double down, int count = 160}) {
  for (var i = 0; i < count; i++) {
    final p = Offset(random.nextDouble() * size.width, math.pow(random.nextDouble(), 1.4) * size.height * down);
    final big = random.nextDouble() < 0.08;
    final r = big ? 1.3 + random.nextDouble() : 0.4 + random.nextDouble() * 0.7;
    final a = 0.35 + random.nextDouble() * 0.65;
    if (big) _glow(canvas, p, r * 5, Colors.white.withValues(alpha: 0.18 * a));
    canvas.drawCircle(p, r, Paint()..color = Color.lerp(Colors.white, const Color(0xFFBFD8FF), random.nextDouble())!.withValues(alpha: a));
  }
}

void _moon(Canvas canvas, Offset at, double r) {
  _glow(canvas, at, r * 7, const Color(0x33D8E6FF));
  _glow(canvas, at, r * 2.6, const Color(0x40EEF4FF));
  canvas.drawCircle(at, r, Paint()..color = const Color(0xFFF4F1E4));
  // Seas on its face.
  for (final (dx, dy, s) in const [(-0.3, -0.2, 0.28), (0.25, 0.15, 0.22), (-0.05, 0.38, 0.16)]) {
    canvas.drawCircle(at + Offset(dx * r, dy * r), s * r, Paint()
      ..color = const Color(0x22707A88)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06));
  }
}

// ── The glossy toolkit of the look: light swooshes, bokeh, flares, gloss ──

/// A sweeping ribbon of light across the picture, thick in the middle and
/// thin at both ends, with a bright edge along its top.
void _swoosh(Canvas canvas, Size size, List<Offset> controls, {required Color color, required double thickness, double edge = 0.8}) {
  Offset at(double t) {
    final u = 1 - t;
    final (p0, p1, p2, p3) = (controls[0], controls[1], controls[2], controls[3]);
    return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t);
  }

  const steps = 80;
  final top = <Offset>[], bottom = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final p = at(t);
    final next = at(math.min(1, t + 0.01)), prev = at(math.max(0, t - 0.01));
    final d = next - prev;
    final n = Offset(-d.dy, d.dx) / math.max(0.0001, d.distance);
    final w = thickness * math.pow(math.sin(t * math.pi), 0.8);
    top.add(p - n * (w * 0.15));
    bottom.add(p + n * w);
  }
  final ribbon = Path()..addPolygon([...top, ...bottom.reversed], true);
  final bounds = ribbon.getBounds();
  canvas.drawPath(
    ribbon,
    Paint()
      ..shader = LinearGradient(colors: [color.withValues(alpha: 0), color.withValues(alpha: color.a * 0.55), color.withValues(alpha: color.a * 0.2), color.withValues(alpha: 0)], stops: const [0, 0.35, 0.75, 1]).createShader(bounds)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, thickness * 0.12),
  );
  canvas.drawPath(
    Path()..addPolygon(top, false),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = LinearGradient(colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: edge), Colors.white.withValues(alpha: 0)]).createShader(bounds)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
  );
}

/// Out-of-focus lights: soft discs, some with a brighter ring.
void _bokeh(Canvas canvas, Rect area, math.Random random, {required Color color, int count = 24, double size = 30}) {
  for (var i = 0; i < count; i++) {
    final c = Offset(area.left + random.nextDouble() * area.width, area.top + random.nextDouble() * area.height);
    final r = size * (0.3 + random.nextDouble());
    final a = 0.25 + random.nextDouble() * 0.75;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()..shader = RadialGradient(colors: [color.withValues(alpha: color.a * 0.35 * a), color.withValues(alpha: color.a * 0.55 * a), color.withValues(alpha: 0)], stops: const [0, 0.82, 1]).createShader(rect));
  }
}

/// A shining sun or lamp with a string of flare rings towards [towards].
void _flare(Canvas canvas, Offset at, Offset towards, double size, {Color tint = const Color(0xFFFFFFFF)}) {
  _glow(canvas, at, size * 4, tint.withValues(alpha: 0.35));
  _glow(canvas, at, size * 1.4, tint.withValues(alpha: 0.85));
  canvas.drawCircle(at, size * 0.35, Paint()..color = Colors.white);
  // A soft star of rays.
  for (var i = 0; i < 6; i++) {
    final a = i / 6 * math.pi;
    final d = Offset(math.cos(a), math.sin(a)) * size * 3;
    canvas.drawLine(at - d, at + d, Paint()
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
  }
  for (final (t, r, a, ring) in const [(0.35, 0.5, 0.16, false), (0.55, 0.25, 0.22, true), (0.8, 0.9, 0.08, false), (1.05, 0.35, 0.18, true), (1.3, 0.6, 0.1, false)]) {
    final p = Offset.lerp(at, towards, t)!;
    final hue = HSVColor.fromColor(tint).withHue((HSVColor.fromColor(tint).hue + t * 120) % 360).withSaturation(0.35).toColor();
    canvas.drawCircle(p, size * r, Paint()..color = hue.withValues(alpha: a));
    if (ring) {
      canvas.drawCircle(p, size * r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: a * 1.6));
    }
  }
}

/// A smooth, rounded hill shaded like polished plastic: a bright rim of
/// light along its top edge and a broad sheen where the light falls.
void _glossyHill(Canvas canvas, Size size, List<Offset> ridge, {required Color top, required Color foot, required Offset light, double shine = 0.55}) {
  final path = _below(ridge, size);
  final crest = ridge.map((p) => p.dy).reduce(math.min);
  final band = Rect.fromLTRB(0, crest, size.width, size.height);
  canvas.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, foot]).createShader(band));
  canvas.save();
  canvas.clipPath(path);
  // Where the light falls.
  _glow(canvas, Offset(light.dx, crest + (size.height - crest) * 0.1), size.width * 0.45, Colors.white.withValues(alpha: 0.25 * shine));
  // The rim: the ridge drawn again just inside, wide and soft, then narrow.
  final rim = [for (final p in ridge) p + const Offset(0, 7)];
  canvas.drawPath(Path()..addPolygon(rim, false), Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 14
    ..color = Colors.white.withValues(alpha: 0.32 * shine)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
  canvas.drawPath(Path()..addPolygon([for (final p in ridge) p + const Offset(0, 2)], false), Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..color = Colors.white.withValues(alpha: 0.6 * shine)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1));
  canvas.restore();
}

/// A drop of water or a bubble: clear in the middle, a coloured rim, a
/// bright catch light at the top and a smaller one below.
void _droplet(Canvas canvas, Offset c, double r, {Color rim = const Color(0xFFFFFFFF), bool bubble = true}) {
  final rect = Rect.fromCircle(center: c, radius: r);
  canvas.drawCircle(c, r, Paint()..shader = RadialGradient(center: const Alignment(0.2, 0.3), colors: [rim.withValues(alpha: bubble ? 0.04 : 0.25), rim.withValues(alpha: bubble ? 0.12 : 0.35), rim.withValues(alpha: 0.75)], stops: const [0, 0.75, 1]).createShader(rect));
  final hl = Rect.fromCenter(center: c + Offset(-r * 0.25, -r * 0.45), width: r * 0.95, height: r * 0.5);
  canvas.drawOval(hl, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: 0.95), Colors.white.withValues(alpha: 0)]).createShader(hl));
  canvas.drawCircle(c + Offset(r * 0.42, r * 0.5), r * 0.12, Paint()..color = Colors.white.withValues(alpha: 0.7));
}

// ── Meadow ────────────────────────────────────────────────────────────────

abstract final class _MeadowDay {
  static const sky = [Color(0xFF0F7FE0), Color(0xFF3FA9F5), Color(0xFF8FD3FF), Color(0xFFDDF4FF)];
  static const hills = [
    [Color(0xFFB4EA7A), Color(0xFF7CCB3E)],
    [Color(0xFF8EDB45), Color(0xFF4FAE1E)],
    [Color(0xFF76D02E), Color(0xFF2E8E10)],
  ];
}

abstract final class _MeadowNight {
  static const sky = [Color(0xFF040C2C), Color(0xFF0B2260), Color(0xFF16408C), Color(0xFF2A6CB0)];
  static const hills = [
    [Color(0xFF1F5A6A), Color(0xFF143E4C)],
    [Color(0xFF1A5A4A), Color(0xFF0F3A30)],
    [Color(0xFF16584A), Color(0xFF0A3028)],
  ];
}

/// Frutiger Eco: rolling glossy hills under a bright sky, a green Earth
/// resting in the grass with a sprout on top, white turbines far off, blue
/// glass butterflies and rainbow bubbles drifting up.
void _meadow(Canvas canvas, Size size, math.Random random, bool night) {
  final rect = Offset.zero & size;
  final m = math.min(size.width, size.height);
  final hills = night ? _MeadowNight.hills : _MeadowDay.hills;
  _verticalGradient(canvas, rect, night ? _MeadowNight.sky : _MeadowDay.sky, const [0, 0.3, 0.55, 0.72]);
  final light = Offset(size.width * 0.2, size.height * 0.12);
  if (night) {
    _stars(canvas, size, random, down: 0.55, count: 120);
    _moon(canvas, light, m * 0.035);
    _bokeh(canvas, Rect.fromLTRB(0, 0, size.width, size.height * 0.5), random, color: const Color(0xFF7FD8FF), count: 14, size: 26);
  } else {
    _flare(canvas, light, rect.center + Offset(size.width * 0.2, size.height * 0.15), m * 0.06, tint: const Color(0xFFFFF6D8));
    _bokeh(canvas, Rect.fromCenter(center: light, width: size.width * 0.5, height: size.height * 0.4), random, color: Colors.white, count: 12, size: 22);
  }
  for (var i = 0; i < 4; i++) {
    final w = size.width * (0.14 + random.nextDouble() * 0.12);
    final at = Offset(size.width * (0.3 + random.nextDouble() * 0.65), size.height * (0.26 + random.nextDouble() * 0.18));
    _cloud(canvas, at, w, random, light: night ? const Color(0xFF5C82C0) : Colors.white, shade: night ? const Color(0xFF2E4E8A) : const Color(0xFFD6EEFF), opacity: night ? 0.45 : 0.92);
  }
  _swoosh(canvas, size, [Offset(-size.width * 0.1, size.height * 0.42), Offset(size.width * 0.3, size.height * 0.12), Offset(size.width * 0.65, size.height * 0.5), Offset(size.width * 1.1, size.height * 0.18)],
      color: night ? const Color(0xFF6FE0FF) : Colors.white, thickness: size.height * 0.06, edge: night ? 0.5 : 0.85);
  _swoosh(canvas, size, [Offset(-size.width * 0.05, size.height * 0.2), Offset(size.width * 0.35, size.height * 0.36), Offset(size.width * 0.6, size.height * 0.05), Offset(size.width * 1.05, size.height * 0.3)],
      color: night ? const Color(0xFF9F8CFF) : const Color(0xFFE6FBFF), thickness: size.height * 0.035, edge: 0.6);
  final ridges = [
    for (var i = 0; i < hills.length; i++) _smoothRidge(size, random, base: size.height * (0.6 + i / (hills.length - 1) * 0.14), height: size.height * (0.05 + i / (hills.length - 1) * 0.03)),
  ];
  _glossyHill(canvas, size, ridges[0], top: hills[0][0], foot: hills[0][1], light: light, shine: night ? 0.35 : 0.75);
  // White turbines along the far hill.
  for (var i = 0; i < 5; i++) {
    final tx = size.width * (0.04 + i * 0.07 + random.nextDouble() * 0.03);
    final ground = ridges[0][(tx / size.width * (ridges[0].length - 1)).round()].dy;
    _turbine(canvas, Offset(tx, ground + 3), size.height * (0.09 + random.nextDouble() * 0.04), random.nextDouble() * math.pi, night: night);
  }
  for (var i = 1; i < hills.length; i++) {
    _glossyHill(canvas, size, ridges[i], top: hills[i][0], foot: hills[i][1], light: light, shine: night ? 0.35 : 0.75);
  }
  // The green Earth resting in the grass, a sprout growing from it.
  final ground = ridges.last[(0.72 * (ridges.last.length - 1)).round()].dy;
  final r = m * 0.17;
  final earth = Offset(size.width * 0.72, ground - r * 0.7);
  globe(canvas, earth, r, night: night, green: true, turn: 0.3);
  sprout(canvas, earth - Offset(-r * 0.05, r * 0.96), r * 0.6, night: night);
  // Dew drops on the grass in front.
  for (var i = 0; i < 9; i++) {
    final r = 4 + random.nextDouble() * 10;
    final c = Offset(size.width * random.nextDouble(), size.height * (0.86 + random.nextDouble() * 0.12));
    _droplet(canvas, c, r, rim: night ? const Color(0xFF8FE8FF) : Colors.white, bubble: false);
  }
  // Bubbles and butterflies in the air.
  for (var i = 0; i < 12; i++) {
    final br = 10 + math.pow(random.nextDouble(), 2) * 48;
    rainbowBubble(canvas, Offset(size.width * (0.3 + random.nextDouble() * 0.7), size.height * (0.06 + random.nextDouble() * 0.62)), br.toDouble(), opacity: night ? 0.6 : 1);
  }
  butterfly(canvas, Offset(size.width * 0.56, size.height * 0.5), m * 0.06, turn: -0.3, color: night ? const Color(0xFF6FA8FF) : const Color(0xFF2E9BFF));
  butterfly(canvas, Offset(size.width * 0.9, size.height * 0.4), m * 0.045, turn: 0.4, color: night ? const Color(0xFF8F7FFF) : const Color(0xFF4FC8FF));
}

/// Long, low swells: one or two broad waves only, as on idealised hills.
List<Offset> _smoothRidge(Size size, math.Random random, {required double base, required double height}) {
  final phase = random.nextDouble() * math.pi * 2;
  final turns = 0.5 + random.nextDouble() * 0.6;
  final phase2 = random.nextDouble() * math.pi * 2;
  return [
    for (var i = 0; i <= 120; i++)
      () {
        final x = size.width * i / 120;
        final u = x / size.width * math.pi * 2;
        return Offset(x, base - math.sin(u * turns + phase) * height - math.sin(u * turns * 2.3 + phase2) * height * 0.25);
      }(),
  ];
}

// ── Sky ───────────────────────────────────────────────────────────────────

abstract final class _SkyDay {
  static const sky = [Color(0xFF0A6FD6), Color(0xFF2D9BF0), Color(0xFF7CCBFF), Color(0xFFD4F0FF)];
}

abstract final class _SkyNight {
  static const sky = [Color(0xFF030A26), Color(0xFF071C52), Color(0xFF0F3A86), Color(0xFF1C5DAA)];
}

/// Open sky: big clouds below, ribbons of light, rainbow bubbles, glass
/// stars and a clear orb holding a little green world.
void _sky(Canvas canvas, Size size, math.Random random, bool night) {
  final rect = Offset.zero & size;
  final m = math.min(size.width, size.height);
  _verticalGradient(canvas, rect, night ? _SkyNight.sky : _SkyDay.sky, const [0, 0.35, 0.75, 1]);
  final sun = Offset(size.width * 0.82, size.height * 0.12);
  if (night) {
    _stars(canvas, size, random, down: 0.7, count: 160);
  } else {
    _flare(canvas, sun, rect.center + Offset(-size.width * 0.25, size.height * 0.15), m * 0.06, tint: const Color(0xFFFFF9E6));
  }
  for (var i = 0; i < 6; i++) {
    final w = size.width * (0.2 + random.nextDouble() * 0.18);
    final at = Offset(size.width * (i / 5) + (random.nextDouble() - 0.5) * size.width * 0.1, size.height * (0.86 + random.nextDouble() * 0.12));
    _cloud(canvas, at, w, random, light: night ? const Color(0xFF4F78BC) : Colors.white, shade: night ? const Color(0xFF223E78) : const Color(0xFFCDE8FF), opacity: night ? 0.55 : 0.95);
  }
  final ribbon = night ? const Color(0xFF5FD8FF) : Colors.white;
  _swoosh(canvas, size, [Offset(-size.width * 0.1, size.height * 0.7), Offset(size.width * 0.25, size.height * 0.25), Offset(size.width * 0.6, size.height * 0.85), Offset(size.width * 1.1, size.height * 0.35)], color: ribbon, thickness: size.height * 0.09);
  _swoosh(canvas, size, [Offset(-size.width * 0.1, size.height * 0.5), Offset(size.width * 0.3, size.height * 0.65), Offset(size.width * 0.7, size.height * 0.2), Offset(size.width * 1.1, size.height * 0.55)], color: night ? const Color(0xFF8C7CFF) : const Color(0xFFB8F0FF), thickness: size.height * 0.05, edge: 0.6);
  _swoosh(canvas, size, [Offset(-size.width * 0.1, size.height * 0.3), Offset(size.width * 0.35, size.height * 0.45), Offset(size.width * 0.55, size.height * 0.1), Offset(size.width * 1.1, size.height * 0.25)], color: ribbon, thickness: size.height * 0.025, edge: 0.7);
  _bokeh(canvas, rect, random, color: night ? const Color(0xFF7FD8FF) : Colors.white, count: 22, size: 24);
  // A clear orb with a little meadow inside, resting on the clouds.
  glassOrb(canvas, Offset(size.width * 0.8, size.height * 0.62), m * 0.13, night: night, inside: (c, box) {
    _verticalGradient(c, box, night ? _MeadowNight.sky : _MeadowDay.sky);
    final hills = night ? _MeadowNight.hills : _MeadowDay.hills;
    final inner = Size(box.width, box.height);
    c.save();
    c.translate(box.left, box.top);
    _cloud(c, Offset(inner.width * 0.35, inner.height * 0.38), inner.width * 0.4, math.Random(5), light: night ? const Color(0xFF5C82C0) : Colors.white, shade: const Color(0xFFD6EEFF), opacity: night ? 0.4 : 0.9);
    for (var i = 0; i < hills.length; i++) {
      _glossyHill(c, inner, _smoothRidge(inner, math.Random(11 + i), base: inner.height * (0.6 + i * 0.1), height: inner.height * 0.05), top: hills[i][0], foot: hills[i][1], light: Offset(inner.width * 0.3, 0), shine: 0.6);
    }
    _turbine(c, Offset(inner.width * 0.65, inner.height * 0.6), inner.height * 0.28, 0.4, night: night);
    c.restore();
  });
  // Glass stars and rainbow bubbles.
  final stars = night ? const [Color(0xFF7F9FFF), Color(0xFFB08AFF)] : const [Color(0xFF3A8CFF), Color(0xFF7AB8FF), Color(0xFF9A7AFF)];
  for (var i = 0; i < 5; i++) {
    glassStar(canvas, Offset(size.width * (0.45 + random.nextDouble() * 0.5), size.height * (0.1 + random.nextDouble() * 0.5)), m * (0.03 + random.nextDouble() * 0.035), stars[i % stars.length], turn: -math.pi / 2 + (random.nextDouble() - 0.5) * 0.6);
  }
  for (var i = 0; i < 14; i++) {
    final rr = 5 + math.pow(random.nextDouble(), 2) * 40;
    rainbowBubble(canvas, Offset(size.width * random.nextDouble(), size.height * random.nextDouble() * 0.8), rr.toDouble(), opacity: night ? 0.6 : 1);
  }
}

// ── Under water ───────────────────────────────────────────────────────────

abstract final class _SeaDay {
  static const water = [Color(0xFF7FF0F5), Color(0xFF22C4DF), Color(0xFF0A8FBF), Color(0xFF05608F)];
}

abstract final class _SeaNight {
  static const water = [Color(0xFF145A86), Color(0xFF0A3A6A), Color(0xFF062650), Color(0xFF031634)];
}

/// Frutiger Aqua: clear tropical water lit from above, a reef of soft
/// coral on white sand, tropical fish, jellyfish, a dolphin and rainbow
/// bubbles rising.
void _underwater(Canvas canvas, Size size, math.Random random, bool night) {
  final rect = Offset.zero & size;
  final m = math.min(size.width, size.height);
  final water = night ? _SeaNight.water : _SeaDay.water;
  _verticalGradient(canvas, rect, water, const [0, 0.3, 0.65, 1]);
  _verticalGradient(canvas, Rect.fromLTRB(0, 0, size.width, size.height * 0.1), night ? const [Color(0x667FD0FF), Color(0x00000000)] : const [Color(0xE6FFFFFF), Color(0x00FFFFFF)]);
  final ripple = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
  for (var i = 0; i < 30; i++) {
    final y = random.nextDouble() * size.height * 0.08;
    final x = random.nextDouble() * size.width;
    final w = 30 + random.nextDouble() * 90;
    ripple.color = Colors.white.withValues(alpha: night ? 0.15 : 0.5);
    canvas.drawArc(Rect.fromCenter(center: Offset(x, y), width: w, height: w * 0.18), 0.2, math.pi - 0.4, false, ripple);
  }
  canvas.save();
  canvas.clipRect(rect);
  final source = Offset(size.width * 0.35, -size.height * 0.3);
  canvas.saveLayer(rect, Paint()..blendMode = BlendMode.screen);
  for (var i = 0; i < 10; i++) {
    final a = math.pi / 2 + (random.nextDouble() - 0.5) * 1.1;
    final spread = 0.012 + random.nextDouble() * 0.03;
    final len = size.height * 1.4;
    final beam = Path()
      ..moveTo(source.dx, source.dy)
      ..lineTo(source.dx + math.cos(a - spread) * len, source.dy + math.sin(a - spread) * len)
      ..lineTo(source.dx + math.cos(a + spread) * len, source.dy + math.sin(a + spread) * len)
      ..close();
    canvas.drawPath(beam, Paint()
      ..shader = RadialGradient(colors: night ? const [Color(0x4096C8FF), Color(0x0096C8FF)] : const [Color(0x80FFFFFF), Color(0x00FFFFFF)]).createShader(Rect.fromCircle(center: source, radius: len))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  }
  canvas.restore();
  _swoosh(canvas, size, [Offset(-size.width * 0.1, size.height * 0.62), Offset(size.width * 0.3, size.height * 0.35), Offset(size.width * 0.65, size.height * 0.8), Offset(size.width * 1.1, size.height * 0.5)], color: night ? const Color(0xFF4FE0FF) : const Color(0xFFCFFFFF), thickness: size.height * 0.07, edge: 0.6);
  // A dolphin gliding high up, jellyfish drifting.
  dolphin(canvas, Offset(size.width * 0.3, size.height * 0.24), m * 0.32, night: night);
  jellyfish(canvas, Offset(size.width * 0.82, size.height * 0.2), m * 0.07, night: night);
  jellyfish(canvas, Offset(size.width * 0.9, size.height * 0.36), m * 0.045, night: night);
  // White sand and the reef.
  final sand = _smoothRidge(size, random, base: size.height * 0.9, height: size.height * 0.03);
  final corals = night
      ? const [Color(0xFFB0609A), Color(0xFF7A5AC0), Color(0xFFC07A50), Color(0xFF4FA0A0)]
      : const [Color(0xFFFF6FA8), Color(0xFFB07AFF), Color(0xFFFF9A4A), Color(0xFF2FD0C0)];
  for (var i = 0; i < 10; i++) {
    final x = size.width * random.nextDouble();
    final h = size.height * (0.12 + random.nextDouble() * 0.12);
    final path = Path()..moveTo(x, size.height);
    for (var k = 1; k <= 8; k++) {
      path.lineTo(x + math.sin(k * 0.9 + i) * 10, size.height - h * k / 8);
    }
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = night ? const Color(0xFF2A7A5A) : const Color(0xFF3ACB6A));
  }
  for (var i = 0; i < 9; i++) {
    final x = size.width * (i / 8) + (random.nextDouble() - 0.5) * size.width * 0.06;
    final ground = sand[(x.clamp(0, size.width) / size.width * (sand.length - 1)).round()].dy;
    coral(canvas, Offset(x, ground + 6), m * (0.1 + random.nextDouble() * 0.08), corals[i % corals.length], random);
  }
  // Round coral heads and anemones between them.
  for (var i = 0; i < 12; i++) {
    final x = size.width * random.nextDouble();
    final ground = sand[(x / size.width * (sand.length - 1)).round()].dy;
    final r = m * (0.025 + random.nextDouble() * 0.035);
    final color = corals[(i + 1) % corals.length];
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(x - r * 1.2, 0, x + r * 1.2, ground + r * 0.2));
    gelOrb(canvas, Offset(x, ground + r * 0.2), r, color);
    canvas.restore();
  }
  _glossyHill(canvas, size, sand, top: night ? const Color(0xFF6A8AA8) : const Color(0xFFFFF4D6), foot: night ? const Color(0xFF3A5470) : const Color(0xFFE6D2A2), light: Offset(size.width * 0.35, 0), shine: night ? 0.3 : 0.8);
  // Fish of the reef.
  const kinds = FishKind.values;
  for (var i = 0; i < 7; i++) {
    final at = Offset(size.width * (0.08 + random.nextDouble() * 0.84), size.height * (0.45 + random.nextDouble() * 0.35));
    tropicalFish(canvas, at, m * (0.06 + random.nextDouble() * 0.05), kinds[i % kinds.length], flip: random.nextBool(), night: night);
  }
  for (var i = 0; i < 22; i++) {
    final right = random.nextDouble() < 0.6;
    final x = right ? size.width * (0.7 + random.nextDouble() * 0.3) : size.width * random.nextDouble();
    final r = math.pow(random.nextDouble(), 2) * 30 + 3;
    rainbowBubble(canvas, Offset(x, random.nextDouble() * size.height * 0.85), r.toDouble(), opacity: night ? 0.55 : 1);
  }
  _bokeh(canvas, rect, random, color: night ? const Color(0xFF40E0FF) : Colors.white, count: 24, size: 12);
  canvas.restore();
}

// ── Northern lights ───────────────────────────────────────────────────────

abstract final class _Aurora {
  static const sky = [Color(0xFF01061A), Color(0xFF041638), Color(0xFF07285A), Color(0xFF0A3A70)];
}

void _aurora(Canvas canvas, Size size, math.Random random) {
  final rect = Offset.zero & size;
  _verticalGradient(canvas, rect, _Aurora.sky, const [0, 0.4, 0.75, 1]);
  _stars(canvas, size, random, down: 0.9, count: 200);
  // Smooth glowing veils of green, teal and violet, laid with light.
  canvas.saveLayer(rect, Paint()..blendMode = BlendMode.plus);
  final veils = [
    (const Color(0xFF3CFFA0), 0.16, 0.0),
    (const Color(0xFF22D8FF), 0.11, 0.35),
    (const Color(0xFF9A6BFF), 0.07, 0.7),
  ];
  for (final (color, thick, shift) in veils) {
    for (var k = 0; k < 2; k++) {
      final y0 = size.height * (0.2 + shift * 0.3 + k * 0.2 + random.nextDouble() * 0.08);
      final swing = size.height * (0.2 + random.nextDouble() * 0.25);
      _swoosh(canvas, size, [
        Offset(-size.width * (0.1 + random.nextDouble() * 0.2), y0 + swing * (random.nextDouble() - 0.2)),
        Offset(size.width * (0.15 + random.nextDouble() * 0.3), y0 - swing),
        Offset(size.width * (0.5 + random.nextDouble() * 0.3), y0 + swing),
        Offset(size.width * (1.05 + random.nextDouble() * 0.2), y0 - swing * random.nextDouble()),
      ], color: color, thickness: size.height * thick * (0.7 + random.nextDouble() * 0.6), edge: 0.45);
    }
  }
  // Curtain folds: fine rays rising from the brightest veil.
  final foot = <Offset>[];
  for (var i = 0; i <= 160; i++) {
    final t = i / 160;
    foot.add(Offset(size.width * t, size.height * (0.5 + 0.12 * math.sin(t * math.pi * 2.2 + 0.6) + 0.04 * math.sin(t * math.pi * 7))));
  }
  for (final p in foot) {
    final h = size.height * (0.12 + random.nextDouble() * 0.22);
    final a = 0.06 + random.nextDouble() * 0.12;
    final ray = Rect.fromLTRB(p.dx - 2.5, p.dy - h, p.dx + 2.5, p.dy);
    canvas.drawRect(ray, Paint()
      ..shader = LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [const Color(0xFF3CFFA0).withValues(alpha: a), const Color(0xFF22D8FF).withValues(alpha: a * 0.6), const Color(0xFF9A6BFF).withValues(alpha: 0)]).createShader(ray)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
  }
  canvas.restore();
  _bokeh(canvas, rect, random, color: const Color(0xFF7FFFD4), count: 22, size: 18);
  // Icy mountains, glossy as glass, and a still lake that mirrors the light.
  final peaks = <Offset>[];
  for (var i = 0; i <= 120; i++) {
    final t = i / 120;
    final saw = math.pow(1 - math.sin(t * math.pi * 4 + 0.4).abs(), 1.6) * 0.75 + (1 - math.sin(t * math.pi * 9 + 1.3).abs()) * 0.25;
    peaks.add(Offset(size.width * t, size.height * (0.78 - saw * 0.16)));
  }
  _glossyHill(canvas, size, peaks, top: const Color(0xFF3A6A8C), foot: const Color(0xFF0E2440), light: Offset(size.width * 0.5, 0), shine: 0.5);
  canvas.save();
  canvas.clipPath(_below(peaks, size));
  final snow = Paint()
    ..color = const Color(0x99E6F6FF)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  for (final p in peaks) {
    if (p.dy < size.height * 0.69) canvas.drawCircle(p + const Offset(0, 5), 7, snow);
  }
  canvas.restore();
  final lake = Rect.fromLTRB(0, size.height * 0.8, size.width, size.height);
  _verticalGradient(canvas, lake, const [Color(0xFF0A3A5A), Color(0xFF041A30)]);
  canvas.save();
  canvas.clipRect(lake);
  canvas.saveLayer(lake, Paint()..blendMode = BlendMode.plus);
  for (var i = 0; i < 40; i++) {
    final x = random.nextDouble() * size.width;
    final y = lake.top + random.nextDouble() * lake.height;
    final w = 30 + random.nextDouble() * 120;
    canvas.drawLine(Offset(x, y), Offset(x + w, y), Paint()
      ..strokeWidth = 2
      ..color = (random.nextBool() ? const Color(0xFF3CFFA0) : const Color(0xFF22D8FF)).withValues(alpha: 0.12 + random.nextDouble() * 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
  }
  canvas.restore();
  canvas.restore();
  canvas.drawLine(Offset(0, lake.top), Offset(size.width, lake.top), Paint()
    ..strokeWidth = 1.5
    ..color = const Color(0x8040FFB0));
}

// ── Green city of tomorrow ────────────────────────────────────────────────

abstract final class _City {
  static const glassDay = [Color(0xFFDDF6FF), Color(0xFF63B8E8), Color(0xFF1F6FB0)];
  static const glassNight = [Color(0xFF2B5C8C), Color(0xFF173A66), Color(0xFF0C2446)];
}

/// The scene of the age, split at the water line: above, a bright sky
/// with the sun flaring, glass towers with gardens on a strip of perfect
/// grass and the Earth hanging huge in the sky; below, clear water with
/// tropical fish and rainbow bubbles. Nature, buildings and machines in
/// one bright world.
void _city(Canvas canvas, Size size, math.Random random, bool night) {
  final rect = Offset.zero & size;
  final m = math.min(size.width, size.height);
  _verticalGradient(canvas, rect, night ? _MeadowNight.sky : _MeadowDay.sky, const [0, 0.25, 0.45, 0.6]);
  final light = Offset(size.width * 0.12, size.height * 0.1);
  if (night) {
    _stars(canvas, size, random, down: 0.5, count: 110);
    _moon(canvas, light, m * 0.032);
  } else {
    _flare(canvas, light, rect.center, m * 0.07, tint: const Color(0xFFFFF6D8));
  }
  // The Earth, huge, coming in from the top right.
  globe(canvas, Offset(size.width * 0.9, size.height * 0.16), m * 0.3, night: night, turn: -0.4);
  for (var i = 0; i < 3; i++) {
    final w = size.width * (0.14 + random.nextDouble() * 0.1);
    _cloud(canvas, Offset(size.width * (0.25 + random.nextDouble() * 0.45), size.height * (0.38 + random.nextDouble() * 0.12)), w, random,
        light: night ? const Color(0xFF5C82C0) : Colors.white, shade: night ? const Color(0xFF2E4E8A) : const Color(0xFFD6EEFF), opacity: night ? 0.4 : 0.92);
  }
  _swoosh(canvas, size, [Offset(-size.width * 0.1, size.height * 0.3), Offset(size.width * 0.3, size.height * 0.08), Offset(size.width * 0.7, size.height * 0.4), Offset(size.width * 1.1, size.height * 0.15)],
      color: night ? const Color(0xFF6FE0FF) : Colors.white, thickness: size.height * 0.045, edge: 0.7);
  final level = size.height * 0.6;
  // The towers stand on a strip of grass just above the water.
  final glass = night ? _City.glassNight : _City.glassDay;
  var x = size.width * (0.02 + random.nextDouble() * 0.04);
  while (x < size.width * 0.62) {
    final w = size.width * (0.035 + random.nextDouble() * 0.035);
    final h = size.height * (0.18 + random.nextDouble() * 0.28);
    _tower(canvas, Rect.fromLTWH(x, level - size.height * 0.03 - h, w, h + size.height * 0.02), random, glass, night: night, light: light);
    x += w + size.width * (0.008 + random.nextDouble() * 0.02);
  }
  final hills = night ? _MeadowNight.hills : _MeadowDay.hills;
  final grass = _smoothRidge(size, random, base: level - size.height * 0.035, height: size.height * 0.012);
  _glossyHill(canvas, size, grass, top: hills[1][0], foot: hills[2][1], light: light, shine: night ? 0.3 : 0.85);
  _train(canvas, size, grass, night: night);
  for (var i = 0; i < 3; i++) {
    final tx = size.width * (0.7 + i * 0.09);
    _turbine(canvas, Offset(tx, grass[(tx / size.width * (grass.length - 1)).round()].dy + 2), size.height * 0.12, random.nextDouble() * math.pi, night: night);
  }
  waterline(canvas, size, level, random, water: night ? _SeaNight.water : _SeaDay.water, night: night);
  // Under the line.
  const kinds = [FishKind.clown, FishKind.tang, FishKind.clown, FishKind.angel, FishKind.tang];
  for (var i = 0; i < kinds.length; i++) {
    tropicalFish(canvas, Offset(size.width * (0.08 + i * 0.2 + random.nextDouble() * 0.06), size.height * (0.72 + random.nextDouble() * 0.2)), m * (0.06 + random.nextDouble() * 0.04), kinds[i], flip: i.isOdd, night: night);
  }
  for (var i = 0; i < 18; i++) {
    final r = 4 + math.pow(random.nextDouble(), 2) * 36;
    rainbowBubble(canvas, Offset(size.width * random.nextDouble(), size.height * (0.05 + random.nextDouble() * 0.9)), r.toDouble(), opacity: night ? 0.55 : 1);
  }
}

void _tower(Canvas canvas, Rect t, math.Random random, List<Color> glass, {required bool night, required Offset light}) {
  // Rounded, slanted or stepped tops, so no two towers match.
  final kind = random.nextInt(3);
  final Path body;
  switch (kind) {
    case 0:
      body = Path()..addRRect(RRect.fromRectAndCorners(t, topLeft: Radius.circular(t.width / 2), topRight: Radius.circular(t.width / 2)));
    case 1:
      final rise = t.width * (0.6 + random.nextDouble() * 0.8);
      body = Path()
        ..moveTo(t.left, t.top + rise)
        ..quadraticBezierTo(t.left + t.width * 0.2, t.top, t.right, t.top)
        ..lineTo(t.right, t.bottom)
        ..lineTo(t.left, t.bottom)
        ..close();
    default:
      final step = t.height * 0.12;
      body = Path()
        ..addRRect(RRect.fromRectAndCorners(Rect.fromLTRB(t.left, t.top + step, t.right, t.bottom), topLeft: Radius.circular(t.width * 0.2), topRight: Radius.circular(t.width * 0.2)))
        ..addRRect(RRect.fromRectAndCorners(Rect.fromLTRB(t.left + t.width * 0.22, t.top, t.right - t.width * 0.22, t.top + step + 4), topLeft: Radius.circular(t.width * 0.28), topRight: Radius.circular(t.width * 0.28)));
  }
  // Glass: sky reflected bright at the top, deeper below, with a vertical
  // sheen down the side facing the light.
  canvas.drawPath(body, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: glass).createShader(t));
  canvas.save();
  canvas.clipPath(body);
  // Clouds and sky caught in the glass.
  _glow(canvas, Offset(t.left + t.width * 0.3, t.top + t.height * 0.25), t.width * 0.9, Colors.white.withValues(alpha: night ? 0.06 : 0.35));
  final sheen = Rect.fromLTWH(t.left + t.width * (light.dx > t.center.dx ? 0.55 : 0.1), t.top, t.width * 0.25, t.height);
  canvas.drawRect(sheen, Paint()..shader = LinearGradient(colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: night ? 0.12 : 0.5), Colors.white.withValues(alpha: 0)]).createShader(sheen));
  // Floors, and at night lit windows.
  final floor = 7.0 + random.nextDouble() * 3;
  for (var y = t.top + floor * 2; y < t.bottom; y += floor) {
    canvas.drawLine(Offset(t.left, y), Offset(t.right, y), Paint()
      ..color = (night ? Colors.black : Colors.white).withValues(alpha: night ? 0.25 : 0.22)
      ..strokeWidth = 1);
    if (night) {
      for (var wx = t.left + 3; wx < t.right - 4; wx += 6) {
        if (random.nextDouble() < 0.45) {
          canvas.drawRect(Rect.fromLTWH(wx, y + 2, 3.5, floor - 4), Paint()..color = (random.nextDouble() < 0.7 ? const Color(0xFFFFE6A8) : const Color(0xFF9FF0FF)).withValues(alpha: 0.75));
        }
      }
    }
  }
  canvas.restore();
  // Gardens on two or three terraces: round green crowns spilling over.
  final terraces = 2 + random.nextInt(2);
  for (var i = 0; i < terraces; i++) {
    final y = t.top + t.height * (0.18 + i * 0.22 + random.nextDouble() * 0.05);
    canvas.drawRect(Rect.fromLTWH(t.left - 3, y, t.width + 6, 3), Paint()..color = night ? const Color(0xFF1E3A50) : Colors.white);
    // Vines hanging over the edge.
    for (var k = 0; k < 3; k++) {
      final vx = t.left + random.nextDouble() * t.width;
      canvas.drawLine(Offset(vx, y + 3), Offset(vx + (random.nextDouble() - 0.5) * 3, y + 6 + random.nextDouble() * 14), Paint()
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = night ? const Color(0xFF1E4A38) : const Color(0xFF4FAE2A));
    }
    // Shrubs and small trees, bigger at the back.
    for (var k = 0; k < 6; k++) {
      final c = Offset(t.left - 2 + random.nextDouble() * (t.width + 4), y - 1 - random.nextDouble() * 4);
      final rx = t.width * (0.09 + random.nextDouble() * 0.12);
      final crown = Rect.fromCenter(center: c, width: rx * 2, height: rx * 1.5);
      canvas.drawOval(crown, Paint()..shader = RadialGradient(center: const Alignment(-0.3, -0.5), colors: night ? const [Color(0xFF2F6A50), Color(0xFF123628)] : const [Color(0xFFC8F58A), Color(0xFF3E9E22)]).createShader(crown));
    }
  }
  // A glint at the very top.
  _glow(canvas, Offset(t.center.dx, t.top + 6), t.width * 0.5, (night ? const Color(0xFFFF4D6A) : Colors.white).withValues(alpha: night ? 0.6 : 0.5));
}

void _turbine(Canvas canvas, Offset foot, double height, double turn, {required bool night}) {
  final white = night ? const Color(0xFF9FB4CC) : Colors.white;
  final hub = foot - Offset(0, height);
  canvas.drawPath(
    Path()
      ..moveTo(foot.dx - height * 0.025, foot.dy)
      ..lineTo(hub.dx - height * 0.01, hub.dy)
      ..lineTo(hub.dx + height * 0.01, hub.dy)
      ..lineTo(foot.dx + height * 0.025, foot.dy)
      ..close(),
    Paint()..shader = LinearGradient(colors: [white, Color.lerp(white, const Color(0xFF8FA6BC), 0.5)!]).createShader(Rect.fromPoints(foot - Offset(height * 0.03, 0), hub + Offset(height * 0.03, 0))),
  );
  for (var i = 0; i < 3; i++) {
    final a = turn + i * math.pi * 2 / 3;
    final tip = hub + Offset(math.cos(a), math.sin(a)) * height * 0.55;
    final side = Offset(-math.sin(a), math.cos(a)) * height * 0.035;
    canvas.drawPath(Path()
      ..moveTo(hub.dx, hub.dy)
      ..quadraticBezierTo(hub.dx + (tip.dx - hub.dx) * 0.3 + side.dx, hub.dy + (tip.dy - hub.dy) * 0.3 + side.dy, tip.dx, tip.dy)
      ..lineTo(hub.dx, hub.dy)
      ..close(), Paint()..color = white);
  }
  canvas.drawCircle(hub, height * 0.03, Paint()..color = white);
  if (night) canvas.drawCircle(hub - Offset(0, height * 0.04), 2, Paint()..color = const Color(0xFFFF4D6A));
}

/// A rounded white train on a slender track that follows the hill.
void _train(Canvas canvas, Size size, List<Offset> ridge, {required bool night}) {
  final track = [for (final p in ridge) p - Offset(0, size.height * 0.035)];
  canvas.drawPath(Path()..addPolygon(track, false), Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..color = night ? const Color(0xFF7FA0C0) : Colors.white);
  // Pillars.
  for (var i = 0; i < track.length; i += 8) {
    canvas.drawLine(track[i], ridge[i] + const Offset(0, 6), Paint()
      ..strokeWidth = 2
      ..color = (night ? const Color(0xFF7FA0C0) : Colors.white).withValues(alpha: 0.8));
  }
  // The train: three cars along the track.
  final start = (track.length * 0.18).round();
  for (var car = 0; car < 3; car++) {
    final i = start + car * 7;
    final a = track[i], b = track[i + 7];
    final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
    final len = (b - a).distance;
    canvas.save();
    canvas.translate(a.dx, a.dy);
    canvas.rotate(angle);
    final body = RRect.fromRectAndCorners(Rect.fromLTWH(0, -19, len - 3, 17),
        topLeft: Radius.circular(car == 0 ? 3 : 9), bottomLeft: const Radius.circular(4), topRight: Radius.circular(car == 2 ? 3 : 14), bottomRight: const Radius.circular(4));
    canvas.drawRRect(body, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: night ? const [Color(0xFFB8C8DC), Color(0xFF5F7590)] : const [Colors.white, Color(0xFFC8D8E8)]).createShader(body.outerRect));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(4, -15, len - 12, 6), const Radius.circular(3)), Paint()..color = night ? const Color(0xFFFFE6A8) : const Color(0xFF1F5FA8));
    canvas.drawRect(Rect.fromLTWH(2, -5, len - 7, 1.5), Paint()..color = const Color(0xFF34C3FF));
    canvas.restore();
  }
}

// ── Millennium collage ────────────────────────────────────────────────────

abstract final class _Collage {
  static const day = [Color(0xFF0A5FD0), Color(0xFF1E8EF0), Color(0xFF4FC4F8), Color(0xFF2AA8E0)];
  static const night = [Color(0xFF041038), Color(0xFF0A2468), Color(0xFF123C8C), Color(0xFF0C2A66)];
  static const props = [Color(0xFFD5DCE4), Color(0xFF3AA84A), Color(0xFF3A8CFF), Color(0xFF9A7AFF)];
  static const propsNight = [Color(0xFF4A5566), Color(0xFF1F5A2C), Color(0xFF7F9FFF), Color(0xFFB08AFF)];
}

/// Treasures of the age floating in blue: shining discs, a crystal ball
/// with a city above the water and fish below, the Earth in a drop of
/// water, glass stars, green gel balls, a goldfish, a glass butterfly and
/// bubbles everywhere.
void _collage(Canvas canvas, Size size, math.Random random, bool night) {
  final rect = Offset.zero & size;
  final m = math.min(size.width, size.height);
  _verticalGradient(canvas, rect, night ? _Collage.night : _Collage.day, const [0, 0.4, 0.7, 1]);
  final ribbon = night ? const Color(0xFF5FD8FF) : Colors.white;
  _swoosh(canvas, size, [Offset(-size.width * 0.1, size.height * 0.75), Offset(size.width * 0.3, size.height * 0.35), Offset(size.width * 0.6, size.height * 0.9), Offset(size.width * 1.1, size.height * 0.45)], color: ribbon, thickness: size.height * 0.08);
  _swoosh(canvas, size, [Offset(-size.width * 0.1, size.height * 0.35), Offset(size.width * 0.35, size.height * 0.5), Offset(size.width * 0.6, size.height * 0.1), Offset(size.width * 1.1, size.height * 0.3)], color: night ? const Color(0xFF8C7CFF) : const Color(0xFFB8F0FF), thickness: size.height * 0.04, edge: 0.6);
  _bokeh(canvas, rect, random, color: night ? const Color(0xFF7FD8FF) : Colors.white, count: 30, size: 22);
  // Discs, piled at the top right.
  disc(canvas, Offset(size.width * 0.86, size.height * 0.2), m * 0.2, turn: 0.4, dim: night ? 0.7 : 0);
  disc(canvas, Offset(size.width * 0.7, size.height * 0.1), m * 0.12, turn: 1.6, label: const Color(0x553A8CFF), dim: night ? 0.7 : 0);
  // The crystal ball: a city on grass above the water line, fish below.
  glassOrb(canvas, Offset(size.width * 0.16, size.height * 0.7), m * 0.2, night: night, inside: (c, box) {
    c.save();
    c.translate(box.left, box.top);
    _city(c, Size(box.width, box.height), math.Random(9), night);
    c.restore();
  });
  // The Earth inside a drop of water.
  final drop = Offset(size.width * 0.9, size.height * 0.62);
  final dr = m * 0.09;
  globe(canvas, drop, dr * 0.8, night: night, turn: 0.8);
  final tear = Path()
    ..moveTo(drop.dx, drop.dy - dr * 1.9)
    ..cubicTo(drop.dx + dr * 0.35, drop.dy - dr * 1.3, drop.dx + dr, drop.dy - dr * 0.6, drop.dx + dr, drop.dy)
    ..arcToPoint(Offset(drop.dx - dr, drop.dy), radius: Radius.circular(dr))
    ..cubicTo(drop.dx - dr, drop.dy - dr * 0.6, drop.dx - dr * 0.35, drop.dy - dr * 1.3, drop.dx, drop.dy - dr * 1.9)
    ..close();
  canvas.drawPath(tear, Paint()..shader = RadialGradient(colors: [const Color(0x0080E0FF), const Color(0x1080E0FF), const Color(0xAA2A8AD8)], stops: const [0, 0.7, 1]).createShader(Rect.fromCircle(center: drop - Offset(0, dr * 0.4), radius: dr * 1.5)));
  canvas.drawPath(tear, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white.withValues(alpha: 0.7));
  gloss(canvas, drop, dr, strength: 0.8, shadow: false);
  // Stars, gel balls and a goldfish.
  final stars = night ? const [Color(0xFF7F9FFF), Color(0xFFB08AFF)] : const [Color(0xFF3A8CFF), Color(0xFF7AB8FF), Color(0xFF9A7AFF)];
  for (final (x, y, r, i) in const [(0.52, 0.12, 0.05, 0), (0.62, 0.42, 0.035, 2), (0.38, 0.3, 0.03, 1), (0.95, 0.88, 0.045, 2), (0.3, 0.92, 0.035, 0)]) {
    glassStar(canvas, Offset(size.width * x, size.height * y), m * r, stars[i % stars.length], turn: -math.pi / 2 + (x - 0.5));
  }
  for (final (x, y, r) in const [(0.42, 0.78, 0.045), (0.47, 0.86, 0.028), (0.74, 0.8, 0.035)]) {
    gelOrb(canvas, Offset(size.width * x, size.height * y), m * r, night ? const Color(0xFF1F5A2C) : const Color(0xFF4CD03A));
  }
  tropicalFish(canvas, Offset(size.width * 0.6, size.height * 0.66), m * 0.16, FishKind.gold, night: night);
  butterfly(canvas, Offset(size.width * 0.32, size.height * 0.48), m * 0.07, turn: -0.25, color: night ? const Color(0xFF6FA8FF) : const Color(0xFF2E9BFF));
  for (var i = 0; i < 22; i++) {
    final r = 5 + math.pow(random.nextDouble(), 2) * 44;
    rainbowBubble(canvas, Offset(size.width * random.nextDouble(), size.height * random.nextDouble()), r.toDouble(), opacity: night ? 0.6 : 1);
  }
}

// ── Dunes ─────────────────────────────────────────────────────────────────

abstract final class _DunesDay {
  /// Top of the sky down to the haze on the horizon.
  static const sky = [Color(0xFFE2C29A), Color(0xFFEDD3AE), Color(0xFFF6E4C8), Color(0xFFF9ECD8)];
  /// Far to near: sunlit face at the crest and at the foot, then the
  /// shaded slip face at the crest and at the foot.
  static const dunes = [
    [Color(0xFFF3DDBB), Color(0xFFEDD1A8), Color(0xFFE2C29C), Color(0xFFDDBA92)],
    [Color(0xFFF2D3A4), Color(0xFFE8C189), Color(0xFFD3A77A), Color(0xFFCC9D6F)],
    [Color(0xFFF1C990), Color(0xFFE3B072), Color(0xFFC08D5F), Color(0xFFB48056)],
    [Color(0xFFF0C080), Color(0xFFDDA461), Color(0xFFAE7A4F), Color(0xFFA06E47)],
  ];
  static const sun = Color(0xFFFFF6E6);
  static const haze = Color(0xFFF8E8D0);
  static const grain = Color(0x2E6A4020);
}

abstract final class _DunesNight {
  static const sky = [Color(0xFF0B0A18), Color(0xFF15122A), Color(0xFF231B35), Color(0xFF3A2735)];
  static const dunes = [
    [Color(0xFF3B2D3E), Color(0xFF332838), Color(0xFF241D30), Color(0xFF211A2C)],
    [Color(0xFF4A3744), Color(0xFF3D2E3C), Color(0xFF241C2E), Color(0xFF1F1828)],
    [Color(0xFF5A4248), Color(0xFF47343C), Color(0xFF231A2A), Color(0xFF1C1523)],
    [Color(0xFF684C4E), Color(0xFF503A3E), Color(0xFF211825), Color(0xFF18121D)],
  ];
  static const haze = Color(0xFF4A3040);
  static const grain = Color(0x33E8C8A8);
}

/// One row of dunes: its top edge and the crests along it. Sharp crests
/// and wide round hollows, each crest leaning with the wind so its slip
/// face (at the left, away from the light) is the steeper side.
({List<Offset> edge, List<(double x, double y, double valley)> peaks}) _duneEdge(Size size, math.Random random, {required double base, required double height, required int count}) {
  final f = math.pi * count / size.width;
  final p1 = random.nextDouble() * math.pi;
  final f2 = math.pi * 2 * (0.4 + random.nextDouble() * 0.5) / size.width;
  final p2 = random.nextDouble() * math.pi * 2;
  final f3 = math.pi * 2 * (0.5 + random.nextDouble() * 0.6) / size.width;
  final p3 = random.nextDouble() * math.pi * 2;
  double rise(double x) {
    // Unevenly spaced crests: the phase drifts along the row.
    final u = f * x + p1 + 0.9 * math.sin(f3 * x + p3);
    // Leaning the wave puts the cusp nearer one hollow than the other.
    final ridge = 1 - math.sin(u + 0.55 * math.sin(u)).abs();
    final crest = math.pow(ridge, 1.6).toDouble();
    return height * (0.72 * crest + 0.28 * (0.5 + 0.5 * math.sin(f2 * x + p2)));
  }

  const n = 360;
  final edge = [
    for (var i = 0; i <= n; i++)
      () {
        final x = size.width * (i / n * 1.1 - 0.05);
        return Offset(x, base - rise(x));
      }(),
  ];
  final peaks = <(double, double, double)>[];
  for (var i = 1; i < n; i++) {
    if (edge[i].dy < edge[i - 1].dy && edge[i].dy <= edge[i + 1].dy) {
      // The hollow before it, at the left.
      var j = i - 1;
      while (j > 0 && edge[j - 1].dy > edge[j].dy) {
        j--;
      }
      peaks.add((edge[i].dx, edge[i].dy, edge[j].dx));
    }
  }
  return (edge: edge, peaks: peaks);
}

double _edgeAt(List<Offset> edge, double x) {
  for (var i = 1; i < edge.length; i++) {
    if (edge[i].dx >= x) {
      final a = edge[i - 1], b = edge[i];
      return a.dy + (b.dy - a.dy) * ((x - a.dx) / math.max(0.001, b.dx - a.dx));
    }
  }
  return edge.last.dy;
}

void _dune(Canvas canvas, Size size, math.Random random, {required double base, required double height, required int count, required List<Color> tones, required bool night, required double ripples}) {
  final (:edge, :peaks) = _duneEdge(size, random, base: base, height: height, count: count);
  final body = Path()..moveTo(edge.first.dx, size.height);
  for (final p in edge) {
    body.lineTo(p.dx, p.dy);
  }
  body
    ..lineTo(edge.last.dx, size.height)
    ..close();
  final top = edge.map((p) => p.dy).reduce(math.min);
  final band = Rect.fromLTRB(0, top, size.width, size.height);
  // The sunlit sand, bright at the crests.
  canvas.drawPath(body, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [tones[0], tones[1]], stops: const [0, 0.7]).createShader(band));
  canvas.save();
  canvas.clipPath(body);
  // Wind ripples on the lit backs: fine lines following the dune's
  // shape, a shaded groove with a lit ridge just under it.
  final depth = size.height - top;
  for (var i = 0; i < 26 * ripples; i++) {
    final d = depth * (0.04 + math.pow(random.nextDouble(), 1.3) * 0.7);
    final x0 = random.nextDouble() * size.width;
    final w = size.width * (0.08 + random.nextDouble() * 0.2);
    final wobble = 2 + random.nextDouble() * 5;
    final phase = random.nextDouble() * 6;
    final line = <Offset>[
      for (var j = 0; j <= 24; j++)
        () {
          final x = x0 + w * j / 24;
          return Offset(x, _edgeAt(edge, x) + d + math.sin(j / 24 * math.pi * 2 + phase) * wobble);
        }(),
    ];
    final fade = 1 - d / depth;
    canvas.drawPoints(PointMode.polygon, line, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = tones[3].withValues(alpha: 0.28 * fade));
    canvas.drawPoints(PointMode.polygon, [for (final p in line) p + const Offset(0, 1.6)], Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = (night ? const Color(0xFFB8A6C8) : Colors.white).withValues(alpha: (night ? 0.12 : 0.3) * fade));
  }
  // Slip faces in shadow: from each crest the knife edge winds down
  // through the dune; everything between it and the hollow before is in
  // shade.
  for (final (px, py, valley) in peaks) {
    final span = px - valley;
    final bend = span * (0.15 + random.nextDouble() * 0.25);
    final shade = Path()..moveTo(px, py);
    for (final p in edge.reversed) {
      if (p.dx < px && p.dx >= valley) shade.lineTo(p.dx, p.dy);
    }
    shade
      ..lineTo(valley + span * 0.3, size.height)
      ..lineTo(px - bend, size.height)
      ..cubicTo(px - bend * 1.4, py + (size.height - py) * 0.6, px + bend * 0.9, py + (size.height - py) * 0.3, px, py)
      ..close();
    final rect = Rect.fromLTRB(valley, py, px, size.height);
    canvas.drawPath(shade, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [tones[2], tones[3]]).createShader(rect));
    // Light thrown back from the sand in front warms the shade's foot.
    canvas.drawPath(shade, Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [tones[1].withValues(alpha: 0), tones[1].withValues(alpha: 0.3)]).createShader(rect));
  }
  canvas.restore();
  // The knife-edge crests catch the light.
  for (final (px, py, _) in peaks) {
    final crest = [for (final p in edge) if (p.dx >= px - 2 && p.dx < px + size.width * 0.12) p];
    if (crest.length < 2) continue;
    canvas.drawPoints(PointMode.polygon, crest, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(colors: [(night ? const Color(0xFFE8DCF0) : Colors.white).withValues(alpha: night ? 0.45 : 0.8), Colors.white.withValues(alpha: 0)]).createShader(Rect.fromLTRB(px, py - 4, px + size.width * 0.12, py + 4))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8));
  }
}

/// A sea of wind-carved dunes, crest behind crest fading into the haze:
/// under a low, hazy sun by day; by night under a large moon and a small
/// second one, with the crests silvered and the slip faces in deep shade.
void _dunes(Canvas canvas, Size size, math.Random random, bool night) {
  final rect = Offset.zero & size;
  final m = math.min(size.width, size.height);
  final sky = night ? _DunesNight.sky : _DunesDay.sky;
  final tones = night ? _DunesNight.dunes : _DunesDay.dunes;
  _verticalGradient(canvas, rect, sky, const [0, 0.25, 0.48, 0.62]);
  final light = Offset(size.width * 0.78, size.height * 0.36);
  if (night) {
    _stars(canvas, size, random, down: 0.6, count: 220);
    // The band of the galaxy, faint, across the sky.
    canvas.save();
    canvas.translate(size.width * 0.5, size.height * 0.25);
    canvas.rotate(-0.35);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: size.width * 1.3, height: size.height * 0.16), Paint()
      ..color = const Color(0x14C8B8FF)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, m * 0.05));
    canvas.restore();
    _moon(canvas, Offset(size.width * 0.86, size.height * 0.22), m * 0.06);
    _moon(canvas, Offset(size.width * 0.74, size.height * 0.14), m * 0.018);
    _glow(canvas, Offset(size.width * 0.5, size.height * 0.58), size.width * 0.6, const Color(0x40703040));
  } else {
    // A big pale sun low in the haze.
    _glow(canvas, light, m * 0.9, const Color(0x55FFE2B0));
    _glow(canvas, light, m * 0.32, const Color(0x99FFF1D6));
    canvas.drawCircle(light, m * 0.07, Paint()
      ..color = _DunesDay.sun
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, m * 0.006));
    // Thin bands of high cloud across the sun.
    for (var i = 0; i < 5; i++) {
      final y = size.height * (0.12 + random.nextDouble() * 0.26);
      final x = size.width * (random.nextDouble() * 0.8);
      canvas.drawOval(Rect.fromLTWH(x, y, size.width * (0.2 + random.nextDouble() * 0.3), m * 0.012), Paint()
        ..color = const Color(0x40FFFFFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, m * 0.008));
    }
  }
  const bases = [0.6, 0.7, 0.82, 0.97];
  const heights = [0.07, 0.11, 0.16, 0.22];
  const counts = [4, 3, 3, 2];
  for (var i = 0; i < tones.length; i++) {
    _dune(canvas, size, random, base: size.height * bases[i], height: size.height * heights[i], count: counts[i], tones: tones[i], night: night, ripples: 0.3 + i * 0.35);
    // Blown sand hangs over the far dunes.
    if (i < tones.length - 1) {
      final y = size.height * (bases[i] - heights[i] * 0.4);
      final band = Rect.fromLTRB(0, y - size.height * 0.08, size.width, y + size.height * 0.12);
      final haze = night ? _DunesNight.haze : _DunesDay.haze;
      canvas.drawRect(band, Paint()
        ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [haze.withValues(alpha: 0), haze.withValues(alpha: night ? 0.22 : 0.4), haze.withValues(alpha: 0)]).createShader(band));
    }
  }
  // Grain over everything, as sand and old film.
  canvas.drawRect(rect, Paint()..shader = noiseShader(night ? _DunesNight.grain : _DunesDay.grain, spacing: 3, size: 1));
}
