import 'package:flutter/material.dart';

import '../appearance_settings.dart';
import 'app_icons.dart';
import 'palettes.dart';

/// A [ThemePreset] drawn as a small window in its light and its dark
/// colours side by side, with its name under it.
class ThemePresetCard extends StatelessWidget {
  const ThemePresetCard({super.key, required this.preset, required this.selected, required this.onTap});
  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  ColorScheme _scheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: Color(preset.seed), brightness: brightness, dynamicSchemeVariant: preset.variant);
    return brightness == Brightness.dark && preset.pureBlack ? scheme.copyWith(surface: Colors.black, surfaceContainer: const Color(0xFF121212)) : scheme;
  }

  @override
  Widget build(BuildContext context) => SchemeCard(name: preset.name, light: _scheme(Brightness.light), dark: _scheme(Brightness.dark), selected: selected, onTap: onTap);
}

/// A [Palette] as a [SchemeCard], with what it is for under its name.
class PaletteCard extends StatelessWidget {
  const PaletteCard({super.key, required this.palette, required this.selected, required this.onTap});
  final Palette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SchemeCard(
        name: palette.name,
        note: palette.mood,
        light: paletteScheme(const ColorScheme.light(), palette, Brightness.light, pureBlack: false),
        dark: paletteScheme(const ColorScheme.dark(), palette, Brightness.dark, pureBlack: false),
        selected: selected,
        onTap: onTap,
      );
}

/// A small window in a light and a dark scheme side by side, with a name under it.
class SchemeCard extends StatelessWidget {
  const SchemeCard({super.key, required this.name, this.note, required this.light, required this.dark, required this.selected, required this.onTap});
  final String name;
  final String? note;
  final ColorScheme light;
  final ColorScheme dark;
  final bool selected;
  final VoidCallback onTap;

  Widget _half(ColorScheme scheme) => Expanded(
        child: Container(
          color: scheme.surface,
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 6, width: 30, decoration: BoxDecoration(color: scheme.onSurface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 4),
            Container(
              height: 22,
              decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(4)),
              padding: const EdgeInsets.all(4),
              child: Row(children: [
                Container(width: 14, decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 4),
                Expanded(child: Container(height: 4, decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2)))),
              ]),
            ),
            const Spacer(),
            Row(children: [
              Container(height: 12, width: 28, decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(6))),
              const SizedBox(width: 4),
              Container(height: 12, width: 18, decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(6))),
            ]),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 150,
          child: Column(children: [
            Container(
              height: 84,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: selected ? colors.primary : colors.outlineVariant, width: selected ? 2.5 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_half(light), _half(dark)]),
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (selected) ...[Icon(AppIcons.checkCircleFill, size: 14, color: colors.primary), const SizedBox(width: 4)],
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: selected ? colors.primary : colors.onSurfaceVariant, fontWeight: selected ? FontWeight.w600 : null))),
            ]),
            if (note case final note?) Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: colors.outline)),
          ]),
        ),
      ),
    );
  }
}
