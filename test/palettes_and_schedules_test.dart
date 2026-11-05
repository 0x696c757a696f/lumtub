import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/appearance_settings.dart';
import 'package:lumtub/sun_times.dart';
import 'package:lumtub/sun_zones.dart';
import 'package:lumtub/ui/palettes.dart';
import 'package:lumtub/ui/theme.dart';
import 'package:lumtub/ui/warm_layer.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  test('every palette reads well in light and dark', () {
    expect(palettes.length, 10);
    expect(palettes.map((p) => p.id).toSet().length, 10);
    for (final palette in palettes) {
      for (final brightness in Brightness.values) {
        final scheme = buildAppTheme(Colors.red, brightness, palette: palette).colorScheme;
        final what = '${palette.id} ${brightness.name}';
        expect(_contrast(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(12), reason: what);
        expect(_contrast(scheme.onSurfaceVariant, scheme.surface), greaterThanOrEqualTo(4.5), reason: what);
        expect(_contrast(scheme.primary, scheme.surface), greaterThanOrEqualTo(4.5), reason: what);
        expect(_contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5), reason: what);
        expect(scheme.primary, palette.of(brightness).accent, reason: what);
      }
    }
    expect(buildAppTheme(Colors.red, Brightness.dark, palette: paletteOf('ricePaper'), pureBlack: true).colorScheme.surface, Colors.black);
  });

  test('appearance keeps palette, schedules, warmth and layout', () {
    const a = AppearanceSettings(palette: 'rime', eyeCare: EyeCare.hours, warmth: 0.6, eyeCareStart: 21, eyeCareEnd: 6, darkSchedule: DarkSchedule.sun, lowResource: true, layout: VideoLayout.text);
    final b = AppearanceSettings.fromJson(a.toJson());
    expect((b.palette, b.eyeCare, b.warmth, b.eyeCareStart, b.eyeCareEnd, b.darkSchedule, b.lowResource, b.layout), ('rime', EyeCare.hours, 0.6, 21, 6, DarkSchedule.sun, true, VideoLayout.text));
    expect(b.effectiveThumbnails, ThumbnailQuality.medium);
    expect(b.effectiveMotion, MotionPreference.reduced);
    expect(const AppearanceSettings().palette, '');
  });

  test('hours run through midnight', () {
    const a = AppearanceSettings(eyeCare: EyeCare.hours, eyeCareStart: 21, eyeCareEnd: 6, darkSchedule: DarkSchedule.hours, darkStart: 8, darkEnd: 18);
    expect(a.warmAt(DateTime(2026, 1, 1, 23)), isTrue);
    expect(a.warmAt(DateTime(2026, 1, 1, 5)), isTrue);
    expect(a.warmAt(DateTime(2026, 1, 1, 12)), isFalse);
    expect(a.themeModeAt(DateTime(2026, 1, 1, 9)), ThemeMode.dark);
    expect(a.themeModeAt(DateTime(2026, 1, 1, 20)), ThemeMode.light);
    expect(const AppearanceSettings(themeMode: ThemeMode.dark).themeModeAt(DateTime(2026, 1, 1, 12)), ThemeMode.dark);
  });

  test('sunrise and sunset come out where they should', () {
    // Shanghai, 21 June 2026: sunrise about 04:50 and sunset about 19:01 (UTC+8).
    final shanghai = SunTimes.at(31.2, 121.5);
    final (rise, set) = shanghai.on(DateTime(2026, 6, 21))!;
    final riseUtc = rise.toUtc(), setUtc = set.toUtc();
    expect((riseUtc.hour * 60 + riseUtc.minute - (20 * 60 + 50)).abs(), lessThan(8), reason: '$riseUtc');
    expect((setUtc.hour * 60 + setUtc.minute - (11 * 60 + 1)).abs(), lessThan(8), reason: '$setUtc');
    // Tromsø has no sunrise in late December and no sunset in late June.
    final tromso = SunTimes.at(69.6, 18.9);
    expect(tromso.on(DateTime(2026, 12, 21)), isNull);
    expect(tromso.polarNight(DateTime(2026, 12, 21)), isTrue);
    expect(tromso.isNight(DateTime(2026, 6, 21, 12)), isFalse);
    expect(windowsZones['China Standard Time'], 'Asia/Shanghai');
    expect(zoneCoordinates['Europe/Rome'], isNotNull);
  });

  test('warm light keeps black and red, takes blue down most', () {
    final tint = WarmLayer.tint(1);
    expect(tint.r, 1);
    expect(tint.g, greaterThan(tint.b));
    expect(WarmLayer.tint(0), const Color(0xFFFFFFFF));
  });

  test('the warm light keeps every palette readable and its own', () {
    for (final palette in [null, ...palettes]) {
      for (final brightness in Brightness.values) {
        final theme = buildAppTheme(Colors.red, brightness, palette: palette, warmth: 1);
        final plain = buildAppTheme(Colors.red, brightness, palette: palette).colorScheme;
        final scheme = theme.colorScheme;
        final what = '${palette?.id} ${brightness.name}';
        expect(_contrast(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(10), reason: what);
        expect(_contrast(scheme.onSurfaceVariant, scheme.surface), greaterThanOrEqualTo(4.0), reason: what);
        if (palette != null) expect(_contrast(scheme.primary, scheme.surface), greaterThanOrEqualTo(4.0), reason: what);
        // The accent moves a quarter as far as the page.
        expect(scheme.primary, warmColor(plain.primary, 0.25), reason: what);
        expect(theme.extension<AppTones>()!.warmth, 1);
        final chrome = palette?.of(brightness).chrome;
        if (chrome != null) expect(theme.extension<AppTones>()!.chrome, warmColor(chrome, 1), reason: what);
      }
    }
  });
}
