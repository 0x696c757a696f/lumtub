import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/skins/jsonc.dart';
import 'package:lumtub/skins/skin.dart';
import 'package:lumtub/skins/skin_library.dart';

/// Every skin in skins/ reads without a single warning, contrast included,
/// on every kind of device.
void main() {
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
        for (final name in skin.fontFiles.values) {
          expect(File(skin.file(name)).existsSync(), isTrue, reason: name);
        }
        Skin.formFactor = 'desktop';
      });
    }
  }
}
