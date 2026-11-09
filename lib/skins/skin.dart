import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A skin: a whole look for the window, read from a `skin.jsonc` file.
/// docs/skins.md describes every field; skins/template/skin.jsonc is a
/// commented starting point. Every field is optional except `id`, `name`
/// and `brightness`; what a skin leaves out stays as Lumtub draws it.
class Skin {
  Skin._(this.id, this._raw, this.folder, this.builtIn, this.warnings);

  /// The newest file format this Lumtub reads.
  static const formatVersion = 1;

  final String id;
  final Map<String, Object?> _raw;

  /// Where its files (pictures, fonts) are: an asset folder for a built-in
  /// skin, a directory for one the user added.
  final String folder;
  final bool builtIn;

  /// Fields that could not be read and were left out.
  final List<String> warnings;

  late final String _name = _str(_raw['name']) ?? id;
  late final Map<String, String> _names = _strings(_raw['names']);
  late final String _description = _str(_raw['description']) ?? '';
  late final Map<String, String> _descriptions = _strings(_raw['descriptions']);
  late final String author = _str(_raw['author']) ?? '';
  late final String version = _str(_raw['version']) ?? '';
  late final String license = _str(_raw['license']) ?? '';

  /// Its name in [language] (a tag such as zh-Hans), falling back on
  /// the language alone, then on the English `name`.
  String nameIn(String language) => _localized(_names, language) ?? _name;
  String descriptionIn(String language) => _localized(_descriptions, language) ?? _description;

  late final Brightness brightness = _raw['brightness'] == 'dark' ? Brightness.dark : Brightness.light;

  /// The dark side of a skin whose "brightness" is "auto": it follows the
  /// theme mode, light or dark, with `overrides.dark` laid over it there.
  Skin? _dark;
  bool get followsThemeMode => _dark != null || _light != null;
  Skin? _light;

  /// This skin as drawn in [mode]: the dark side of an "auto" skin in dark
  /// mode, otherwise itself.
  Skin forBrightness(Brightness mode) => mode == Brightness.dark ? (_dark ?? this) : (_light ?? this);

  /// Whether the skin draws the side rail, or leaves it as Lumtub's own.
  bool get drawsRail => sideBar != null || navSelected != null;

  /// Whether the skin has its own logo, or keeps Lumtub's.
  bool get hasLogo => _map(_raw['logo']).isNotEmpty;

  /// Font families to load from files in the skin's folder.
  late final Map<String, String> fontFiles = _strings(_raw['fonts']);

  late final Map<String, Object?> _text = _map(_raw['text']);
  /// The face for all text, or null to keep the one chosen in Settings.
  late final String? font = _str(_text['font']);
  /// The face for headings and the app name.
  late final String? displayFont = _str(_text['displayFont']);
  /// The face for numbers: times, durations, the status bar.
  late final String? monoFont = _str(_text['monoFont']);

  late final SkinColors colors = SkinColors._(_map(_raw['colors']), this);
  late final SkinShape shape = SkinShape._(_map(_raw['shape']));

  late final Map<String, Object?> _window = _map(_raw['window']);
  /// The page behind everything, painted bottom first.
  late final List<SkinPaint> background = SkinPaint.listOf(_window['background'], this);
  /// Ornaments over the background, under the content.
  late final List<SkinDecoration> decorations = _list(_window['decorations']).map((d) => SkinDecoration.parse(d, this)).nonNulls.toList();
  late final SkinTitleBar? titleBar = SkinTitleBar.parse(_window['titleBar'], this);
  late final SkinMenuBar? menuBar = SkinMenuBar.parse(_window['menuBar'], this);
  late final SkinSurface? topBar = SkinSurface.parse(_window['topBar'], this);
  late final SkinSurface? sideBar = SkinSurface.parse(_window['sideBar'], this);
  late final SkinSurface? statusBar = SkinSurface.parse(_window['statusBar'], this);
  /// Whether the user may make the bars, rail, cards and panels clearer, so
  /// the sky or water behind shows through: `window.glass`.
  late final bool glass = _window['glass'] == true || _window['glass'] is Map;
  /// The clearest the glass may go, 0.3 to 1: `window.glass.min`, higher for
  /// a skin with dark or busy parts behind its bars.
  late final double glassMin = (_num(_map(_window['glass'])['min']) ?? 0.3).clamp(0.3, 1).toDouble();
  /// How much of the page colour lies over the backdrop under the pages,
  /// 0 to 0.9, so text there reads over a busy picture: `window.veil`.
  late final double veil = (_num(_window['veil']) ?? 0).clamp(0, 0.9).toDouble();

  void _glaze() {
    if (!glass) return;
    for (final s in [titleBar?.surface, titleBar?.inactive, menuBar?.surface, topBar, sideBar, statusBar, tabs?.bar, videoCard, panel]) {
      s?.glass = true;
    }
  }

  /// The row of pages on a phone, or in a narrow window, in place of the
  /// side rail; null keeps Lumtub's own bottom bar.
  late final SkinTabs? tabs = SkinTabs.parse(_window['tabs'], this);
  /// Icons on the top bar; colors.text unless that is hard to see on it.
  late final Color? topBarText = _readable(colorOf(_window['topBarText'], 'window.topBarText'), topBar, 'window.topBarText', fallback: colors.text, min: 3);
  /// The status line's text.
  late final Color? statusBarText = _readable(colorOf(_window['statusBarText'], 'window.statusBarText'), statusBar, 'window.statusBarText', fallback: colors.muted ?? colors.text);

  late final Map<String, Object?> _controls = _map(_raw['controls']);
  late final SkinSurface? button = SkinSurface.parse(_controls['button'], this);
  late final Color? buttonText = _readable(colorOf(_controls['buttonText']), button, 'controls.buttonText', fallback: colors.text);
  late final SkinSurface? primaryButton = SkinSurface.parse(_controls['primaryButton'], this);
  late final Color? primaryButtonText = _readable(colorOf(_controls['primaryButtonText']) ?? colors.onAccent, primaryButton, 'controls.primaryButtonText');
  late final SkinSurface? chip = SkinSurface.parse(_controls['chip'], this);
  late final SkinSurface? chipSelected = SkinSurface.parse(_controls['chipSelected'], this);
  late final Color? chipSelectedText = _readable(colorOf(_controls['chipSelectedText']), chipSelected, 'controls.chipSelectedText');
  late final SkinSurface? field = SkinSurface.parse(_controls['field'], this);
  late final SkinSurface? navSelected = SkinSurface.parse(_controls['navSelected'], this);
  late final Color? navSelectedText = _readable(colorOf(_controls['navSelectedText']), navSelected, 'controls.navSelectedText', fallback: colors.text);
  late final Color? navText = _readable(colorOf(_controls['navText']), sideBar, 'controls.navText', fallback: colors.muted ?? colors.text);

