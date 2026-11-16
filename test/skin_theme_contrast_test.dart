import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/skins/jsonc.dart';
import 'package:lumtub/skins/skin.dart';
import 'package:lumtub/ui/skin_scenes.dart';
import 'package:lumtub/ui/linked_text.dart';
import 'package:lumtub/ui/theme.dart';

/// The colours the app's widgets put on top of each other, for every
/// built-in skin on both sides: what is chosen in segmented buttons, lists
/// and the rail must read on what it sits on, not only the pairs a skin
/// file names.
void main() {
  final dirs = Directory('skins').listSync().whereType<Directory>().where((d) => File('${d.path}/skin.jsonc').existsSync() && !d.path.endsWith('template'));
  Color solid(Color c, Color under) => Color.alphaBlend(c, under);
  // A picture behind: its colours averaged over patches about as big as a
  // line of text.
  Future<List<Color>> picture(String path) async {
    final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync(), targetWidth: 48, targetHeight: 27);
    final image = (await codec.getNextFrame()).image;
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return [for (var i = 0; i < bytes.lengthInBytes; i += 4) Color.fromARGB(255, bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2))];
  }

  for (final dir in dirs) {
    test('${dir.path} keeps chosen things readable', () async {
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
          // Up next, cards and comments draw channel names and views in these.
          'quiet text on page': (scheme.outline, page, 4.5),
          'muted text on page': (scheme.onSurfaceVariant, page, 4.5),
          'quiet text on cards': (scheme.outline, solid(scheme.surfaceContainerLow, page), 4.5),
          // Links and times in descriptions and comments are words to read.
          'links on page': (linkColor(theme), page, 4.5),
          'links on cards': (linkColor(theme), solid(scheme.surfaceContainerLow, page), 4.5),
          // Filter chips: Explore's and search's menus, off and on.
          'chip label': (theme.chipTheme.labelStyle!.color!, solid(theme.chipTheme.backgroundColor!, page), 4.5),
          'chip label, chosen': ((theme.chipTheme.labelStyle!.color! as WidgetStateColor).resolve(selected), solid(theme.chipTheme.selectedColor!, page), 4.5),
        };
        // Every control's words on the control as drawn over the page,
        // every stop of a gradient and a see-through fill included.
        final controls = <String, (Color?, SkinSurface?)>{
          'button': (side.buttonText, side.button),
          'main button': (side.primaryButtonText, side.primaryButton),
          'chip': (side.chipText, side.chip),
          'chosen chip': (side.chipSelectedText, side.chipSelected),
          'chosen rail item': (side.navSelectedText, side.navSelected),
          'rail item': (side.navText, side.sideBar),
          'duration badge': (side.durationText, side.durationBadge),
        };
        for (final MapEntry(key: what, value: (fg, surface)) in controls.entries) {
          if (fg == null || surface == null || surface.baseColor == null) continue;
          for (final bg in surface.tones(page)) {
            expect(contrastRatio(solid(fg, bg), bg), greaterThanOrEqualTo(4.45), reason: '$what text in ${mode.name}: $fg on $bg');
          }
        }
        for (final MapEntry(key: what, value: (fg, bg, min)) in pairs.entries) {
          expect(contrastRatio(solid(fg, bg), bg), greaterThanOrEqualTo(min - 0.05), reason: '$what in ${mode.name}');
        }
        // Pages opened over the window (settings and the like) are veiled
        // like the main page, not drawn straight on the picture.
        if (side.veil > 0) expect(theme.scaffoldBackgroundColor, page.withValues(alpha: side.veil), reason: 'pushed pages veiled in ${mode.name}');
        // Glass made as clear as it goes still keeps what is on it readable.
        if (side.glass) {
          // Every colour of the backdrop the glass can lie over.
          final behind = <Color>[page];
          for (final paint in side.background) {
            if (paint is ImagePaint) {
              behind.addAll(await picture(paint.path));
              continue;
            }
            final colors = switch (paint) {
              SolidPaint(:final color) => [color],
              LinearPaint(:final colors) => colors,
              RadialPaint(:final colors) => colors,
              _ => const <Color>[],
            };
            for (final c in colors) {
              behind.add(Color.alphaBlend(c, behind.first));
            }
          }
          // A painted landscape behind: every colour it is made of.
          for (final d in side.decorations.whereType<SceneDecoration>()) {
            behind.addAll(sceneTones(SkinScene.byName(d.scene)!, night: d.night));
          }
          // Text on the pages lies over the landscape through the veil.
          if (side.veil > 0) {
            for (final under in behind) {
              final bg = Color.alphaBlend(page.withValues(alpha: side.veil), under);
              expect(contrastRatio(side.colors.text, bg), greaterThanOrEqualTo(4.45), reason: 'page text through the veil in ${mode.name}: on $bg');
              expect(contrastRatio(linkColor(theme), bg), greaterThanOrEqualTo(4.45), reason: 'links through the veil in ${mode.name}: on $bg');
              if (side.colors.muted case final muted?) {
                expect(contrastRatio(muted, bg), greaterThanOrEqualTo(4.45), reason: 'muted text through the veil in ${mode.name}: on $bg');
              }
            }
          }
          List<Color> clear(SkinSurface? s) => [
                for (final under in behind) ...[
                  // With no pane of its own the text lies on the picture.
                  if (s == null || s.tones(const Color(0x00000000)).isEmpty) under,
                  for (final c in s?.tones(const Color(0x00000000)) ?? <Color>[]) Color.alphaBlend(c.withValues(alpha: c.a * side.glassMin), under),
                ],
              ];
          final glassPairs = <String, (Color?, SkinSurface?, double)>{
            'top bar icons': (side.topBarText, side.topBar, 3),
            'rail labels': (side.navText, side.sideBar, 4.5),
            'status line': (side.statusBarText, side.statusBar, 4.5),
            'title': (side.titleBar?.text, side.titleBar?.surface, 4.5),
            'menus': (side.menuBar?.text, side.menuBar?.surface, 4.5),
            'tabs': (side.tabs?.text, side.tabs?.bar, 4.5),
            'card text': (side.colors.text, side.videoCard, 4.5),
          };
          for (final MapEntry(key: what, value: (fg, surface, min)) in glassPairs.entries) {
            if (fg == null) continue;
            for (final bg in clear(surface)) {
              expect(contrastRatio(solid(fg, bg), bg), greaterThanOrEqualTo(min - 0.05), reason: '$what on clear glass in ${mode.name}: $fg on $bg');
            }
          }
        }
      }
    });
  }
}
