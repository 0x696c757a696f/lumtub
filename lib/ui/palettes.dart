import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// One side of a [Palette]. The page, its text and the accent; optionally
/// [chrome], the top bar and side rail around the page, [card], what fields,
/// menus and placeholders start from instead of the page, and [glow], how
/// much of the accent they take on. Secondary text and borders are the
/// text laid over the page at the neutral scheme's steps.
class PaletteTones {
  const PaletteTones(this.page, this.text, this.accent, {this.chrome, this.card, this.glow = 0, this.indicator});
  final Color page;
  final Color text;
  final Color accent;
  final Color? chrome;
  final Color? card;
  final double glow;
  /// The chosen item in the side rail and lists, when not a wash of the text.
  final Color? indicator;

  Color over(double strength, {Color? on}) => Color.lerp(on ?? page, text, strength)!;
}

/// A named colour scheme for the whole window, light and dark.
class Palette {
  const Palette(this.id, this._name, this._mood, this.light, this.dark, {this.strong = false});
  final String id;
  final String _name;
  final String _mood;
  String get name => tr(_name);
  /// What it is for, in a few words.
  String get mood => tr(_mood);
  final PaletteTones light;
  final PaletteTones dark;
  /// Borders and secondary text as strong as can be, for 高对比.
  final bool strong;

  PaletteTones of(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}

/// Lumtub's palettes besides the default neutral one, each with its own
/// character: a deeper margin round paper, cards brighter than the page
/// like frost, a navy rail. Text on its page is at least 12:1 and
/// secondary text and the accent at least 4.5:1 in both modes.
const palettes = [
  // Paper with a deeper margin and a vermilion seal.
  Palette('ricePaper', 'Rice Paper', 'Warm paper with a vermilion seal and a deeper margin',
      PaletteTones(Color(0xFFF4ECDC), Color(0xFF2A241C), Color(0xFFA3402A), chrome: Color(0xFFEADFC8), indicator: Color(0xFFE2D3B6)),
      PaletteTones(Color(0xFF1E1A15), Color(0xFFEAE1D0), Color(0xFFDB7A5E), chrome: Color(0xFF16130F), indicator: Color(0xFF332B22))),
  // Everything glows a little amber.
  Palette('candlelight', 'Candlelight', 'For evenings: little blue, a touch of amber everywhere',
      PaletteTones(Color(0xFFF8ECD6), Color(0xFF33230F), Color(0xFF8F4C0E), glow: 0.10, indicator: Color(0xFFF0D9AE)),
      PaletteTones(Color(0xFF1B130A), Color(0xFFF0DCBC), Color(0xFFE6A04A), glow: 0.10, indicator: Color(0xFF3A2711))),
  // Rice paper cards on a bamboo-green page, ink text.
  Palette('inkBamboo', 'Ink Bamboo', 'Plain white cards on bamboo green',
      PaletteTones(Color(0xFFE9EFE6), Color(0xFF18201B), Color(0xFF2B6E4E), card: Color(0xFFF6F8F3), chrome: Color(0xFFDDE7D9), indicator: Color(0xFFCFE0CB)),
      PaletteTones(Color(0xFF111813), Color(0xFFDFE8E1), Color(0xFF6CBC8F), card: Color(0xFF1A231D), chrome: Color(0xFF0C120E), indicator: Color(0xFF223A2B))),
  // Frost: cards brighter than the page.
  Palette('rime', 'Rime', 'Ice blue, with cards bright as frost',
      PaletteTones(Color(0xFFE6EFF4), Color(0xFF13202A), Color(0xFF0A7391), card: Color(0xFFFAFDFE), indicator: Color(0xFFCFE6EF)),
      PaletteTones(Color(0xFF0D1920), Color(0xFFDAEBF2), Color(0xFF52C3E0), card: Color(0xFF16262F), indicator: Color(0xFF1C3A47))),
  // Slate: a cool grey rail and bar round a lighter page.
  Palette('pineSoot', 'Pine Soot', 'Slate blue-grey, with a deeper side rail and top bar',
      PaletteTones(Color(0xFFEEF1F5), Color(0xFF19202A), Color(0xFF3B61A4), chrome: Color(0xFFDFE5ED), indicator: Color(0xFFCCD6E4)),
      PaletteTones(Color(0xFF161C25), Color(0xFFDFE5EE), Color(0xFF82A6E8), chrome: Color(0xFF10151C), indicator: Color(0xFF26324A))),
  // Navy through and through, amber lights at night.
  Palette('nightVoyage', 'Night Voyage', 'A navy cabin with amber lamps at night',
      PaletteTones(Color(0xFFEDF0F8), Color(0xFF131A2D), Color(0xFF2C4BAA), chrome: Color(0xFFDDE3F2), glow: 0.05, indicator: Color(0xFFCCD5EE)),
      PaletteTones(Color(0xFF0D1631), Color(0xFFE2E7F5), Color(0xFFF2B04A), chrome: Color(0xFF09102A), card: Color(0xFF15204A), indicator: Color(0xFF2A2F4A))),
  // Violet hills with a peach sky for what is chosen.
  Palette('duskHills', 'Dusk Hills', 'Grey-violet hills, with a sunset glow on what is chosen',
      PaletteTones(Color(0xFFF0EBF4), Color(0xFF221C2C), Color(0xFF6A4DB5), chrome: Color(0xFFE5DDEE), indicator: Color(0xFFF5DCCF)),
      PaletteTones(Color(0xFF181322), Color(0xFFE8E2F0), Color(0xFFAC8EEC), chrome: Color(0xFF120E1A), indicator: Color(0xFF3E2C3A))),
  // White petals on a blush page.
  Palette('fallingPetals', 'Falling Petals', 'Pale blush, with cards like white petals',
      PaletteTones(Color(0xFFF8ECEF), Color(0xFF2C1D22), Color(0xFFAE375C), card: Color(0xFFFFFAFB), indicator: Color(0xFFF3D3DC)),
      PaletteTones(Color(0xFF1E1418), Color(0xFFF2E1E6), Color(0xFFF083A3), card: Color(0xFF2A1C22), indicator: Color(0xFF45252F))),
  // Sand with terracotta warmth in everything raised.
  Palette('sandstone', 'Sandstone', 'Warm sand, with terracotta in what is raised',
      PaletteTones(Color(0xFFF3E9DF), Color(0xFF2B2019), Color(0xFFA14A22), chrome: Color(0xFFE9DACB), glow: 0.06, indicator: Color(0xFFEBCDB8)),
      PaletteTones(Color(0xFF1E1611), Color(0xFFEFE2D8), Color(0xFFE88E5F), chrome: Color(0xFF17100C), glow: 0.06, indicator: Color(0xFF3F2619))),
  Palette('highContrast', 'High Contrast', 'Pure black and white, the clearest text and borders', PaletteTones(Color(0xFFFFFFFF), Color(0xFF000000), Color(0xFF0047CC)), PaletteTones(Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFFFFD60A)), strong: true),
];

