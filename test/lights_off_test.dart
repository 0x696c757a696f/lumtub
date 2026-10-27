import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_preferences.dart';
import 'package:lumtub/ui/lights_off.dart';
import 'package:lumtub/ui/player_shortcuts.dart';

void main() {
  tearDown(() => lightsOff.value = false);

  Future<List<String>> pumpLayer(WidgetTester tester) async {
    final taps = <String>[];
    lightsOff.value = true;
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [
        Positioned.fill(child: GestureDetector(onTap: () => taps.add('page'), child: const ColoredBox(color: Colors.white))),
        Positioned(
          left: 100,
          top: 100,
          width: 320,
          height: 180,
          child: GestureDetector(key: lightsOffHole, onTap: () => taps.add('player'), child: const ColoredBox(color: Colors.black)),
        ),
        Positioned.fill(child: ValueListenableBuilder(
          valueListenable: lightsOff,
          builder: (context, off, _) => off ? const LightsOffLayer(dim: .85) : const SizedBox.shrink(),
        )),
      ]),
    ));
    await tester.pumpAndSettle();
    return taps;
  }

  testWidgets('the player stays usable through the hole', (tester) async {
    final taps = await pumpLayer(tester);
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.tapAt(const Offset(260, 190));
    expect(taps, ['player']);
    expect(lightsOff.value, isTrue);
  });

  testWidgets('a click on the dark part turns the lights on, not the page', (tester) async {
    final taps = await pumpLayer(tester);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(taps, isEmpty);
    expect(lightsOff.value, isFalse);
  });

  test('the hole follows the player box', () {
    expect(holeRect(GlobalKey(), null), isNull);
  });

  test('nextSpeed steps through the speed list and stops at its ends', () {
    const speeds = [2.0, 0.5, 1.0, 1.5];
    expect(nextSpeed(speeds, 1, 1), 1.5);
    expect(nextSpeed(speeds, 1, -1), 0.5);
    expect(nextSpeed(speeds, 2, 1), 2);
    expect(nextSpeed(speeds, 0.5, -1), 0.5);
    expect(nextSpeed(speeds, 1.2, 1), 1.5);
    expect(nextSpeed(const [], 1, 1), isNull);
  });

  test('关灯 preferences are saved and kept in range', () {
    final prefs = AppPreferences.fromJson(const AppPreferences().copyWith(autoLightsOff: true, lightsOffDim: 70).toJson());
    expect(prefs.autoLightsOff, isTrue);
    expect(prefs.lightsOffDim, 70);
    expect(AppPreferences.fromJson(const {'lightsOffDim': 10}).lightsOffDim, 50);
    expect(const AppPreferences().autoLightsOff, isFalse);
    expect(const AppPreferences().lightsOffDim, 85);
  });
}
