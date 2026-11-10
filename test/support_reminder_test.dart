import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/pages/support_page.dart';
import 'package:lumtub/support_reminder.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('reminder'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<SupportReminder> reload(SupportReminder reminder, File file) async {
    await reminder.saved;
    final again = SupportReminder(file);
    await again.load();
    return again;
  }

  test('asks after a week of use spread over two weeks, then every two months', () async {
    final file = File('${dir.path}/support_reminder.json');
    final reminder = SupportReminder(file);
    await reminder.load();
    final start = DateTime(2026, 1, 1, 12);
    for (var day = 0; day < 6; day++) {
      reminder.used(start.add(Duration(days: day)));
    }
    expect(reminder.due(start.add(const Duration(days: 30))), isFalse, reason: 'six days of use');
    reminder.used(start.add(const Duration(days: 6)));
    expect(reminder.due(start.add(const Duration(days: 13))), isFalse, reason: 'not two weeks yet');
    final first = start.add(const Duration(days: 14));
    expect(reminder.due(first), isTrue);
    reminder.asked(first);
    expect(reminder.due(first.add(const Duration(days: 59))), isFalse);
    expect(reminder.due(first.add(const Duration(days: 60))), isTrue);

    final again = await reload(reminder, file);
    expect(again.due(first.add(const Duration(days: 59))), isFalse, reason: 'last time kept');
    expect(again.due(first.add(const Duration(days: 60))), isTrue);
  });

  test("don't ask again sticks", () async {
    final file = File('${dir.path}/support_reminder.json');
    final reminder = SupportReminder(file);
    final start = DateTime(2026, 1, 1, 12);
    for (var day = 0; day < 20; day++) {
      reminder.used(start.add(Duration(days: day)));
    }
    reminder.enabled = false;
    expect(reminder.due(start.add(const Duration(days: 400))), isFalse);
    final again = await reload(reminder, file);
    expect(again.enabled, isFalse);
    expect(again.due(start.add(const Duration(days: 400))), isFalse);
  });

  test('a broken file starts over', () async {
    final file = File('${dir.path}/support_reminder.json')..writeAsStringSync('{');
    final reminder = SupportReminder(file);
    await reminder.load();
    expect(reminder.enabled, isTrue);
    expect(reminder.due(DateTime(2030)), isFalse);
  });

  testWidgets("the question offers support, later and don't ask again", (tester) async {
    final reminder = SupportReminder(File('${dir.path}/support_reminder.json'));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(onPressed: () => askForSupport(context, reminder), child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Enjoying Lumtub?'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(reminder.enabled, isTrue);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Don't ask again"));
    await tester.pumpAndSettle();
    expect(reminder.enabled, isFalse);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  });
}
