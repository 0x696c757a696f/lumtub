import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_directories.dart';
import 'package:lumtub/learning/learning.dart';
import 'package:lumtub/learning/word_token.dart';

String _day(int fromToday) => DateTime.now().add(Duration(days: fromToday)).toIso8601String().substring(0, 10);

Future<Learning> _learning(Map<String, Object?>? trial) async {
  final root = Directory.systemTemp.createTempSync('trial');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory('${root.path}/config').createSync(recursive: true);
  if (trial != null) File('${root.path}/config/learning.json').writeAsStringSync(jsonEncode({'trial': trial}));
  final learning = Learning();
  await learning.start(AppDirectories.at(root));
  return learning;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the first week is unlimited from the first lookup', () async {
    final learning = await _learning(null);
    expect(learning.inFreeWeek, isTrue);
    for (var i = 0; i < 30; i++) {
      expect(await learning.takeLookup('w$i'), isTrue);
    }
    expect(learning.freeWeekLeft, Learning.trialDays);
  });

  test('after the week, a few new words a day; one seen today again is free', () async {
    final learning = await _learning({'start': _day(-7)});
    expect(learning.inFreeWeek, isFalse);
    for (var i = 0; i < Learning.trialPerDay; i++) {
      expect(await learning.takeLookup('w$i'), isTrue);
    }
    expect(await learning.takeLookup('another'), isFalse);
    expect(await learning.takeLookup('w0'), isTrue);
    expect(learning.trialLeft, 0);
  });

  test('turning the clock back neither stretches the week nor gives lookups back', () async {
    // Started 3 days ago, but the clock was 10 days ahead once: the week is over.
    final learning = await _learning({'start': _day(-3), 'seen': _day(10)});
    expect(learning.inFreeWeek, isFalse);
    // Today's lookups were counted on the later day the trial saw.
    final used = await _learning({'start': _day(-20), 'seen': _day(2), 'day': _day(2), 'used': Learning.trialPerDay});
    expect(await used.takeLookup('new'), isFalse);
  });

  test('a trial counted a day at a time before the free week began on that day', () async {
    final learning = await _learning({'day': _day(-8), 'used': 3});
    expect(learning.inFreeWeek, isFalse);
    expect(learning.trialLeft, Learning.trialPerDay);
  });

  test('the pack is unlocked in the week and locked after it', () async {
    expect((await _learning(null)).unlocked, isTrue);
    expect((await _learning({'start': _day(-6)})).unlocked, isTrue);
    final over = await _learning({'start': _day(-7)});
    expect(over.unlocked, isFalse);
    expect(over.isHard(const WordToken('serendipity', null, isWord: true)), isFalse);
  });
}