  late final Map<String, Object?> _cards = _map(_raw['cards']);
  /// What video cards sit on; null leaves them as a picture and text on the page.
  late final SkinSurface? videoCard = SkinSurface.parse(_cards['video'], this);
  /// Padding inside [videoCard].
  late final double videoCardPadding = _num(_cards['padding']) ?? 8;
  /// Dialogs, menus and panels on the watch page.
  late final SkinSurface? panel = SkinSurface.parse(_cards['panel'], this);
  /// The little label with the length on a thumbnail.
  late final SkinSurface? durationBadge = SkinSurface.parse(_cards['durationBadge'], this);
  late final Color? durationText = _readable(colorOf(_cards['durationText']), durationBadge, 'cards.durationText', fallback: Colors.white);

  late final SkinLogo logo = SkinLogo._(_map(_raw['logo']), this);
  late final SkinPlayer player = SkinPlayer._(_map(_raw['player']), this);
  late final SkinIcons icons = SkinIcons._(_map(_raw['icons']), this);
  /// What a press looks like: wash (the control darkens at once), ripple
  /// (a ring spreads from the finger) or glow (an accent-coloured wash).
  late final String press = switch (_str(_map(_raw['controls'])['press'])) {
    'ripple' => 'ripple',
    'glow' => 'glow',
    null || 'wash' => 'wash',
    final other => () {
        warn('controls.press "$other" is unknown (wash, ripple, glow)');
        return 'wash';
      }(),
  };

  /// The file a picture or font named in the skin is in.
  String file(String name) => builtIn ? '$folder/$name' : '$folder${folder.contains('\\') ? '\\' : '/'}${name.replaceAll('/', folder.contains('\\') ? '\\' : '/')}';

  void warn(String message) => warnings.add(message);

  /// What [fg] (or [fallback]) is drawn on [bg]: itself when it stands out
  /// at least [min]:1, else black or white, whichever stands out more,
  /// with a warning naming [where]. Translucent backgrounds count as laid
  /// over the page.
  Color? _readable(Color? fg, SkinSurface? bg, String where, {Color? fallback, double min = 4.5}) {
    final color = fg ?? fallback;
    if (color == null || bg?.baseColor == null) return fg;
    return readableOnAll(color, bg!.tones(colors.page), where, min: min);
  }

  Color readableOn(Color fg, Color bg, String where, {double min = 4.5}) => readableOnAll(fg, [bg], where, min: min);

  /// Like [readableOn], for a background that runs through [bgs], such as
  /// a gradient: [fg] has to stand out against every one of them.
  Color readableOnAll(Color fg, List<Color> bgs, String where, {double min = 4.5}) {
    double worst(Color c) => bgs.map((bg) => contrastRatio(Color.alphaBlend(c, bg), bg)).reduce((a, b) => a < b ? a : b);
    final ratio = worst(fg);
    if (ratio >= min) return fg;
    final better = worst(Colors.white) >= worst(Colors.black) ? Colors.white : Colors.black;
    warn('$where: ${ratio.toStringAsFixed(1)}:1 against its background, needs $min:1; drawn ${better == Colors.white ? 'white' : 'black'} instead');
    return better;
  }

  /// Reads a skin from the decoded contents of its file.
  static Skin parse(Object? json, {required String folder, required bool builtIn}) {
    if (json is! Map<String, Object?>) throw const FormatException('the file is not a JSON object');
    final version = json['lumtubSkin'];
    if (version is! num) throw const FormatException('"lumtubSkin": 1 is missing at the top');
    if (version > formatVersion) throw FormatException('made for a newer Lumtub (format $version)');
    final id = json['id'];
    if (id is! String || !RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$').hasMatch(id)) {
      throw const FormatException('"id" must be lower case letters, digits, dots, dashes or underscores');
    }
    if (json['brightness'] == 'auto') {
      Skin side(String mode) {
        final merged = _deepMerge(_withOverrides(json, formFactor), {..._map(_map(json['overrides'])[mode]), 'brightness': mode});
        return _checked(Skin._(id, merged, folder, builtIn, []));
      }
      final light = side('light'), dark = side('dark');
      light.warnings.addAll(dark.warnings.map((w) => 'dark: $w'));
      light._dark = dark;
      dark._light = light;
      return light;
    }
    return _checked(Skin._(id, _withOverrides(json, formFactor), folder, builtIn, []));
  }

  // Touch everything now, so mistakes show as warnings when it is loaded,
  // not later while drawing.
  static Skin _checked(Skin skin) {
    skin
      ..colors
      ..shape
      ..background
      ..decorations
      ..titleBar
      ..menuBar
      ..tabs
      ..icons
      ..press
      ..topBar
      ..sideBar
      ..statusBar
      ..button
      ..primaryButton
      ..chip
      ..chipSelected
      ..field
      ..navSelected
      ..videoCard
      ..panel
      ..durationBadge
      ..logo
      ..player
      ..player.deck?.glyph
      ..buttonText
      ..primaryButtonText
      ..chipSelectedText
      ..navSelectedText
      ..navText
      ..durationText
      ..topBarText
      ..statusBarText
      .._glaze();
    return skin;
  }

  /// What kind of device this is: desktop, mobile, tablet or tv. A skin's
  /// `overrides` for it are laid over the rest of the file.
  static String formFactor = 'desktop';

  static Map<String, Object?> _withOverrides(Map<String, Object?> json, String formFactor) {
    final over = _map(_map(json['overrides'])[formFactor]);
    return over.isEmpty ? json : _deepMerge(json, over);
  }

