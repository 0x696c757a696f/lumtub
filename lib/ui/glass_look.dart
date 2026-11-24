import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

import '../skins/skin.dart';
import 'linked_text.dart';
import 'theme.dart';

/// How the window looks while the desktop shows through it (窗口透明,
/// docs/specs/window-glass.md): the page colour laid over the desktop at
/// [alpha], the bars round the pages drawn at [alpha] over that, and the
/// pages themselves solid unless [whole].
class GlassLook extends ThemeExtension<GlassLook> {
  const GlassLook({required this.alpha, required this.whole, required this.tint, this.chrome});

  /// How much of the page colour (and of each bar's own colour) covers
  /// the desktop: never below the skin's [glassFloor].
  final double alpha;

  /// The pages are glass too, not only the frame round them.
  final bool whole;

  /// The page colour the glass is tinted with.
  final Color tint;

  /// The colour of the bars without a skin surface of their own (the
  /// standard look's top bar and rail), as it is without glass.
  final Color? chrome;

  @override
  GlassLook copyWith({double? alpha, bool? whole, Color? tint, Color? chrome}) =>
      GlassLook(alpha: alpha ?? this.alpha, whole: whole ?? this.whole, tint: tint ?? this.tint, chrome: chrome ?? this.chrome);

  @override
  GlassLook lerp(GlassLook? other, double t) => t < 0.5 || other == null ? this : other;
}

extension GlassLookOf on BuildContext {
  /// Set while the desktop shows through the window.
  GlassLook? get glass => Theme.of(this).extension<GlassLook>();
}

/// The clearest a theme's glass may go while every word on it stays
/// readable, whatever lies behind the window.
const glassClearest = 0.3;

/// What may lie behind the window: black to white in steps, and the
/// brightest colours, at full strength (blur only softens them).
final List<Color> desktopColors = [
  for (var v = 0; v <= 255; v += 15) Color.fromARGB(255, v, v, v),
  const Color(0xFFFF0000),
  const Color(0xFF00FF00),
  const Color(0xFF0000FF),
  const Color(0xFFFFFF00),
  const Color(0xFF00FFFF),
  const Color(0xFFFF00FF),
];

/// One kind of writing on the glass: [text] on a bar whose own colours,
/// see-through ones included, are [ground] (empty: the bare glass), at
/// least [min] to one. Words on the frame sit on a [GlassPlate] of
/// [plate]; words on see-through pages ([GlassLook.whole]) have none.
typedef GlassWriting = ({String what, Color text, List<Color> ground, double min, Color? plate});

/// Everything written straight on the glass under [theme]: on the bare
/// tint (the top of the window, the rail of the standard look), on each
/// of a skin's bars, and with [whole] what the pages write.
List<GlassWriting> glassWritings(ThemeData theme, {required bool whole}) {
  final scheme = theme.colorScheme;
  final skin = theme.extension<SkinTheme>()?.skin?.forBrightness(theme.brightness);
  final chrome = theme.extension<AppTones>()?.chrome;
  final tint = glassTint(theme);
  List<Color> ground(SkinSurface? s) => s == null ? const [] : s.groundColors;
  Color plate(SkinSurface? s) => plateColor(tint, surface: s);
  GlassWriting frame(String what, Color text, SkinSurface? s, {double min = 4.5}) => (what: what, text: text, ground: ground(s), min: min, plate: plate(s));
  final chromePlate = plateColor(tint, color: chrome);
  final onChrome = chrome == null ? const <Color>[] : [chrome];
  return [
    // The top bar and rail of the standard look and of skins without
    // bars of their own.
    (what: 'text on the frame', text: scheme.onSurface, ground: onChrome, min: 4.5, plate: chromePlate),
    (what: 'muted text on the frame', text: scheme.onSurfaceVariant, ground: onChrome, min: 4.5, plate: chromePlate),
    (what: 'status bar', text: skin?.statusBarText ?? scheme.outline, ground: skin?.statusBar != null ? ground(skin!.statusBar) : onChrome, min: 4.5, plate: skin?.statusBar != null ? plate(skin!.statusBar) : chromePlate),
    if (skin != null) ...[
      if (skin.titleBar case final t?) ...[
        frame('title', t.text, t.surface),
        // Buttons with faces of their own draw them solid, glyphs on them,
        // as without glass; bare glyphs sit on the bar.
        if (t.button?.baseColor == null) frame('window buttons', t.buttonIcon, t.surface, min: 3),
      ],
      if (skin.menuBar case final m?) frame('menu bar', m.text, m.surface),
      if (skin.topBar != null) frame('top bar', skin.topBarText ?? scheme.onSurface, skin.topBar, min: 3),
      if (skin.sideBar != null) frame('rail', skin.navText ?? scheme.onSurfaceVariant, skin.sideBar),
      if (skin.tabs case final t?) frame('tabs', t.text, t.bar),
    ],
    if (whole) ...[
      (what: 'text on the pages', text: scheme.onSurface, ground: const [], min: 4.5, plate: null),
      (what: 'muted text on the pages', text: scheme.onSurfaceVariant, ground: const [], min: 4.5, plate: null),
      (what: 'quiet text on the pages', text: scheme.outline, ground: const [], min: 4.5, plate: null),
      (what: 'links on the pages', text: linkColor(theme), ground: const [], min: 4.5, plate: null),
    ],
  ];
}

