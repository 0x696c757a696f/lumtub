import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/appearance_settings.dart';
import 'package:lumtub/skins/jsonc.dart';
import 'package:lumtub/skins/skin.dart';
import 'package:lumtub/ui/glass_look.dart';
import 'package:lumtub/ui/skin_chrome.dart';
import 'package:lumtub/ui/skin_paint.dart';
import 'package:lumtub/ui/theme.dart';

/// 窗口透明 (docs/specs/window-glass.md): every word on the glass reads
/// over anything behind the window, under every skin, light and dark.
void main() {
  final dirs = Directory('skins').listSync().whereType<Directory>().where((d) => File('${d.path}/skin.jsonc').existsSync() && !d.path.endsWith('template')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final themes = <String, ThemeData>{
    for (final b in Brightness.values) 'standard ${b.name}': buildAppTheme(const Color(0xFF3366FF), b),
    for (final dir in dirs)
      for (final b in Brightness.values)
        '${dir.path} ${b.name}': () {
          final skin = Skin.parse(decodeJsonc(File('${dir.path}/skin.jsonc').readAsStringSync()), folder: dir.path, builtIn: true).forBrightness(b);
          return buildAppTheme(const Color(0xFF3366FF), skin.brightness, skin: skin);
        }(),
  };

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    test('$name: words on the glass read over any desktop at every transparency', () {
      for (final whole in [false, true]) {
        for (final transparency in [0.0, 0.5, 1.0]) {
          final glazed = withGlass(theme, transparency: transparency, whole: whole);
          final look = glazed.extension<GlassLook>()!;
          expect(look.alpha, greaterThanOrEqualTo(glassClearest));
          // The words are measured as the theme without glass gives them.
          for (final w in glassWritings(theme, whole: whole)) {
            for (final desk in desktopColors) {
              for (final bg in glassBehind(w, look.tint, desk, look.alpha)) {
                expect(contrastRatio(Color.alphaBlend(w.text, bg), bg), greaterThanOrEqualTo(w.min - 0.005),
                    reason: '${w.what}, ${whole ? 'whole window' : 'frame'}, transparency $transparency, over ${desk.toARGB32().toRadixString(16)}');
              }
            }
          }
        }
      }
    });

    test('$name: the frame really lets the desktop through', () {
      // Words glow on the frame, so it may go clear whatever the colours.
      expect(glassFloor(theme, whole: false), lessThanOrEqualTo(0.55), reason: 'frame glass as clear as it goes');
      final glazed = withGlass(theme, transparency: 0.7, whole: false);
      expect(glazed.scaffoldBackgroundColor.a, 1, reason: 'pages solid in the frame-only look');
      expect(withGlass(theme, transparency: 0.7, whole: true).scaffoldBackgroundColor.a, 0, reason: 'pages clear in the whole-window look');
    });
  }

  testWidgets('a plate covers round the letters it glows behind, and fades', (tester) async {
    const tint = Color(0xFF204020);
    const size = Size(120, 40);
    Widget words(bool glass) => MaterialApp(
          theme: ThemeData(extensions: [if (glass) const GlassLook(alpha: 0.4, whole: false, tint: tint)]),
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: glass ? const ValueKey('glass') : const ValueKey('bare'),
              child: SizedBox.fromSize(
                size: size,
                child: const Material(type: MaterialType.transparency, child: Center(child: GlassPlate(child: Text('文件 Hg', style: TextStyle(fontSize: 16, color: Colors.white))))),
              ),
            ),
          ),
        );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<ByteData> render(bool glass) async {
      await tester.pumpWidget(words(glass));
      await tester.pumpAndSettle();
      final boundary = tester.renderObject(find.byKey(ValueKey(glass ? 'glass' : 'bare')));
      return (await tester.runAsync(() async {
        final picture = await (boundary as RenderRepaintBoundary).toImage();
        return (await picture.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
      }))!;
    }
    final bare = await render(false);
    final glass = await render(true);
    final w = size.width.toInt(), h = size.height.toInt();
    bool ink(int x, int y) => x >= 0 && y >= 0 && x < w && y < h && bare.getUint8((y * w + x) * 4 + 3) > 128;
    double alpha(int x, int y) => glass.getUint8((y * w + x) * 4 + 3) / 255;
    var near = 0, far = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (ink(x, y)) continue;
        var distance = 99;
        for (var dy = -10; dy <= 10; dy++) {
          for (var dx = -10; dx <= 10; dx++) {
            if (ink(x + dx, y + dy)) distance = math.min(distance, math.max(dx.abs(), dy.abs()));
          }
        }
        if (distance <= 2) {
          near++;
          expect(alpha(x, y), greaterThanOrEqualTo(distance == 1 ? GlassPlate.coverage - 0.01 : 0.93), reason: 'halo at $x,$y');
        } else if (distance > 9) {
          far++;
          expect(alpha(x, y), lessThan(0.05), reason: 'glass at $x,$y');
        }
      }
    }
    expect(near, greaterThan(100));
    expect(far, greaterThan(100), reason: 'the halo hugs the words, not a box round them');
  });

  testWidgets('no glass, no plate', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GlassPlate(child: SizedBox(width: 10, height: 10))));
    expect(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Halo'), findsNothing);
  });

  test('the frame turns to glass, the cards do not', () {
    final skin = Skin.parse(decodeJsonc(File('skins/aero/skin.jsonc').readAsStringSync()), folder: 'skins/aero', builtIn: true);
    expect(skin.frameSurfaces, isNotEmpty);
    expect(skin.frameSurfaces.every((s) => s.frame), isTrue);
    expect(skin.videoCard?.frame ?? false, isFalse);
    expect(skin.topBar!.forState(hovered: true).frame, isTrue, reason: 'hovered bars stay glass');
  });

  testWidgets('the title glows behind its words only, not across the bar', (tester) async {
    final skin = Skin.parse(decodeJsonc(File('skins/aero/skin.jsonc').readAsStringSync()), folder: 'skins/aero', builtIn: true);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [GlassLook(alpha: 0.4, whole: false, tint: Colors.white)]),
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(key: key, child: SizedBox(width: 800, child: SkinTitleBarView(bar: skin.titleBar!, title: 'Lumtub'))),
      ),
    ));
    final height = skin.titleBar!.height.round();
    final image = await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await boundary.toImage();
      return (await picture.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
    });
    // Halfway along, between the title and the buttons: glass.
    final alpha = image!.getUint8(((height ~/ 3) * 800 + 450) * 4 + 3) / 255;
    expect(alpha, lessThan(0.6));
  });

  testWidgets('bars are drawn at the glass alpha, not the skin glass slider', (tester) async {
    final skin = Skin.parse(decodeJsonc(File('skins/aero/skin.jsonc').readAsStringSync()), folder: 'skins/aero', builtIn: true);
    late SurfaceDecoration bar, card;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [GlassLook(alpha: 0.42, whole: false, tint: Colors.white)]),
      home: Builder(builder: (context) {
        bar = SurfaceDecoration.of(context, skin.topBar!);
        card = SurfaceDecoration.of(context, skin.videoCard!);
        return const SizedBox();
      }),
    ));
    expect(bar.clarity, 0.42);
    expect(card.clarity, skin.videoCard!.glass ? SkinGlass.opacity : 1);
  });

  test('settings keep the window glass apart from a skin glass', () {
    const off = AppearanceSettings();
    expect(off.windowGlass, isFalse);
    final on = off.copyWith(windowGlass: true, windowGlassClarity: 0.4, windowGlassWhole: true, windowGlassBlur: false, glassOpacity: 0.5);
    final back = AppearanceSettings.fromJson(on.toJson());
    expect(back.windowGlass, isTrue);
    expect(back.windowGlassClarity, 0.4);
    expect(back.windowGlassWhole, isTrue);
    expect(back.windowGlassBlur, isFalse);
    expect(back.glassOpacity, 0.5);
    // A setting saved by 0.2.30's see-through window is not taken for it.
    expect(AppearanceSettings.fromJson({'seeThrough': true}).windowGlass, isFalse);
  });
}
