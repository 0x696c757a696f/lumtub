import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/l10n/l10n.dart';
import 'package:lumtub/skins/skin.dart';
import 'package:lumtub/ui/skin_deck.dart';
import 'package:lumtub/ui/skin_lcd.dart';
import 'package:lumtub/ui/skin_paint.dart';
import 'package:lumtub/ui/skin_scenes.dart';
import 'package:lumtub/ui/theme.dart';
import 'package:lumtub/ui/window_chrome.dart';
import 'player_controls_test.dart' show FakePlayer;

Skin _skin(Map<String, Object?> extra) => Skin.parse({
      'lumtubSkin': 1,
      'id': 't',
      'name': 'T',
      'colors': {'page': '#ffffff', 'text': '#000000'},
      ...extra,
    }, folder: 'skins/aero', builtIn: true);

void main() {
  setUpAll(loadTranslations);

  testWidgets("a controller change does not paint the skin's ornaments again", (tester) async {
    final skin = _skin({
      'window': {
        'decorations': [
          {'type': 'bubbles'},
          {'type': 'pattern', 'pattern': 'scanlines', 'above': true},
        ],
      },
    });
    final controller = AppController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Colors.red, Brightness.light, skin: skin),
      builder: (context, child) => WindowChrome(controller: controller, title: 'Lumtub', child: child!),
      home: const SizedBox.expand(),
    ));
    await tester.pump();
    expect(find.byType(SkinBackdrop), findsOneWidget);
    final before = SkinDecorationPainter.paints;
    expect(before, greaterThan(0));
    for (var i = 0; i < 5; i++) {
      controller.setIncognito(i.isEven);
      await tester.pump();
    }
    expect(SkinDecorationPainter.paints, before);
  });

  test('resizing the window records a scene only once a step', () {
    final painter = ScenePainter(SkinScene.meadow, night: false, seed: 42);
    void paintAt(Size size) {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      recorder.endRecording().dispose();
    }

    final before = ScenePainter.recordings;
    for (var w = 961.0; w <= 1020; w += 3) {
      paintAt(Size(w, 650 + (w - 961) / 4));
    }
    expect(ScenePainter.recordings - before, 1);
    paintAt(const Size(1400, 900));
    expect(ScenePainter.recordings - before, 2);
    paintAt(const Size(1000, 650));
    expect(ScenePainter.recordings - before, 2, reason: 'the size resized back from is kept');
  });

  testWidgets("the LCD's meter asks for about 20 frames a second, not one per refresh", (tester) async {
    final player = FakePlayer();
    player.state = player.state.copyWith(playing: true);
    final skin = _skin({
      'player': {'style': 'lcd'},
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SkinLcd(skin: skin, player: player, title: 'A title long enough to run past the display ' * 3, subtitle: 'Channel', still: false)),
    ));
    var frames = 0;
    await tester.pump();
    for (var t = 0; t < 1000; t += 4) {
      await tester.binding.delayed(const Duration(milliseconds: 4));
      if (tester.binding.hasScheduledFrame) {
        frames++;
        await tester.pump();
      }
    }
    expect(frames, greaterThanOrEqualTo(10), reason: 'the meter moves');
    expect(frames, lessThanOrEqualTo(25));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("the deck's groove moving does not paint the deck's body again", (tester) async {
    final player = FakePlayer();
    final skin = _skin({
      'player': {'style': 'deck', 'deck': {'speakers': true}},
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SkinDeckView(deck: skin.player.deck!, player: player, title: 'Title', onSeek: player.seek)),
    ));
    await tester.pump();
    final before = SkinDeckView.bodyPaints;
    expect(before, greaterThan(0));
    for (var s = 2; s < 8; s++) {
      await player.seek(Duration(minutes: 1, seconds: s));
      await tester.pump();
    }
    expect(SkinDeckView.bodyPaints, before);
  });
}
