import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/app_preferences.dart';
import 'package:lumtub/shortcut_bindings.dart';
import 'package:lumtub/ui/player_shortcuts.dart';
import 'package:lumtub/ui/shortcut_settings.dart';

void main() {
  const bracketLeft = KeyCombo(LogicalKeyboardKey.bracketLeft);
  const bracketRight = KeyCombo(LogicalKeyboardKey.bracketRight);
  const parenLeft = KeyCombo(LogicalKeyboardKey.digit9, shift: true);

  test('a key combination reads back from its saved form', () {
    for (final combo in [bracketLeft, parenLeft, const KeyCombo(LogicalKeyboardKey.keyC, control: true, alt: true, meta: true)]) {
      expect(KeyCombo.parse(combo.id), combo);
      expect(KeyCombo.parse(combo.id)!.activator.trigger, combo.key);
    }
    expect(KeyCombo.parse('nonsense'), isNull);
    expect(parenLeft.label, 'Shift + 9');
    expect(const KeyCombo(LogicalKeyboardKey.arrowLeft).label, '←');
  });

  test('with nothing saved every action has its old keys', () {
    final keys = shortcutKeys(const {});
    expect(keys[PlayerAction.seekBack], [const KeyCombo(LogicalKeyboardKey.arrowLeft)]);
    expect(keys[PlayerAction.previous], contains(bracketLeft));
    expect(keys.length, PlayerAction.values.length);
  });

  test('a key given to another action leaves the one that had it, as with wiliwili\'s [ ]', () {
    var saved = withShortcutKeys(const {}, PlayerAction.seekBack, [const KeyCombo(LogicalKeyboardKey.arrowLeft), bracketLeft]);
    saved = withShortcutKeys(saved, PlayerAction.seekForward, [const KeyCombo(LogicalKeyboardKey.arrowRight), bracketRight]);
    final keys = shortcutKeys(saved);
    expect(keys[PlayerAction.seekBack], contains(bracketLeft));
    expect(keys[PlayerAction.previous], [const KeyCombo(LogicalKeyboardKey.keyP, shift: true)]);
    expect(keys[PlayerAction.next], [const KeyCombo(LogicalKeyboardKey.keyN, shift: true)]);
    expect(actionOfKey(keys, bracketRight), PlayerAction.seekForward);
    // Only what changed is written out.
    expect(saved.keys.toSet(), {'seekBack', 'seekForward'});
  });

  test('the shifted keys of ( ) work for volume and stay apart from 9 and 0', () {
    final saved = withShortcutKeys(const {}, PlayerAction.volumeDown, [parenLeft]);
    final keys = shortcutKeys(saved);
    expect(keys[PlayerAction.volumeDown], [parenLeft]);
    expect(fixedKey(parenLeft), isFalse);
    expect(fixedKey(const KeyCombo(LogicalKeyboardKey.digit9)), isTrue);
  });

  test('resetting an action takes its keys back from others', () {
    var saved = withShortcutKeys(const {}, PlayerAction.mute, [const KeyCombo(LogicalKeyboardKey.keyF)]);
    expect(shortcutKeys(saved)[PlayerAction.fullscreen], isEmpty);
    saved = resetShortcutKeys(saved, PlayerAction.fullscreen);
    final keys = shortcutKeys(saved);
    expect(keys[PlayerAction.fullscreen], [const KeyCombo(LogicalKeyboardKey.keyF)]);
    expect(keys[PlayerAction.mute], isEmpty);
  });

  test('saved keys come back through the preferences file', () {
    final saved = withShortcutKeys(const {}, PlayerAction.seekBack, [bracketLeft]);
    final prefs = AppPreferences.fromJson(const AppPreferences().copyWith(shortcutKeys: saved, rightClickBack: true).toJson());
    expect(shortcutKeys(prefs.shortcutKeys)[PlayerAction.seekBack], [bracketLeft]);
    expect(prefs.rightClickBack, isTrue);
    final help = playerShortcutHelp(prefs).map((e) => e.$1).join(' | ');
    expect(help, contains('[ / →'));
  });

  test('a fixed key saved by hand is ignored', () {
    final keys = shortcutKeys({'seekBack': [const KeyCombo(LogicalKeyboardKey.digit1).id]});
    expect(keys[PlayerAction.seekBack], isEmpty);
  });

  testWidgets('the settings window takes a pressed key over from the action that had it', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = AppController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(onPressed: () => showShortcutSettings(context, controller), child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final row = find.ancestor(of: find.text('Back 5 s'), matching: find.byType(Row)).first;
    await tester.tap(find.descendant(of: row, matching: find.byTooltip('Add a key')));
    await tester.pumpAndSettle();
    expect(find.text('Press a key'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(find.text('Press a key'), findsOneWidget, reason: 'digits stay fixed');
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pumpAndSettle();
    expect(find.text('Press a key'), findsNothing);
    final keys = shortcutKeys(controller.preferences.shortcutKeys);
    expect(keys[PlayerAction.seekBack], contains(bracketLeft));
    expect(keys[PlayerAction.previous], isNot(contains(bracketLeft)));
    expect(find.textContaining('was taken from'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