  static Map<String, Object?> _deepMerge(Map<String, Object?> base, Map<String, Object?> over) => {
        ...base,
        for (final e in over.entries)
          e.key: base[e.key] is Map<String, Object?> && e.value is Map<String, Object?> ? _deepMerge(base[e.key] as Map<String, Object?>, e.value as Map<String, Object?>) : e.value,
      };

  Color? colorOf(Object? value, [String? where]) {
    if (value == null) return null;
    final color = parseColor(value);
    if (color == null) warn('${where ?? 'color'}: "$value" is not a colour like #RRGGBB or #RRGGBBAA');
    return color;
  }
}

/// WCAG's contrast ratio of two opaque colours, 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// `#RGB`, `#RRGGBB` or `#RRGGBBAA` (alpha last, as in CSS), or
/// `transparent`.
Color? parseColor(Object? value) {
  if (value is! String) return null;
  final s = value.trim();
  if (s == 'transparent') return const Color(0x00000000);
  if (!s.startsWith('#')) return null;
  var hex = s.substring(1);
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;
  if (hex.length == 3 || hex.length == 4) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length == 6) hex = '${hex}ff';
  if (hex.length != 8) return null;
  final v = int.parse(hex, radix: 16);
  return Color(((v & 0xff) << 24) | (v >> 8));
}

class SkinColors {
  SkinColors._(Map<String, Object?> m, Skin skin) {
    page = skin.colorOf(m['page'], 'colors.page') ?? (skin.brightness == Brightness.dark ? const Color(0xFF111113) : Colors.white);
    page = Color.alphaBlend(page, skin.brightness == Brightness.dark ? Colors.black : Colors.white);
    text = skin.readableOn(skin.colorOf(m['text'], 'colors.text') ?? (skin.brightness == Brightness.dark ? Colors.white : const Color(0xFF09090B)), page, 'colors.text');
    // The accent marks icons and thin lines, which need 3:1.
    accent = skin.readableOn(skin.colorOf(m['accent'], 'colors.accent') ?? const Color(0xFFE53935), page, 'colors.accent', min: 3);
    final onAccentRaw = skin.colorOf(m['onAccent'], 'colors.onAccent');
    onAccent = onAccentRaw == null ? null : skin.readableOn(onAccentRaw, accent, 'colors.onAccent');
    final mutedRaw = skin.colorOf(m['muted'], 'colors.muted');
    muted = mutedRaw == null ? null : skin.readableOn(mutedRaw, page, 'colors.muted');
    border = skin.colorOf(m['border'], 'colors.border');
    card = skin.colorOf(m['card'], 'colors.card');
    selected = skin.colorOf(m['selected'], 'colors.selected');
    final onSelectedRaw = skin.colorOf(m['onSelected'], 'colors.onSelected');
    final chosen = selected == null ? page : Color.alphaBlend(selected!, page);
    onSelected = onSelectedRaw == null ? null : skin.readableOn(onSelectedRaw, chosen, 'colors.onSelected');
    if (selected != null && onSelectedRaw == null) skin.readableOn(text, chosen, 'colors.text on colors.selected');
    chrome = skin.colorOf(m['chrome'], 'colors.chrome');
    if (chrome != null) skin.readableOn(text, Color.alphaBlend(chrome!, page), 'colors.text on colors.chrome');
    tint = ((m['tint'] is num ? m['tint'] as num : 0).toDouble()).clamp(0.0, 0.3);
    strong = m['strong'] == true;
    final reasonRaw = skin.colorOf(m['reason'], 'colors.reason');
    reason = reasonRaw == null ? null : skin.readableOn(reasonRaw, card == null ? page : Color.alphaBlend(card!, page), 'colors.reason');
  }

  /// What the page is, where [Skin.background] does not cover it (menus,
  /// dialogs, the colour scheme's surface).
  late Color page;
  late final Color text;
  /// What is chosen, playing or in progress.
  late final Color accent;
  late final Color? onAccent;
  /// Secondary text.
  late final Color? muted;
  /// Hairlines round fields and panels.
  late final Color? border;
  /// Fields, menus and placeholders.
  late final Color? card;
  /// The background of a chosen list row.
  late final Color? selected;
  late final Color? onSelected;
  /// The line under a recommended video saying why.
  late final Color? reason;
  /// The top bar and side rail round the page, where the skin draws no
  /// surface of its own for them.
  late final Color? chrome;
  /// How much of the accent fields, menus and placeholders take on, 0–0.3.
  late final double tint;
  /// Borders and secondary text as strong as can be.
  late final bool strong;
}

class SkinShape {
  SkinShape._(Map<String, Object?> m)
      : cardRadius = _num(m['cardRadius']),
        controlRadius = _num(m['controlRadius']),
        thumbnailRadius = _num(m['thumbnailRadius']);

  /// Cards, panels, menus and dialogs.
  final double? cardRadius;
  /// Buttons, fields, chips and list rows. A large number makes pills.
  final double? controlRadius;
  final double? thumbnailRadius;
}

/// One layer of paint: a colour, a gradient, a picture or a pattern.
sealed class SkinPaint {
  const SkinPaint();

  static List<SkinPaint> listOf(Object? value, Skin skin) {
    if (value == null) return const [];
    final items = value is List ? value : [value];
    return items.map((item) => parse(item, skin)).nonNulls.toList();
  }

  static SkinPaint? parse(Object? value, Skin skin) {
    if (value is String) {
      final c = skin.colorOf(value);
      return c == null ? null : SolidPaint(c);
    }
    if (value is! Map<String, Object?>) {
      skin.warn('paint: expected a colour or an object, got $value');
      return null;
    }
    if (value['linear'] case final Map<String, Object?> m) {
      final colors = _colors(m['colors'], skin);
      if (colors.length < 2) return _bad(skin, 'linear needs at least two colours');
      return LinearPaint(_num(m['angle']) ?? 180, colors, _stops(m['stops'], colors.length, skin));
    }
    if (value['radial'] case final Map<String, Object?> m) {
      final colors = _colors(m['colors'], skin);
      if (colors.length < 2) return _bad(skin, 'radial needs at least two colours');
      final center = _list(m['center']);
      return RadialPaint(
        Offset(center.isNotEmpty ? _num(center[0]) ?? 0.5 : 0.5, center.length > 1 ? _num(center[1]) ?? 0.5 : 0.5),
        _num(m['radius']) ?? 0.5,
        colors,
        _stops(m['stops'], colors.length, skin),
      );
    }
    if (value['image'] case final String name) {
      return ImagePaint(skin.file(name), builtIn: skin.builtIn, fit: _str(value['fit']) ?? 'cover', opacity: (_num(value['opacity']) ?? 1).clamp(0, 1).toDouble());
    }
    if (value['pattern'] case final Map<String, Object?> m) {
      final color = skin.colorOf(m['color'], 'pattern.color');
      final type = _str(m['type']);
      if (color == null || type == null || !PatternPaint.types.contains(type)) return _bad(skin, 'pattern needs a type (${PatternPaint.types.join(', ')}) and a color');
      return PatternPaint(type, color, spacing: math.max(1, _num(m['spacing']) ?? 4), size: math.max(0.5, _num(m['size']) ?? 1), angle: _num(m['angle']) ?? 0);
    }
    return _bad(skin, 'paint: use "linear", "radial", "image" or "pattern"');
  }

