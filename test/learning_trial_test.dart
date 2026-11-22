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

  test('the first lookups have everything on; the same word today again is free', () async {
    final learning = await _learning(null);
    expect(learning.inTrial, isTrue);
    expect(learning.unlocked, isTrue);
    for (var i = 0; i < Learning.trialTotal - 1; i++) {
      expect(await learning.takeLookup('w$i'), isTrue);
    }
    expect(await learning.takeLookup('w0'), isTrue);
    expect(learning.trialTotalLeft, 1);
    expect(await learning.takeLookup('last'), isTrue);
    // The last trial card stays fully on until it closes.
    expect(learning.unlocked, isTrue);
    expect(learning.closeTrialCard(), isTrue);
    expect(learning.unlocked, isFalse);
    expect(learning.closeTrialCard(), isFalse);
  });

  test('after the trial, a few new words a day; one seen today again is free', () async {
    final learning = await _learning({'taken': Learning.trialTotal});
    expect(learning.inTrial, isFalse);
    for (var i = 0; i < Learning.trialPerDay; i++) {
      expect(await learning.takeLookup('w$i'), isTrue);
    }
    expect(await learning.takeLookup('another'), isFalse);
    expect(await learning.takeLookup('w0'), isTrue);
    expect(learning.trialLeft, 0);
  });

  test('turning the clock back does not give the day back', () async {
    final used = await _learning({'taken': Learning.trialTotal, 'seen': _day(2), 'day': _day(2), 'used': Learning.trialPerDay});
    expect(await used.takeLookup('new'), isFalse);
  });

  test('locked after the trial: no hard words marked', () async {
    final over = await _learning({'taken': Learning.trialTotal});
    expect(over.unlocked, isFalse);
    expect(over.isHard(const WordToken('serendipity', null, isWord: true)), isFalse);
  });
}
