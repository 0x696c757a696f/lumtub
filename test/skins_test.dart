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
    expect(parse({'background': ['#008080']}).warnings, contains(contains('on window.background')));
    expect(parse({'background': ['#008080'], 'veil': 0.5}).warnings.where((w) => w.contains('on window.background')), isEmpty);
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

  test('a saved colour scheme becomes its skin', () {
    expect(paletteSkinId('ricePaper'), 'rice-paper');
    expect(SkinLibrary.colorSchemeIds, containsAll([for (final p in palettes) paletteSkinId(p.id)]));
  });
}
