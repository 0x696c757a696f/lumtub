import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/libass_layout.dart';
import 'package:lumtub/line_pause.dart';
import 'package:lumtub/player_settings.dart';
import 'package:lumtub/shortcut_bindings.dart';
import 'package:lumtub/subtitle_cues.dart';
import 'package:media_kit_video/media_kit_video.dart' show SecondaryRevealArea, SubtitleViewConfiguration;

Duration ms(int value) => Duration(milliseconds: value);

SubtitleCue cue(int start, int end, String text) => (start: ms(start), end: ms(end), text: text);

void main() {
  final lines = [cue(1000, 3000, 'one'), cue(3000, 5000, 'two'), cue(6000, 8000, 'three')];

  group('LinePause', () {
    List<int> pausesWhilePlaying(List<SubtitleCue> lines, Iterable<int> positions, {double rate = 1}) {
      final pause = LinePause();
      return [for (final p in positions) if (pause.observe(lines, ms(p), rate: rate)) p];
    }

    test('pauses once at the end of each line, a moment early', () {
      // Frames every 40 ms from 0 to 9 s.
      final paused = pausesWhilePlaying(lines, [for (var p = 0; p <= 9000; p += 40) p]);
      expect(paused, [2880, 4880, 7880]);
    });

    test('a line shorter than the lead pauses at its start', () {
      expect(LinePause.pauseAt(cue(1000, 1050, 'a')), ms(1000));
    });

    test('a seek past the end of a line does not pause', () {
      expect(pausesWhilePlaying(lines, [1000, 1040, 4000, 4040]), isEmpty);
    });

    test('playing on after the pause does not pause again for the same line', () {
      final pause = LinePause();
      expect(pause.observe(lines, ms(2800)), isFalse);
      expect(pause.observe(lines, ms(2900)), isTrue);
      expect(pause.observe(lines, ms(2950)), isFalse);
      expect(pause.observe(lines, ms(3100)), isFalse);
    });

    test('replaying a line pauses at its end again', () {
      final pause = LinePause();
      pause.observe(lines, ms(2800));
      expect(pause.observe(lines, ms(2900)), isTrue);
      pause.reset();
      expect(pause.observe(lines, ms(1000)), isFalse);
      expect(pause.observe(lines, ms(2800)), isFalse);
      expect(pause.observe(lines, ms(2900)), isTrue);
    });

    test('faster playback pauses earlier and allows longer steps', () {
      expect(pausesWhilePlaying(lines, [for (var p = 0; p <= 9000; p += 80) p], rate: 2), [2800, 4800, 7760]);
    });

    test('no lines, no pause', () {
      expect(pausesWhilePlaying(const [], [for (var p = 0; p <= 9000; p += 40) p]), isEmpty);
    });
  });

  group('lineToStep', () {
    test('steps from inside a line', () {
      expect(lineToStep(lines, ms(3500), -1), 0);
      expect(lineToStep(lines, ms(3500), 0), 1);
      expect(lineToStep(lines, ms(3500), 1), 2);
    });

    test('between two lines, this line is the one just heard', () {
      expect(lineToStep(lines, ms(5500), 0), 1);
      expect(lineToStep(lines, ms(5500), 1), 2);
    });

    test('just before a line counts as that line, where replaying starts', () {
      expect(lineToStep(lines, lineStart(lines[2]), 0), 2);
      expect(lineStart(lines[2]), lessThan(lines[2].start));
    });

    test('ends of the list', () {
      expect(lineToStep(lines, ms(0), 0), 0);
      expect(lineToStep(lines, ms(0), -1), 0);
      expect(lineToStep(lines, ms(1500), -1), 0);
      expect(lineToStep(lines, ms(7000), 1), isNull);
      expect(lineToStep(const [], ms(7000), 0), isNull);
    });
  });

  group('TranslationReveal', () {
    test('shows while hovered', () {
      final reveal = TranslationReveal();
      expect(reveal.shown, isFalse);
      expect(reveal.hover(true), isTrue);
      expect(reveal.shown, isTrue);
      expect(reveal.hover(false), isTrue);
      expect(reveal.shown, isFalse);
    });

    test('a tap shows the line until the next one', () {
      final reveal = TranslationReveal();
      expect(reveal.toggle('hello'), isTrue);
      expect(reveal.shown, isTrue);
      // A gap, then the same line from a swapped track.
      expect(reveal.lineChanged(''), isFalse);
      expect(reveal.lineChanged('hello'), isFalse);
      expect(reveal.shown, isTrue);
      expect(reveal.lineChanged('world'), isTrue);
      expect(reveal.shown, isFalse);
    });

    test('a tap while shown hides it', () {
      final reveal = TranslationReveal()..hover(true);
      expect(reveal.toggle('hello'), isTrue);
      expect(reveal.shown, isFalse);
    });

    test('a tap between lines shows the coming line', () {
      final reveal = TranslationReveal()..toggle('');
      expect(reveal.lineChanged('next'), isFalse);
      expect(reveal.shown, isTrue);
      expect(reveal.lineChanged('after'), isTrue);
    });

    test('a new video blurs again', () {
      final reveal = TranslationReveal()..toggle('a');
      expect(reveal.reset(), isTrue);
      expect(reveal.shown, isFalse);
    });

    test("libmpv's copy holds the main lines after a blank line", () {
      expect(secondLines('你好\n世界\n \nhello world'), '你好\n世界');
      expect(secondLines('just this'), 'just this');
      expect(secondLines('\nlead\n\nmain'), 'lead');
      final reveal = TranslationReveal()..toggle('你好\n \nhello');
      expect(reveal.lineChanged('你好\n \nhello there'), isFalse);
      expect(reveal.shown, isTrue);
    });
  });

  group('blurred second subtitle for libmpv', () {
    test('every second line is blurred without its outline; the main lines stay as they were', () {
      const settings = PlayerSettings();
      final cues = [cue(1000, 3000, 'Bonjour'), cue(3000, 5000, 'le monde')];
      final main = (cues: [cue(1000, 5000, 'Hello world')], font: 'sans-serif', room: 40.0, wrapFont: '');
      final plain = secondAss(cues, settings, outline: 0.1, main: main);
      final blurred = secondAss(cues, settings, outline: 0.1, main: main, blurred: true);
      expect(plain, isNot(contains(r'\blur')));
      final events = blurred.split('\n').where((l) => l.startsWith('Dialogue:')).toList();
      expect(events, hasLength(2));
      for (final event in events) {
        expect(event, matches(RegExp(r',,\{\\bord0\\shad0\\blur\d+(\.\d)?\}')));
        expect(event, contains('Hello world'));
      }
      expect(blurred.replaceAll(RegExp(r'\{\\bord0\\shad0\\blur[\d.]+\}'), ''), plain);
    });

    test('without the main subtitle too', () {
      final blurred = secondAss([cue(0, 1000, 'Hola')], const PlayerSettings(), outline: 0.1, blurred: true);
      expect(blurred, contains(r'{\bord0\shad0\blur'));
    });
  });

  group('settings and keys', () {
    test('both switches are saved and default to off', () {
      const off = PlayerSettings();
      expect(off.pauseEachLine, isFalse);
      expect(off.blurSecondary, isFalse);
      final on = off.copyWith(pauseEachLine: true, blurSecondary: true);
      final back = PlayerSettings.fromJson(on.toJson());
      expect(back.pauseEachLine, isTrue);
      expect(back.blurSecondary, isTrue);
    });

    test('Q and V are the keys, and no other player action has them', () {
      final keys = shortcutKeys(const {});
      expect(keys[PlayerAction.linePause], [const KeyCombo(LogicalKeyboardKey.keyQ)]);
      expect(keys[PlayerAction.revealTranslation], [const KeyCombo(LogicalKeyboardKey.keyV)]);
      for (final MapEntry(:key, :value) in keys.entries) {
        if (key.page || key == PlayerAction.linePause || key == PlayerAction.revealTranslation) continue;
        expect(value, isNot(contains(const KeyCombo(LogicalKeyboardKey.keyQ))), reason: key.name);
        expect(value, isNot(contains(const KeyCombo(LogicalKeyboardKey.keyV))), reason: key.name);
      }
      expect(keys[PlayerAction.lineLoop], [const KeyCombo(LogicalKeyboardKey.keyR, shift: true)]);
      final loopKey = const KeyCombo(LogicalKeyboardKey.keyR, shift: true);
      expect([for (final MapEntry(:key, :value) in keys.entries) if (!key.page && value.contains(loopKey)) key], [PlayerAction.lineLoop]);
      expect(PlayerAction.lineLoop.page, isFalse);
      expect(PlayerAction.linePause.page, isFalse);
      expect(PlayerAction.revealTranslation.page, isFalse);
    });
  });

  group('SecondaryRevealArea', () {
    testWidgets('takes taps and hovering over the line, above the controls, and nowhere else', (tester) async {
      var hovering = false, taps = 0, controlTaps = 0;
      const line = Rect.fromLTWH(200, 300, 400, 40);
      await tester.pumpWidget(MaterialApp(
        home: Stack(children: [
          // The player's controls, which take every tap.
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => controlTaps++)),
          Positioned.fill(
            child: SecondaryRevealArea(
              rect: () => line,
              configuration: SubtitleViewConfiguration(blurSecondary: true, onSecondaryHover: (over) => hovering = over, onSecondaryTap: () => taps++),
            ),
          ),
        ]),
      ));
      await tester.tapAt(line.center);
      expect(taps, 1);
      expect(controlTaps, 0);
      await tester.tapAt(const Offset(50, 50));
      expect(taps, 1);
      expect(controlTaps, 1);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(50, 50));
      await tester.pump();
      expect(hovering, isFalse);
      await mouse.moveTo(line.topLeft + const Offset(10, 10));
      await tester.pump();
      expect(hovering, isTrue);
      await mouse.moveTo(const Offset(50, 50));
      await tester.pump();
      expect(hovering, isFalse);
      await mouse.removePointer();
    });

    testWidgets('with no line shown, everything goes to the controls', (tester) async {
      var taps = 0, controlTaps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Stack(children: [
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => controlTaps++)),
          Positioned.fill(child: SecondaryRevealArea(rect: () => null, configuration: SubtitleViewConfiguration(blurSecondary: true, onSecondaryTap: () => taps++))),
        ]),
      ));
      await tester.tapAt(const Offset(400, 300));
      expect(taps, 0);
      expect(controlTaps, 1);
    });
  });
}
