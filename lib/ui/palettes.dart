import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// One side of a [Palette]: the page, its text and the accent. Every other
/// surface, border and secondary text is the text colour laid over the page
/// at a fixed strength, so all palettes keep the same steps as the neutral
/// one.
class PaletteTones {
  const PaletteTones(this.page, this.text, this.accent);
  final Color page;
  final Color text;
  final Color accent;

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

/// Lumtub's palettes besides the default neutral one. Text on its page is
/// at least 12:1 and secondary text and the accent at least 4.5:1 in both
/// modes.
const palettes = [
  Palette('ricePaper', '宣纸', '暖白纸色，长时间看不刺眼', PaletteTones(Color(0xFFF6F1E7), Color(0xFF2A251E), Color(0xFFA8432C)), PaletteTones(Color(0xFF1B1814), Color(0xFFEAE2D3), Color(0xFFD9775B))),
  Palette('candlelight', '烛光', '晚上用，少蓝光的琥珀色', PaletteTones(Color(0xFFFBF3E4), Color(0xFF3A2A17), Color(0xFF965010)), PaletteTones(Color(0xFF17110B), Color(0xFFF0DDBF), Color(0xFFE39B45))),
  Palette('inkBamboo', '墨竹', '带一点绿意的淡墨色', PaletteTones(Color(0xFFF2F4EF), Color(0xFF1C231E), Color(0xFF2F7352)), PaletteTones(Color(0xFF111512), Color(0xFFE1E8E2), Color(0xFF69B98C))),
  Palette('rime', '雾凇', '清冷的冰蓝', PaletteTones(Color(0xFFF4F8FA), Color(0xFF142027), Color(0xFF0B7896)), PaletteTones(Color(0xFF0C1418), Color(0xFFDCEBF1), Color(0xFF4FC0DE))),
  Palette('pineSoot', '松烟', '沉稳的石板蓝灰', PaletteTones(Color(0xFFF1F3F6), Color(0xFF1A2029), Color(0xFF3E64A8)), PaletteTones(Color(0xFF12161C), Color(0xFFDFE5EE), Color(0xFF7FA3E6))),
  Palette('nightVoyage', '夜航', '深海军蓝配琥珀灯', PaletteTones(Color(0xFFF3F5FA), Color(0xFF141B2E), Color(0xFF2F4FB0)), PaletteTones(Color(0xFF0B1124), Color(0xFFE2E7F5), Color(0xFFF2B04A))),
  Palette('duskHills', '暮山', '傍晚山色的灰紫', PaletteTones(Color(0xFFF5F3F8), Color(0xFF221D2C), Color(0xFF6B4FB8)), PaletteTones(Color(0xFF15121B), Color(0xFFE8E3F0), Color(0xFFA98BEA))),
  Palette('fallingPetals', '樱落', '柔和的樱花粉', PaletteTones(Color(0xFFFBF4F5), Color(0xFF2C1E22), Color(0xFFB33A60)), PaletteTones(Color(0xFF1A1215), Color(0xFFF2E2E7), Color(0xFFEE7FA0))),
  Palette('sandstone', '砂岩', '赤陶与暖沙', PaletteTones(Color(0xFFF7F2EE), Color(0xFF2B211B), Color(0xFFA64D24)), PaletteTones(Color(0xFF1A1411), Color(0xFFEFE3DA), Color(0xFFE58B5C))),
  Palette('highContrast', '高对比', '纯黑纯白，边框和文字最清楚', PaletteTones(Color(0xFFFFFFFF), Color(0xFF000000), Color(0xFF0047CC)), PaletteTones(Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFFFFD60A)), strong: true),
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
  return tonal.copyWith(
    primary: accent,
    onPrimary: onAccent,
    primaryContainer: Color.lerp(page, accent, dark ? 0.18 : 0.10),
    onPrimaryContainer: t.text,
    secondary: over(0.85),
    onSecondary: page,
    secondaryContainer: over(dark ? 0.10 : 0.05),
    onSecondaryContainer: t.text,
    tertiaryContainer: over(dark ? 0.10 : 0.05),
    onTertiaryContainer: t.text,
    surface: page,
    onSurface: t.text,
    onSurfaceVariant: over(strong ? 0.85 : 0.70),
    surfaceDim: dark ? page : over(0.05),
    surfaceBright: dark ? over(0.12) : page,
    surfaceContainerLowest: page,
    surfaceContainerLow: over(dark ? 0.03 : 0.025),
    surfaceContainer: over(dark ? 0.06 : 0.05),
    surfaceContainerHigh: over(dark ? 0.08 : 0.05),
    surfaceContainerHighest: over(dark ? 0.12 : 0.11),
    outline: over(strong ? 0.75 : 0.45),
    outlineVariant: over(strong ? 0.45 : (dark ? 0.12 : 0.11)),
    inverseSurface: t.text,
    onInverseSurface: page,
    surfaceTint: Colors.transparent,
    shadow: Colors.black,
  );
}