  static SkinPaint? _bad(Skin skin, String message) {
    skin.warn(message);
    return null;
  }
}

class SolidPaint extends SkinPaint {
  const SolidPaint(this.color);
  final Color color;
}

/// A CSS-style linear gradient: 180° runs top to bottom, 90° left to right.
class LinearPaint extends SkinPaint {
  const LinearPaint(this.angle, this.colors, this.stops);
  final double angle;
  final List<Color> colors;
  final List<double>? stops;

  LinearGradient get gradient {
    final a = angle * math.pi / 180;
    final dx = math.sin(a), dy = -math.cos(a);
    return LinearGradient(begin: Alignment(-dx, -dy), end: Alignment(dx, dy), colors: colors, stops: stops);
  }
}

/// A round glow: [center] as fractions of the box (may lie outside it),
/// [radius] as a fraction of its longer side.
class RadialPaint extends SkinPaint {
  const RadialPaint(this.center, this.radius, this.colors, this.stops);
  final Offset center;
  final double radius;
  final List<Color> colors;
  final List<double>? stops;
}

class ImagePaint extends SkinPaint {
  const ImagePaint(this.path, {required this.builtIn, required this.fit, required this.opacity});
  final String path;
  final bool builtIn;
  /// cover, contain, fill or tile.
  final String fit;
  final double opacity;
}

/// A repeating pixel pattern.
class PatternPaint extends SkinPaint {
  const PatternPaint(this.type, this.color, {required this.spacing, required this.size, required this.angle});
  static const types = {'lines', 'grid', 'dots', 'checker', 'scanlines', 'stitch', 'grain'};
  final String type;
  final Color color;
  final double spacing;
  final double size;
  final double angle;
}

/// The look of a box: fill layers, edges, shadow and shine. Used for bars,
/// cards, buttons and title bars.
class SkinSurface {
  SkinSurface._({
    required this.fill,
    this.border,
    this.borderWidth = 1,
    this.borderSides,
    this.bevel,
    this.radius,
    this.shadows = const [],
    this.gloss = 0,
    this.glow,
    this.hover,
    this.pressed,
    this.focused,
  });

  /// One colour, optionally with a shine.
  factory SkinSurface.solid(Color color, {double gloss = 0}) => SkinSurface._(fill: [SolidPaint(color)], gloss: gloss);

  final List<SkinPaint> fill;
  final Color? border;
  final double borderWidth;
  /// Which sides [border] is drawn on; null for all four.
  final Set<String>? borderSides;
  final SkinBevel? bevel;
  /// Overrides the shape's radius for this box.
  final double? radius;
  final List<BoxShadow> shadows;
  /// 0–1: a white shine over the top half, as on gel buttons.
  final double gloss;
  /// A soft light round the box, as on neon.
  final Color? glow;
  final SkinSurface? hover;
  final SkinSurface? pressed;
  /// Reached with the keyboard or a TV remote's arrows.
  final SkinSurface? focused;
  /// A pane of glass: the bars, side rail, cards and panels of a skin that
  /// lets its glass be made clearer ([Skin.glass]).
  bool glass = false;

  static SkinSurface? parse(Object? value, Skin skin) {
    if (value == null) return null;
    if (value is String) {
      final paints = SkinPaint.listOf(value, skin);
      return paints.isEmpty ? null : SkinSurface._(fill: paints);
    }
    if (value is! Map<String, Object?>) {
      skin.warn('surface: expected an object, got $value');
      return null;
    }
    Color? border;
    var borderWidth = 1.0;
    Set<String>? sides;
    final b = value['border'];
    if (b is String) {
      border = skin.colorOf(b, 'border');
    } else if (b is Map<String, Object?>) {
      border = skin.colorOf(b['color'], 'border.color');
      borderWidth = _num(b['width']) ?? 1;
      if (b['sides'] is List) sides = {for (final s in b['sides'] as List) if (s is String) s};
    }
    final shadows = <BoxShadow>[
      for (final s in _list(value['shadow']))
        if (s is Map<String, Object?>)
          BoxShadow(
            color: skin.colorOf(s['color'], 'shadow.color') ?? const Color(0x40000000),
            offset: Offset(_num(s['x']) ?? 0, _num(s['y']) ?? 0),
            blurRadius: _num(s['blur']) ?? 0,
            spreadRadius: _num(s['spread']) ?? 0,
          ),
    ];
    return SkinSurface._(
      fill: SkinPaint.listOf(value['fill'], skin),
      border: border,
      borderWidth: borderWidth,
      borderSides: sides,
      bevel: SkinBevel.parse(value['bevel'], skin),
      radius: _num(value['radius']),
      shadows: shadows,
      gloss: (_num(value['gloss']) ?? 0).clamp(0, 1).toDouble(),
      glow: skin.colorOf(value['glow'], 'glow'),
      hover: SkinSurface.parse(value['hover'], skin),
      pressed: SkinSurface.parse(value['pressed'], skin),
      focused: SkinSurface.parse(value['focused'], skin),
    );
  }