/// The colour of the [GlassPlate] behind words on [surface] (or on a bar
/// of [color]): the bar as it would be drawn solid over the page colour.
Color plateColor(Color tint, {SkinSurface? surface, Color? color}) {
  final base = surface?.baseColor ?? color;
  return base == null ? tint : Color.alphaBlend(base, tint);
}

/// The colours behind [w] over [desktop] at [alpha]: the tint, then each
/// of the bar's colours, all at [alpha], then its plate.
List<Color> glassBehind(GlassWriting w, Color tint, Color desktop, double alpha) {
  Color fade(Color c, double by) => c.withValues(alpha: c.a * by);
  final under = Color.alphaBlend(fade(tint, alpha), desktop);
  final bars = w.ground.isEmpty ? [under] : [for (final c in w.ground) Color.alphaBlend(fade(c, alpha), under)];
  final plate = w.plate;
  return plate == null ? bars : [for (final bar in bars) Color.alphaBlend(fade(plate, GlassPlate.coverage), bar)];
}

/// The lowest [GlassLook.alpha] at which every [glassWritings] of [theme]
/// reads over every [desktopColors], between [glassClearest] and 1.
double glassFloor(ThemeData theme, {required bool whole}) {
  final tint = glassTint(theme);
  final writings = glassWritings(theme, whole: whole);
  bool reads(double alpha) => writings.every((w) => desktopColors.every((desk) => glassBehind(w, tint, desk, alpha).every((bg) {
        // Words at their own alpha land on what is behind them.
        return contrastRatio(Color.alphaBlend(w.text, bg), bg) >= w.min;
      })));
  for (var alpha = glassClearest; alpha < 1; alpha += 0.01) {
    if (reads(alpha)) return double.parse(alpha.toStringAsFixed(2));
  }
  return 1;
}

/// The colour the glass is tinted with: the page colour.
Color glassTint(ThemeData theme) {
  final skin = theme.extension<SkinTheme>()?.skin?.forBrightness(theme.brightness);
  final page = skin?.colors.page ?? theme.colorScheme.surface;
  return page.withValues(alpha: 1);
}

/// [theme] for a window the desktop shows through, [transparency] 0 (as
/// solid as without) to 1 (as clear as words stay readable). The pages
/// keep their solid page colour unless [whole].
ThemeData withGlass(ThemeData theme, {required double transparency, required bool whole}) {
  final floor = glassFloor(theme, whole: whole);
  final alpha = 1 - transparency.clamp(0, 1) * (1 - floor);
  final tint = glassTint(theme);
  final tones = theme.extension<AppTones>() ?? const AppTones();
  final look = GlassLook(alpha: math.min(1, alpha), whole: whole, tint: tint, chrome: tones.chrome);
  return theme.copyWith(
    // Pages opened over the window: solid, or the glass itself.
    scaffoldBackgroundColor: whole ? Colors.transparent : tint,
    extensions: [
      ...theme.extensions.values.where((e) => e is! AppTones),
      // The chrome colour of the standard look's bars, at the glass's alpha
      // over the tint; without one the bars are the bare glass.
      AppTones(chrome: tones.chrome?.withValues(alpha: tones.chrome!.a * look.alpha) ?? Colors.transparent, warmth: tones.warmth),
      look,
    ],
  );
}

