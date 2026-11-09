import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/skins/jsonc.dart';
import 'package:lumtub/skins/skin.dart';
import 'package:lumtub/ui/theme.dart';

/// The colours the app's widgets put on top of each other, for every
/// built-in skin on both sides: what is chosen in segmented buttons, lists
/// and the rail must read on what it sits on, not only the pairs a skin
/// file names.
void main() {
  final dirs = Directory('skins').listSync().whereType<Directory>().where((d) => File('${d.path}/skin.jsonc').existsSync() && !d.path.endsWith('template'));
  Color solid(Color c, Color under) => Color.alphaBlend(c, under);

  for (final dir in dirs) {
    test('${dir.path} keeps chosen things readable', () {
      final skin = Skin.parse(decodeJsonc(File('${dir.path}/skin.jsonc').readAsStringSync()), folder: dir.path, builtIn: true);
      for (final mode in Brightness.values) {
        final side = skin.forBrightness(mode);
        final theme = buildAppTheme(const Color(0xFF3366FF), side.brightness, skin: side);
        final scheme = theme.colorScheme;
        final page = side.colors.page;
        final selected = {WidgetState.selected};
        final segmentBg = solid(theme.segmentedButtonTheme.style!.backgroundColor!.resolve(selected)!, page);
        final segmentFg = theme.segmentedButtonTheme.style!.foregroundColor!.resolve(selected)!;
        final pairs = <String, (Color, Color, double)>{
          'segmented button, chosen': (segmentFg, segmentBg, 4.5),
          'list tile, chosen': (theme.listTileTheme.selectedColor!, solid(theme.listTileTheme.selectedTileColor!, page), 4.5),
          'rail icon, chosen': (theme.navigationRailTheme.selectedIconTheme!.color!, solid(theme.navigationRailTheme.indicatorColor!, page), 3),
          'secondary container': (scheme.onSecondaryContainer, solid(scheme.secondaryContainer, page), 4.5),
          'text on page': (scheme.onSurface, solid(scheme.surface, page), 4.5),
        };
        for (final MapEntry(key: what, value: (fg, bg, min)) in pairs.entries) {
          expect(contrastRatio(solid(fg, bg), bg), greaterThanOrEqualTo(min - 0.05), reason: '$what in ${mode.name}');
        }
      }
    });
  }
}
