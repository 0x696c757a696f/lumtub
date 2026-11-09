import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/skins/jsonc.dart';
import 'package:lumtub/skins/skin.dart';

/// Checks a skin before it is shared:
///   SKIN=path/to/skin flutter test test/skin_check_test.dart
void main() {
  final path = Platform.environment['SKIN'];
  test('skin at \$SKIN', () {
    if (path == null) {
      markTestSkipped('set SKIN to a skin folder');
      return;
    }
    for (final device in ['desktop', 'mobile', 'tablet', 'tv']) {
      Skin.formFactor = device;
      final skin = Skin.parse(decodeJsonc(File('$path/skin.jsonc').readAsStringSync()), folder: path, builtIn: false);
      skin
        ..buttonText
        ..primaryButtonText
        ..chipSelectedText
        ..navSelectedText
        ..navText
        ..durationText;
      for (final w in skin.warnings) {
        // ignore: avoid_print
        print('$device: $w');
      }
      expect(skin.warnings, isEmpty, reason: 'see the lines above');
    }
  });
}