  /// This surface with [over]'s fields where it has them.
  SkinSurface merge(SkinSurface? over) => over == null
      ? this
      : (SkinSurface._(
          fill: over.fill.isNotEmpty ? over.fill : fill,
          border: over.border ?? border,
          borderWidth: over.border != null ? over.borderWidth : borderWidth,
          borderSides: over.border != null ? over.borderSides : borderSides,
          bevel: over.bevel ?? bevel,
          radius: over.radius ?? radius,
          shadows: over.shadows.isNotEmpty ? over.shadows : shadows,
          gloss: over.gloss > 0 ? over.gloss : gloss,
          glow: over.glow ?? glow,
        )..glass = glass);

  /// The look while pointed at or pressed. A pressed bevel sinks in unless
  /// the skin says otherwise.
  SkinSurface forState({bool hovered = false, bool pressed = false, bool focused = false}) {
    if (focused && !pressed) return merge(this.focused ?? hover);
    if (pressed) {
      if (this.pressed != null) return merge(this.pressed);
      if (bevel case final b?) return merge(SkinSurface._(fill: const [], bevel: b.sunken()));
      return merge(hover);
    }
    return hovered ? merge(hover) : this;
  }

  /// The colour text on it is most likely read against.
  /// The colours text on this surface can land on, laid over [under]:
  /// every stop of a gradient, or the one colour.
  List<Color> tones(Color under) {
    final colors = switch (_ground) {
      SolidPaint(:final color) => [color],
      LinearPaint(:final colors) => colors,
      RadialPaint(:final colors) => colors,
      _ => const <Color>[],
    };
    return colors.isEmpty ? [under] : [for (final c in colors) Color.alphaBlend(c, under)];
  }

  /// The topmost layer that colours the whole surface; patterns and
  /// pictures over it only add lines and dots.
  SkinPaint? get _ground => fill.reversed.where((p) => p is SolidPaint || p is LinearPaint || p is RadialPaint).firstOrNull;

  Color? get baseColor => switch (_ground) {
        SolidPaint(:final color) => color,
        LinearPaint(:final colors) => Color.lerp(colors.first, colors.last, 0.5),
        RadialPaint(:final colors) => colors.last,
        _ => null,
      };
}

/// The raised or sunken edge of classic desktops: a light line top and left,
/// a dark one bottom and right, [width] pixels each, optionally doubled.
class SkinBevel {
  const SkinBevel(this.light, this.dark, {this.width = 1, this.innerLight, this.innerDark, this.sunk = false});
  final Color light;
  final Color dark;
  final double width;
  final Color? innerLight;
  final Color? innerDark;
  final bool sunk;

  SkinBevel sunken() => SkinBevel(light, dark, width: width, innerLight: innerLight, innerDark: innerDark, sunk: !sunk);

  static SkinBevel? parse(Object? value, Skin skin) {
    if (value is! Map<String, Object?>) return null;
    final light = skin.colorOf(value['light'], 'bevel.light');
    final dark = skin.colorOf(value['dark'], 'bevel.dark');
    if (light == null || dark == null) {
      skin.warn('bevel needs "light" and "dark" colours');
      return null;
    }
    return SkinBevel(light, dark,
        width: _num(value['width']) ?? 1,
        innerLight: skin.colorOf(value['innerLight'], 'bevel.innerLight'),
        innerDark: skin.colorOf(value['innerDark'], 'bevel.innerDark'),
        sunk: value['sunken'] == true);
  }
}

/// Ornaments drawn over the window's background.
sealed class SkinDecoration {
  const SkinDecoration({required this.above});
  /// Drawn over the content too (scanlines), never catching the mouse.
  final bool above;

  static SkinDecoration? parse(Object? value, Skin skin) {
    if (value is! Map<String, Object?>) return null;
    final type = _str(value['type']);
    final above = value['above'] == true;
    final color = skin.colorOf(value['color'], 'decoration.color');
    switch (type) {
      case 'bubbles':
        return BubblesDecoration(count: (_num(value['count']) ?? 8).round().clamp(1, 40), tint: color ?? const Color(0x5978DCFF), seed: (_num(value['seed']) ?? 7).round(), above: above);
      case 'sparkles':
        return SparklesDecoration(count: (_num(value['count']) ?? 6).round().clamp(1, 40), color: color ?? Colors.white, glow: skin.colorOf(value['glow'], 'sparkles.glow'), seed: (_num(value['seed']) ?? 3).round(), above: above);
      case 'perspectiveGrid':
        return PerspectiveGridDecoration(color: color ?? const Color(0x55FF3FD2), spacing: _num(value['spacing']) ?? 48, horizon: (_num(value['horizon']) ?? 0.55).clamp(0, 1).toDouble(), above: above);
      case 'beam':
        return BeamDecoration(color: color ?? const Color(0x59FFFFFF), angle: _num(value['angle']) ?? -10, position: (_num(value['position']) ?? 0.45).toDouble(), above: above);
      case 'waves':
        return WavesDecoration(count: (_num(value['count']) ?? 3).round().clamp(1, 8), color: color ?? const Color(0x4D3FC8FF), seed: (_num(value['seed']) ?? 5).round(), position: (_num(value['position']) ?? 0.8).clamp(0, 1).toDouble(), above: above);
      case 'scene':
        final name = _str(value['scene']);
        if (!sceneNames.contains(name)) {
          skin.warn('scene "$name" is unknown (${sceneNames.join(', ')})');
          return null;
        }
        return SceneDecoration(scene: name!, night: value['night'] == true, seed: (_num(value['seed']) ?? 3).round(), above: false);
      case 'pattern':
        final paint = SkinPaint.parse({'pattern': {...value, 'type': value['pattern']}}, skin);
        return paint is PatternPaint ? PatternDecoration(paint, fade: _str(value['fade']), above: above) : null;
    }
    skin.warn('decoration type "$type" is unknown (scene, bubbles, sparkles, perspectiveGrid, beam, waves, pattern)');
    return null;
  }
}

class BubblesDecoration extends SkinDecoration {
  const BubblesDecoration({required this.count, required this.tint, required this.seed, required super.above});
  final int count;
  final Color tint;
  final int seed;
}

class SparklesDecoration extends SkinDecoration {
  const SparklesDecoration({required this.count, required this.color, this.glow, required this.seed, required super.above});
  final int count;
  final Color color;
  final Color? glow;
  final int seed;
}

class PerspectiveGridDecoration extends SkinDecoration {
  const PerspectiveGridDecoration({required this.color, required this.spacing, required this.horizon, required super.above});
  final Color color;
  final double spacing;
  /// Where the horizon is, as a fraction of the window's height.
  final double horizon;
}

