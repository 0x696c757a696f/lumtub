import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/level_test.dart';

LevelTestBank _bank(String language, {int levels = 6, int real = 30, int made = 15}) {
  final lines = ['# lumtub level test v1'];
  for (var l = 1; l <= levels; l++) {
    for (var i = 0; i < real; i++) {
      lines.add('w\t$l\t${language == 'zh' ? String.fromCharCodes([0x4e00 + l * 400 + i * 2, 0x4e01 + l * 400 + i * 2]) : 'real$l${'x' * (i % 5)}$i'}');
    }
    for (var i = 0; i < made; i++) {
      lines.add('n\t$l\t${language == 'zh' ? String.fromCharCodes([0x6000 + l * 200 + i * 2, 0x6001 + l * 200 + i * 2]) : 'made$l${'y' * (i % 5)}$i'}');
    }
  }
  lines.addAll(['bad line', 'w\tx\tword', 'q\t1\tword', 'w\t12\tword']);
  return LevelTestBank.parse(language, lines.join('\n'));
}

List<(LevelTestItem, bool)> _answer(List<LevelTestItem> items, {required int knownUpTo, required bool yesToMade}) =>
    [for (final i in items) (i, i.real ? i.level <= knownUpTo : yesToMade)];

void main() {
  test('items are read and bad lines skipped', () {
    final bank = LevelTestBank.parse('zh', 'w\t1\t学习\t學習\nn\t1\t找认\nw\tx\t坏\nq\t1\t坏\n');
    expect(bank.items.length, 2);
    expect(bank.items.first.shown(traditionalChinese: true), '學習');
    expect(bank.items.last.real, isFalse);
    expect(bank.beta, isFalse);
    expect(LevelTestBank.parse('fr', '').beta, isTrue);
  });

  test('a draw spreads real words over the levels, half as many made up, new each time', () {
    final bank = _bank('fr');
    expect(bank.usable, isTrue);
    final a = bank.draw(Random(1));
    final b = bank.draw(Random(2));
    final reals = a.where((i) => i.real).toList();
    expect(reals.length, 48);
    for (var l = 1; l <= 6; l++) {
      expect(reals.where((i) => i.level == l).length, 8);
    }
    expect(a.where((i) => !i.real).length, 24);
    expect(a.map((i) => i.text).toSet().length, a.length);
    expect(a.map((i) => i.text).toSet().intersection(b.map((i) => i.text).toSet()).length, lessThan(a.length));
  });

  test('Chinese draws never show a character twice', () {
    final items = _bank('zh', levels: 7).draw(Random(3));
    final chars = [for (final i in items) ...i.text.runes];
    expect(chars.toSet().length, chars.length);
  });

  test('an honest learner gets the level they know', () {
    final bank = _bank('es');
    final items = bank.draw(Random(4));
    final result = LevelTestResult.of('es', _answer(items, knownUpTo: 3, yesToMade: false));
    expect(result.level, 3);
    expect(result.falseAlarms, 0);
    expect(result.unreliable, isFalse);
    expect(result.known[3], 1);
    expect(result.known[4], 0);
  });

  test('saying yes to everything scores nothing and is flagged', () {
    final items = _bank('de').draw(Random(5));
    final result = LevelTestResult.of('de', _answer(items, knownUpTo: 9, yesToMade: true));
    expect(result.level, 0);
    expect(result.score, 0);
    expect(result.unreliable, isTrue);
  });

  test('yes to some made-up words lowers the known share', () {
    final items = _bank('it').draw(Random(6));
    var made = 0;
    final answers = [
      for (final i in items)
        if (i.real) (i, i.level <= 4) else (i, made++ < 6),
    ];
    final result = LevelTestResult.of('it', answers);
    expect(result.falseAlarms, closeTo(0.25, 0.01));
    // All of levels 1 to 4 said yes: still all known, but the score pays.
    expect(result.known[1], 1);
    expect(result.known[5], 0);
    expect(result.score, closeTo((32 - 2 * 6) / 48, 0.001));
    expect(result.level, 4);
  });

  test('a beginner who knows nothing is below the first level', () {
    final items = _bank('ru').draw(Random(7));
    final result = LevelTestResult.of('ru', _answer(items, knownUpTo: 0, yesToMade: false));
    expect(result.level, 0);
  });
}
