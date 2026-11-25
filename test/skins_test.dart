import 'dart:io';
import 'dart:ui' show Brightness, Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/appearance_settings.dart' show paletteSkinId;
import 'package:lumtub/skins/jsonc.dart';
import 'package:lumtub/ui/palettes.dart' show palettes;
import 'package:lumtub/skins/skin.dart';
import 'package:lumtub/skins/skin_library.dart';

/// Every skin in skins/ reads without a single warning, contrast included,
/// on every kind of device.
void main() {
  test('a picture keeps its focus in view, and a plain background is checked under the veil', () {
    Skin parse(Map<String, Object?> window) => Skin.parse({'lumtubSkin': 1, 'id': 't', 'name': 'T', 'colors': {'page': '#ffffff', 'text': '#000000'}, 'window': window}, folder: 'skins/aero', builtIn: true);
    final picture = parse({'background': [{'image': 'day.jpg', 'focus': [0.5, 0.3]}]}).background.single as ImagePaint;
    expect(picture.focus.x, 0);
    expect(picture.focus.y, closeTo(-0.4, 1e-9));
    expect(parse({'background': [{'image': 'day.jpg', 'focus': [2, 0]}]}).warnings, contains(contains('focus')));
    // Text that cannot be read on a plain backdrop gets a veil of the page
    // colour, as much as it takes.
    final teal = parse({'background': ['#008080']});
    expect(teal.veil, greaterThan(0));
    expect(teal.warnings.where((w) => w.contains('on window.background')), isEmpty);
    expect(parse({'background': ['#ffffff']}).veil, 0);
    expect(parse({'background': ['#008080'], 'veil': 0.5}).warnings.where((w) => w.contains('on window.background')), isEmpty);
  });

  test('a skin with many layers, colours or tiny spacings stays cheap to read and draw', () {
    Skin parse(Map<String, Object?> window) => Skin.parse({'lumtubSkin': 1, 'id': 't', 'name': 'T', 'colors': {'page': '#ffffff', 'text': '#000000'}, 'window': window}, folder: 'skins/aero', builtIn: true);
    final colours = [for (var i = 0; i < 40; i++) '#${(i * 6).toRadixString(16).padLeft(2, '0')}8080'];
    final watch = Stopwatch()..start();
    final heavy = parse({'background': [for (var i = 0; i < 20; i++) {'linear': {'colors': colours}}]});
    expect(heavy.veil, inInclusiveRange(0, 0.9));
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(heavy.background, hasLength(SkinPaint.maxLayers));
    expect((heavy.background.first as LinearPaint).colors, hasLength(16));
    final dots = parse({
      'background': [{'pattern': {'type': 'dots', 'color': '#000000', 'spacing': 0.001, 'size': 50}}],
      'decorations': [{'type': 'perspectiveGrid', 'spacing': 0}],
    });
    final pattern = dots.background.single as PatternPaint;
    expect(pattern.spacing, 3);
    expect(pattern.size, 3);
    expect((dots.decorations.single as PerspectiveGridDecoration).spacing, 8);
  });

  test('jsonc allows comments and trailing commas', () {
    expect(decodeJsonc('{\n // a\n "a": "x//y", /* b */ "b": [1, 2,],\n}'), {'a': 'x//y', 'b': [1, 2]});
    expect(() => decodeJsonc('{\n"a": 1\n"b": 2}'), throwsA(isA<FormatException>().having((e) => e.message, 'message', startsWith('line 3'))));
  });

  test('colours are read as in CSS', () {
    expect(parseColor('#fff'), const Color(0xFFFFFFFF));
    expect(parseColor('#00000080'), const Color(0x80000000));
    expect(parseColor('#12345678'), const Color(0x78123456));
    expect(parseColor('red'), isNull);
  });

  final dirs = Directory('skins').listSync().whereType<Directory>().where((d) => File('${d.path}/skin.jsonc').existsSync()).toList();
  test('every built-in skin is listed', () {
    final ids = {for (final d in dirs) d.uri.pathSegments.where((s) => s.isNotEmpty).last};
    expect(ids.difference({'template'}), SkinLibrary.builtInIds.toSet());
  });

  for (final dir in dirs) {
    for (final device in ['desktop', 'mobile', 'tablet', 'tv']) {
      test('${dir.path} on $device', () {
        Skin.formFactor = device;
        final skin = Skin.parse(decodeJsonc(File('${dir.path}/skin.jsonc').readAsStringSync()), folder: dir.path, builtIn: true);
        // Reading every part records every warning.
        skin
          ..buttonText
          ..primaryButtonText
          ..chipSelectedText
          ..navSelectedText
          ..navText
          ..durationText;
        expect(skin.warnings, isEmpty);
        // A skin that follows the theme mode has a dark side, checked too.
        expect(skin.forBrightness(Brightness.dark).brightness, skin.followsThemeMode ? Brightness.dark : skin.brightness);
        for (final name in skin.fontFiles.values) {
          expect(File(skin.file(name)!).existsSync(), isTrue, reason: name);
        }
        Skin.formFactor = 'desktop';
      });
    }
  }

  test('an auto skin follows the theme mode with its dark overrides', () {
    final skin = Skin.parse({
      'lumtubSkin': 1,
      'id': 'x',
      'name': 'X',
      'brightness': 'auto',
      'colors': {'page': '#ffffff', 'text': '#000000', 'accent': '#0047cc'},
      'overrides': {
        'dark': {'colors': {'page': '#000000', 'text': '#ffffff', 'accent': '#ffd60a'}},
      },
    }, folder: '', builtIn: false);
    expect(skin.followsThemeMode, isTrue);
    expect(skin.brightness, Brightness.light);
    final dark = skin.forBrightness(Brightness.dark);
    expect(dark.brightness, Brightness.dark);
    expect(dark.colors.page, const Color(0xFF000000));
    expect(dark.forBrightness(Brightness.light), same(skin));
  });

  test('phone tabs go along the bottom or under the top bar', () {
    Skin read(Map<String, Object?> tabs) => Skin.parse({
          'lumtubSkin': 1,
          'id': 'x',
          'name': 'X',
          'colors': {'page': '#ffffff', 'text': '#000000', 'accent': '#0047cc'},
          'window': {'tabs': tabs},
        }, folder: '', builtIn: false);
    final bottom = read({'surface': '#111111', 'text': '#222222'});
    expect(bottom.tabs!.top, isFalse);
    // Dark grey on near black is hard to read, so it is replaced.
    expect(bottom.warnings, isNotEmpty);
    final top = read({'position': 'top', 'labels': 'text', 'caps': true, 'indicator': '#33b5e5'});
    expect(top.tabs!.top, isTrue);
    expect(top.tabs!.textOnly, isTrue);
    expect(top.tabs!.caps, isTrue);
    expect(top.warnings, isEmpty);
    expect(read({'enabled': false}).tabs, isNull);
  });

  test('a light hover fill reaching the dark side is listed', () {
    Skin read(Map<String, Object?> darkHover) => Skin.parse({
          'lumtubSkin': 1,
          'id': 't',
          'name': 'T',
          'brightness': 'auto',
          'colors': {'page': '#eef1f1', 'text': '#1f3236'},
          'cards': {'video': {'fill': '#ffffff80', 'hover': {'fill': '#ffffffcc'}}},
          'overrides': {'dark': {'colors': {'page': '#1c2326', 'text': '#e6eeee'}, 'cards': {'video': {'fill': '#232c30b3', 'hover': darkHover}}}},
        }, folder: 'skins/t', builtIn: true);
    expect(read({'border': '#8fd0cf'}).warnings, contains(startsWith('dark: cards.video.hover')));
    expect(read({'fill': '#283b3ecc'}).warnings.where((w) => w.contains('cards.video')), isEmpty);
  });

  test('a saved colour scheme becomes its skin', () {
    expect(paletteSkinId('ricePaper'), 'rice-paper');
    expect(SkinLibrary.colorSchemeIds, containsAll([for (final p in palettes) paletteSkinId(p.id)]));
  });
}