class BeamDecoration extends SkinDecoration {
  const BeamDecoration({required this.color, required this.angle, required this.position, required super.above});
  final Color color;
  final double angle;
  final double position;
}

/// Glossy ribbons swept across the window, as on the water and glass
/// wallpapers of the late 2000s.
/// The landscapes a skin can have painted behind it.
const sceneNames = ['meadow', 'sky', 'underwater', 'aurora', 'city', 'collage'];

/// A whole landscape behind everything: lib/ui/skin_scenes.dart.
class SceneDecoration extends SkinDecoration {
  const SceneDecoration({required this.scene, required this.night, required this.seed, required super.above});
  final String scene;
  final bool night;
  final int seed;
}

class WavesDecoration extends SkinDecoration {
  const WavesDecoration({required this.count, required this.color, required this.seed, required this.position, required super.above});
  final int count;
  final Color color;
  final int seed;
  /// Where the ribbons sit, from 0 (top) to 1 (bottom).
  final double position;
}

class PatternDecoration extends SkinDecoration {
  const PatternDecoration(this.paint, {this.fade, required super.above});
  final PatternPaint paint;
  /// top or bottom: the pattern fades out towards that edge.
  final String? fade;
}

/// The title bar the app draws itself, with its window buttons.
class SkinTitleBar {
  SkinTitleBar._(this.height, this.surface, this.inactive, this.text, this.inactiveText, this.align, this.button, this.buttonIcon, this.closeButton, this.buttonSize, this.buttonsLeft, this.icon, this.minimizeButton, this.maximizeButton, this.glyphsOnHover, this.buttonsSplit, this.classicGlyphs, this.titlePlate);
  final double height;
  final SkinSurface surface;
  final SkinSurface? inactive;
  final Color text;
  final Color? inactiveText;
  /// left or center.
  final String align;
  final SkinSurface? button;
  final Color buttonIcon;
  final SkinSurface? closeButton;
  final Size buttonSize;
  /// Close, minimise and maximise at the left, in that order, as on the
  /// desktops of around 2001; otherwise minimise, maximise, close at the
  /// right.
  final bool buttonsLeft;
  /// Whether the app's icon is drawn at the start.
  final bool icon;
  /// Looks of their own for minimise and maximise; [button] when null.
  final SkinSurface? minimizeButton;
  final SkinSurface? maximizeButton;
  /// The signs on the buttons show only under the pointer.
  final bool glyphsOnHover;
  /// Close alone at the left, minimise and maximise at the right, as on
  /// the desktops of the late 1980s and 1990s.
  final bool buttonsSplit;
  /// The plain boxes of those desktops: an empty close box, a box in a box
  /// to maximise and two lines to minimise.
  final bool classicGlyphs;
  /// A plain patch under the title, so it stands clear of stripes.
  final Color? titlePlate;

  static SkinTitleBar? parse(Object? value, Skin skin) {
    if (value is! Map<String, Object?> || value['enabled'] == false) return null;
    final buttons = _map(value['buttons']);
    final size = _list(buttons['size']);
    final surface = SkinSurface.parse(value['surface'], skin) ?? SkinSurface._(fill: [SolidPaint(skin.colors.chrome ?? skin.colors.page)]);
    final inactive = SkinSurface.parse(value['inactive'], skin);
    final page = skin.colors.page;
    final bar = surface.tones(page);
    final barMid = Color.alphaBlend(surface.baseColor ?? page, page);
    final buttonSurface = SkinSurface.parse(buttons['surface'], skin);
    final inactiveText = skin.colorOf(value['inactiveText'], 'titleBar.inactiveText');
    return SkinTitleBar._(
      (_num(value['height']) ?? 30).clamp(20, 60).toDouble(),
      surface,
      inactive,
      skin.readableOnAll(skin.colorOf(value['text'], 'titleBar.text') ?? skin.colors.text, bar, 'titleBar.text'),
      inactiveText == null ? null : skin.readableOnAll(inactiveText, (inactive ?? surface).tones(page), 'titleBar.inactiveText', min: 3),
      _str(value['align']) == 'center' ? 'center' : 'left',
      buttonSurface,
      skin.readableOnAll(skin.colorOf(buttons['icon'], 'titleBar.buttons.icon') ?? skin.colors.text, (buttonSurface?.baseColor?.a ?? 0) == 0 ? bar : buttonSurface!.tones(barMid), 'titleBar.buttons.icon', min: 3),
      SkinSurface.parse(buttons['close'], skin),
      Size(size.isNotEmpty ? _num(size[0]) ?? 40 : 40, size.length > 1 ? _num(size[1]) ?? 24 : 24),
      _str(buttons['placement']) == 'left',
      value['icon'] != false,
      SkinSurface.parse(buttons['minimize'], skin),
      SkinSurface.parse(buttons['maximize'], skin),
      _str(buttons['glyphs']) == 'hover',
      _str(buttons['placement']) == 'split',
      _str(buttons['glyphs']) == 'classic',
      skin.colorOf(value['titlePlate'], 'titleBar.titlePlate'),
    );
  }
}

/// The pages as tabs on a phone: along the bottom, as on the phones of
/// around 2010 with a glossy bar and a lit square round the page shown, or
/// under the top bar, as words with a line under the page shown.
class SkinTabs {
  SkinTabs._(this.top, this.bar, this.selected, this.text, this.selectedText, this.indicator, this.textOnly, this.caps, this.height);
  /// Under the top bar instead of along the bottom.
  final bool top;
  final SkinSurface bar;
  /// What the page shown sits on; null for nothing but [indicator].
  final SkinSurface? selected;
  final Color text;
  final Color selectedText;
  /// A line under the page shown (at the top edge of the item for a
  /// bottom bar).
  final Color? indicator;
  /// Words only, no icons.
  final bool textOnly;
  /// Words in capitals.
  final bool caps;
  final double height;