/// The glow of words on Windows 7's glass: a soft halo of the bar's own
/// colour that follows the shapes of [child]'s letters and icons while the
/// desktop shows through, so they read whatever lies behind the window.
/// Without glass it is [child] alone.
class GlassPlate extends StatelessWidget {
  const GlassPlate({super.key, this.surface, required this.child});

  /// The bar [child] sits on, whose colour the plate takes; null for the
  /// bars of the standard look, in [GlassLook.chrome].
  final SkinSurface? surface;
  final Widget child;

  /// Each of [children] on a plate of its own, but gaps and stretches.
  static List<Widget> each(SkinSurface? surface, List<Widget> children) => [
        for (final child in children)
          child is SizedBox || child is Spacer || child is Expanded || child is Flexible ? child : GlassPlate(surface: surface, child: child),
      ];

  /// How far the strokes are widened before [sigma] softens the edge, in
  /// pixels: the halo is nearly whole up to two pixels past the ink and
  /// gone about [spread] plus three [sigma] out.
  static const spread = 4.0;

  /// The blur of the halo's edge, as a gaussian sigma.
  static const sigma = 1.25;

  /// How much of the halo covers every point one pixel from the ink
  /// (0.94 two pixels out). Tested in test/window_glass_test.dart.
  static const coverage = 0.99;

  @override
  Widget build(BuildContext context) {
    final look = context.glass;
    if (look == null) return child;
    return _Halo(color: plateColor(look.tint, surface: surface, color: surface == null ? look.chrome : null).withValues(alpha: 1), child: child);
  }
}

class _Halo extends SingleChildRenderObjectWidget {
  const _Halo({required this.color, required super.child});
  final Color color;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHalo(color);

  @override
  void updateRenderObject(BuildContext context, _RenderHalo renderObject) => renderObject.color = color;
}

/// Paints its child twice: once in the halo colour, widened and blurred,
/// then as it is on top.
class _RenderHalo extends RenderProxyBox {
  _RenderHalo(this._color);

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  // Widen the strokes, then soften the edge.
  static final _filter = ui.ImageFilter.compose(
    outer: ui.ImageFilter.blur(sigmaX: GlassPlate.sigma, sigmaY: GlassPlate.sigma),
    inner: ui.ImageFilter.dilate(radiusX: GlassPlate.spread, radiusY: GlassPlate.spread),
  );

  final _blur = LayerHandle<ImageFilterLayer>();
  final _tint = LayerHandle<ColorFilterLayer>();

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final blur = _blur.layer ??= ImageFilterLayer();
    blur.imageFilter = _filter;
    context.pushLayer(blur, (context, offset) {
      _tint.layer = context.pushColorFilter(offset, ColorFilter.mode(_color, BlendMode.srcIn), (context, offset) => context.paintChild(child, offset), oldLayer: _tint.layer);
    }, offset);
    context.paintChild(child, offset);
  }

  @override
  void dispose() {
    _blur.layer = null;
    _tint.layer = null;
    super.dispose();
  }
}

/// The glass itself, under everything in the window: the tint at
/// [GlassLook.alpha] over the desktop, with the diagonal sheen and the
/// light inner edge of Windows 7's frames. [plain] (低占用模式) keeps
/// the tint alone.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.look, this.plain = false});
  final GlassLook look;
  final bool plain;

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(painter: _GlassPainter(look.tint.withValues(alpha: look.alpha), sheen: !plain), size: Size.infinite));
}

class _GlassPainter extends CustomPainter {
  _GlassPainter(this.tint, {required this.sheen});
  final Color tint;
  final bool sheen;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = tint);
    if (!sheen || size.isEmpty) return;
    // Light on a dark tint shows more: the streaks are fainter there.
    final light = tint.computeLuminance() > 0.4;
    final streak = Colors.white.withValues(alpha: light ? 0.16 : 0.07);
    final clear = streak.withValues(alpha: 0);
    // Broad bands across the diagonal, as light through a pane.
    final span = (size.width + size.height) / 2;
    canvas.drawRect(rect, Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(span, span),
        [clear, streak, clear, clear, streak, clear, clear],
        const [0.08, 0.13, 0.2, 0.42, 0.47, 0.56, 1],
      ));
    // The thin light edge inside the frame.
    canvas.drawRect(rect.deflate(0.5), Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: light ? 0.5 : 0.18));
  }

  @override
  bool shouldRepaint(_GlassPainter old) => old.tint != tint || old.sheen != sheen;
}
