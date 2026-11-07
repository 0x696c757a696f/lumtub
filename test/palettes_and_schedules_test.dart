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
    // A white page warms as a white picture does, not only grey ones.
    final page = warmColor(const Color(0xFFFFFFFF), 1);
    expect(page.r, closeTo(1, 0.01));
    expect(page.b, lessThan(0.8));
    expect(warmColor(const Color(0xFF000000), 1), const Color(0xFF000000));
    // A pale blue page goes warm, not olive.
    final blue = warmColor(const Color(0xFFE6EFF4), 1);
    expect(blue.r, greaterThan(blue.g));
    expect(blue.g, greaterThan(blue.b));
  });

  test('the warm light is set as a colour temperature and comes on over an hour', () {
    expect(AppearanceSettings.kelvinOf(AppearanceSettings.warmthOf(3400)), 3400);
    expect(AppearanceSettings.kelvinOf(1), 1900);
    // A candle takes all the blue out of white; 6000 K hardly any.
    expect(WarmLayer.tint(AppearanceSettings.warmthOf(1900)).b, lessThan(0.05));
    expect(WarmLayer.tint(AppearanceSettings.warmthOf(6000)).b, greaterThan(0.9));
    const hours = AppearanceSettings(eyeCare: EyeCare.hours, eyeCareStart: 20, eyeCareEnd: 7, warmth: 0.6);
    double at(int hour, int minute) => hours.warmthAt(DateTime(2026, 11, 7, hour, minute));
    expect(at(12, 0), 0);
    expect(at(19, 25), 0);
    expect(at(20, 0), closeTo(0.3, 0.001), reason: 'halfway at the hour set');
    expect(at(20, 35), 0.6);
    expect(at(7, 0), closeTo(0.3, 0.001));
    // In twelve steps, each lasting five minutes.
    expect(at(19, 47), at(19, 49));
    expect({for (var m = 0; m < 60; m++) at(19 + (30 + m) ~/ 60, (30 + m) % 60)}, hasLength(12));
    expect(const AppearanceSettings(eyeCare: EyeCare.always, warmth: 0.6).warmthAt(DateTime(2026, 11, 7, 12)), 0.6);
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