  static SkinTabs? parse(Object? value, Skin skin) {
    if (value is! Map<String, Object?> || value['enabled'] == false) return null;
    final top = switch (_str(value['position'])) {
      'top' => true,
      null || 'bottom' => false,
      final other => () {
          skin.warn('window.tabs.position "$other" is unknown (bottom, top)');
          return false;
        }(),
    };
    final page = skin.colors.page;
    final bar = SkinSurface.parse(value['surface'], skin) ?? SkinSurface._(fill: [SolidPaint(skin.colors.chrome ?? skin.colors.card ?? page)]);
    final selected = SkinSurface.parse(value['selected'], skin);
    final barMid = Color.alphaBlend(bar.baseColor ?? page, page);
    final text = skin.readableOnAll(skin.colorOf(value['text'], 'window.tabs.text') ?? skin.colors.muted ?? skin.colors.text, bar.tones(page), 'window.tabs.text');
    final selectedText = skin.readableOnAll(
      skin.colorOf(value['selectedText'], 'window.tabs.selectedText') ?? skin.colors.accent,
      selected?.tones(barMid) ?? bar.tones(page),
      'window.tabs.selectedText',
      min: 3,
    );
    final indicator = skin.colorOf(value['indicator'], 'window.tabs.indicator');
    return SkinTabs._(
      top,
      bar,
      selected,
      text,
      selectedText,
      indicator,
      _str(value['labels']) == 'text',
      value['caps'] == true,
      (_num(value['height']) ?? (top ? 44 : 56)).clamp(32, 80).toDouble(),
    );
  }
}

/// A row of text menus (File, View, Help…) drawn by the app.
class SkinMenuBar {
  SkinMenuBar._(this.surface, this.text, this.highlight, this.highlightText, this.menu, this.underlineKeys, this.clock, this.top, this.appMenu, this.height);
  final SkinSurface? surface;
  final Color text;
  final SkinSurface? highlight;
  final Color? highlightText;
  /// The drop-down menus.
  final SkinSurface? menu;
  /// Underlines each menu's access key, opened with Alt and that letter.
  final bool underlineKeys;
  /// A clock at the right end.
  final bool clock;
  /// Drawn above the title bar, along the top of the window, as on a
  /// desktop whose menus sit at the top of the screen.
  final bool top;
  /// A first menu named after the app, in bold, holding About, Settings
  /// and Quit.
  final bool appMenu;
  final double height;

  static SkinMenuBar? parse(Object? value, Skin skin) {
    if (value is! Map<String, Object?> || value['enabled'] == false) return null;
    final chrome = skin.colors.chrome;
    final surface = SkinSurface.parse(value['surface'], skin) ?? (chrome == null ? null : SkinSurface._(fill: [SolidPaint(chrome)]));
    final highlight = SkinSurface.parse(value['highlight'], skin);
    List<Color> on(SkinSurface? s) => s?.tones(skin.colors.page) ?? [skin.colors.page];
    final highlightText = skin.colorOf(value['highlightText'], 'menuBar.highlightText');
    final text = skin.readableOnAll(skin.colorOf(value['text'], 'menuBar.text') ?? skin.colors.text, on(surface), 'menuBar.text');
    return SkinMenuBar._(
      surface,
      text,
      highlight,
      highlight == null ? highlightText : skin.readableOnAll(highlightText ?? text, on(highlight), 'menuBar.highlightText'),
      SkinSurface.parse(value['menu'], skin),
      value['underlineKeys'] != false,
      value['clock'] == true,
      _str(value['position']) == 'top',
      value['appMenu'] == true,
      (_num(value['height']) ?? 26).clamp(18, 40).toDouble(),
    );
  }
}

class SkinLogo {
  SkinLogo._(Map<String, Object?> m, Skin skin)
      : text = _str(m['text']),
        font = _str(m['font']),
        size = _num(m['size']),
        fill = SkinPaint.listOf(m['fill'], skin),
        stroke = skin.colorOf(m['stroke'], 'logo.stroke'),
        shadow = skin.colorOf(m['shadow'], 'logo.shadow'),
        glow = skin.colorOf(m['glow'], 'logo.glow'),
        badge = SkinSurface.parse(m['badge'], skin),
        badgeIcon = skin.colorOf(m['badgeIcon'], 'logo.badgeIcon');

  /// What is written next to the badge; null for the app's name.
  final String? text;
  final String? font;
  final double? size;
  /// Paint for the letters: a colour or a gradient.
  final List<SkinPaint> fill;
  final Color? stroke;
  final Color? shadow;
  final Color? glow;
  /// The round or square mark with the play triangle.
  final SkinSurface? badge;
  final Color? badgeIcon;
}

/// How icons are drawn: outlined or filled, and with a raised, glossy or
/// glowing finish for a skeuomorphic look.
class SkinIcons {
  SkinIcons._(Map<String, Object?> m, Skin skin)
      : filled = _str(m['style']) == 'fill',
        effect = switch (_str(m['effect'])) {
          final e? when const ['emboss', 'engrave', 'gel', 'glow'].contains(e) => e,
          final e? when e != 'none' => _unknownEffect(skin, e),
          _ => 'none',
        },
        glow = skin.colorOf(m['glow'], 'icons.glow');

  static String _unknownEffect(Skin skin, String effect) {
    skin.warn('icons.effect "$effect" is unknown (none, emboss, engrave, gel, glow)');
    return 'none';
  }

  /// Every icon in its filled form.
  final bool filled;
  /// none, emboss (lit from above, raised), engrave (pressed in), gel (a
  /// soft shine and shadow) or glow.
  final String effect;
  /// The glow's colour; the accent when left out.
  final Color? glow;

  /// The shadows that give icons their finish, on [page] colours with
  /// [accent] for the glow.
  List<Shadow>? shadows(Brightness brightness, Color accent) {
    final dark = brightness == Brightness.dark;
    final light = Colors.white.withValues(alpha: dark ? 0.25 : 0.85);
    final shade = Colors.black.withValues(alpha: dark ? 0.7 : 0.35);
    return switch (effect) {
      'emboss' => [Shadow(color: light, offset: const Offset(-0.6, -0.8)), Shadow(color: shade, offset: const Offset(0.6, 1), blurRadius: 1)],
      'engrave' => [Shadow(color: shade, offset: const Offset(0, -0.8)), Shadow(color: light, offset: const Offset(0, 1))],
      'gel' => [Shadow(color: shade.withValues(alpha: shade.a * 0.8), offset: const Offset(0, 1.5), blurRadius: 2.5), Shadow(color: light, offset: const Offset(0, -0.5), blurRadius: 0.5)],
      'glow' => [Shadow(color: (glow ?? accent).withValues(alpha: 0.85), blurRadius: 6)],
      _ => null,
    };
  }
}