/// The palette [id] names, none for the default neutral one.
Palette? paletteOf(String id) => palettes.where((p) => p.id == id).firstOrNull;

/// [tonal] restyled with [palette]'s colours; [pureBlack] turns a dark page black.
ColorScheme paletteScheme(ColorScheme tonal, Palette palette, Brightness brightness, {required bool pureBlack}) {
  final dark = brightness == Brightness.dark;
  final t = palette.of(brightness);
  final page = dark && pureBlack ? Colors.black : t.page;
  Color over(double strength) => t.over(strength, on: page);
  final strong = palette.strong;
  final accent = t.accent;
  // Black or white on the accent, whichever stands out more.
  final light = accent.computeLuminance();
  final onAccent = (1.05 / (light + 0.05)) >= ((light + 0.05) / 0.05) ? Colors.white : Colors.black;
  final base = t.card ?? page;
  // What fields, menus and placeholders are made of: [base], a little of
  // the text over it, and as much of the accent as the palette glows with.
  Color raised(double strength) => Color.lerp(Color.lerp(base, t.text, strength)!, accent, t.glow)!;
  final chosen = t.indicator ?? over(dark ? 0.10 : 0.05);
  return tonal.copyWith(
    primary: accent,
    onPrimary: onAccent,
    primaryContainer: Color.lerp(page, accent, dark ? 0.18 : 0.10),
    onPrimaryContainer: t.text,
    secondary: over(0.85),
    onSecondary: page,
    secondaryContainer: chosen,
    onSecondaryContainer: t.text,
    tertiaryContainer: chosen,
    onTertiaryContainer: t.text,
    surface: page,
    onSurface: t.text,
    onSurfaceVariant: over(strong ? 0.85 : 0.70),
    surfaceDim: dark ? page : over(0.05),
    surfaceBright: dark ? over(0.12) : page,
    surfaceContainerLowest: t.card ?? page,
    surfaceContainerLow: raised(dark ? 0.03 : 0.02),
    surfaceContainer: raised(dark ? 0.06 : 0.04),
    surfaceContainerHigh: raised(dark ? 0.08 : 0.05),
    surfaceContainerHighest: raised(dark ? 0.12 : 0.09),
    outline: over(strong ? 0.75 : 0.45),
    outlineVariant: strong ? over(0.45) : Color.lerp(over(dark ? 0.13 : 0.12), accent, 0.08),
    inverseSurface: t.text,
    onInverseSurface: page,
    surfaceTint: Colors.transparent,
    shadow: Colors.black,
  );
}

/// The top bar and side rail of [palette], none where they are the page.
Color? paletteChrome(Palette? palette, Brightness brightness, {required bool pureBlack}) {
  if (palette == null || (brightness == Brightness.dark && pureBlack)) return null;
  return palette.of(brightness).chrome;
}