class SkinPlayer {
  SkinPlayer._(Map<String, Object?> m, Skin skin)
      : style = switch (_str(m['style'])) { 'lcd' => 'lcd', 'deck' => 'deck', _ => 'default' },
        deck = _str(m['style']) == 'deck' ? SkinDeck._(_map(m['deck']), skin) : null,
        frame = SkinSurface.parse(m['frame'], skin),
        progress = SkinPaint.listOf(m['progress'], skin),
        lcd = SkinSurface.parse(m['lcd'], skin),
        lcdText = skin.colorOf(m['lcdText'], 'player.lcdText') ?? const Color(0xFF7DFF5A),
        lcdAccent = skin.colorOf(m['lcdAccent'], 'player.lcdAccent') ?? const Color(0xFFFFB02E),
        spectrum = m['spectrum'] != false,
        lcdFont = _str(m['lcdFont']) ?? 'VT323';

  /// default, or lcd: a display with the time, scrolling title and a
  /// spectrum under the picture, as on late-90s media players; or deck: a
  /// player body of its own under the picture ([deck]).
  final String style;
  final SkinDeck? deck;
  /// What surrounds the picture on the watch page.
  final SkinSurface? frame;
  /// The played part of the progress bar.
  final List<SkinPaint> progress;
  final SkinSurface? lcd;
  final Color lcdText;
  final Color lcdAccent;
  final bool spectrum;
  /// The display's face; VT323 comes with Lumtub.
  final String lcdFont;
}

/// The body a "deck" player is drawn as, under the picture: its outline,
/// what it is made of, its little screen and its buttons.
class SkinDeck {
  SkinDeck._(Map<String, Object?> m, Skin skin)
      : shape = switch (_str(m['shape'])) {
          final s? when shapes.contains(s) => s,
          final s? => () {
              skin.warn('player.deck.shape "$s" is unknown (${shapes.join(', ')})');
              return 'capsule';
            }(),
          _ => 'capsule',
        },
        body = _orDefault(_colors(m['body'], skin), const [Color(0xFFF6F8FA), Color(0xFFC9D2DC), Color(0xFF9AA6B4)]),
        rim = skin.colorOf(m['rim'], 'player.deck.rim') ?? const Color(0xFF7F8C9C),
        clear = (_num(m['clear']) ?? 0).clamp(0, 0.8).toDouble(),
        screen = skin.colorOf(m['screen'], 'player.deck.screen') ?? const Color(0xFF0B3A66),
        button = _orDefault(_colors(m['button'], skin), const [Color(0xFFBFE8FF), Color(0xFF2A7AD0)]),
        play = _orDefault(_colors(m['play'], skin), const [Color(0xFFD8FFD0), Color(0xFF2E9A2E)]),
        groove = skin.colorOf(m['groove'], 'player.deck.groove') ?? const Color(0xFF5A6878),
        fill = skin.colorOf(m['fill'], 'player.deck.fill') ?? const Color(0xFF3AB0FF),
        speakers = m['speakers'] == true,
        glow = skin.colorOf(m['glow'], 'player.deck.glow') {
    screenText = skin.readableOn(skin.colorOf(m['screenText'], 'player.deck.screenText') ?? const Color(0xFF9FE8FF), screen, 'player.deck.screenText');
    glyph = skin.readableOnAll(skin.colorOf(m['glyph'], 'player.deck.glyph') ?? const Color(0xFFFFFFFF), underGlyph(button), 'player.deck.glyph', min: 3);
    playGlyph = skin.readableOnAll(skin.colorOf(m['playGlyph'], 'player.deck.playGlyph') ?? const Color(0xFFFFFFFF), underGlyph(play), 'player.deck.playGlyph', min: 3);
  }

  static const shapes = ['capsule', 'slab', 'wave', 'boombox', 'oval'];

  /// What a button's sign lies on: the deep colour in the middle, and where
  /// the light colour glowing up from the bottom reaches it.
  static List<Color> underGlyph(List<Color> button) => [button.last, Color.lerp(button.last, button.first, 0.3)!];

  /// capsule: a pill with round ends; slab: a flat, square-cornered unit;
  /// wave: its top edge rolls like water; boombox: a carry handle and round
  /// speakers at both ends; oval: a wide ellipse with the buttons in a
  /// round cluster.
  final String shape;
  /// The body's colours from top to bottom: metal, pearl or plastic.
  final List<Color> body;
  final Color rim;
  /// How see-through the body is, 0 to 0.8, as tinted clear plastic.
  final double clear;
  final Color screen;
  late final Color screenText;
  /// The small round buttons, top to bottom.
  final List<Color> button;
  late final Color glyph;
  /// The big play button.
  final List<Color> play;
  late final Color playGlyph;
  final Color groove;
  final Color fill;
  final bool speakers;
  /// A light round the buttons, as smoked glass skins have.
  final Color? glow;
}

List<Color> _orDefault(List<Color> colors, List<Color> fallback) => colors.length >= 2 ? colors : colors.length == 1 ? [colors.first, colors.first] : fallback;

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
double? _num(Object? v) => v is num ? v.toDouble() : null;
Map<String, Object?> _map(Object? v) => v is Map<String, Object?> ? v : const {};
List<Object?> _list(Object? v) => v is List ? v : const [];
Map<String, String> _strings(Object? v) => {
      if (v is Map<String, Object?>)
        for (final e in v.entries)
          if (e.value is String) e.key: e.value as String,
    };

String? _localized(Map<String, String> m, String language) => m[language] ?? m[language.split('-').first];

List<Color> _colors(Object? v, Skin skin) => _list(v).map((c) => skin.colorOf(c, 'gradient colour')).nonNulls.toList();

List<double>? _stops(Object? v, int count, Skin skin) {
  final stops = [for (final s in _list(v)) if (s is num) s.toDouble()];
  if (stops.isEmpty) return null;
  if (stops.length != count) {
    skin.warn('a gradient has ${stops.length} stops for $count colours; stops left out');
    return null;
  }
  return stops;
}
