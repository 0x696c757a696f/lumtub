import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/japanese_dictionary.dart';

const _sample = '食べる\tたべる\tv1\tto eat\t1\n'
    '行く|往く\tいく|ゆく\tv5k-s\tto go\t1\n'
    '読む\tよむ\tv5m\tto read\t1\n'
    '美味しい\tおいしい\tadj-i\tdelicious\t1\n'
    '勉強\tべんきょう\tvs\tstudy\t1\n'
    '来る\tくる\tvk\tto come\t1\n'
    '\tは\t\ttopic marker\t1\n'
    '\tまだ\t\tstill; not yet\t1\n'
    '浜\tはま\t\tbeach\t1\n'
    '私\tわたし\t\tI; me\t1\n';

void main() {
  final d = JapaneseDictionary.parse(_sample);

  test('a word in kana finds the kanji word people mean, not the first read alike', () {
    final alike = JapaneseDictionary.parse(
        '一敗\tいっぱい\tvs\tone defeat\t1\n一杯|一盃\tいっぱい\t\tone cup\\nfull\\na lot\t1\n');
    expect(alike.lookup('いっぱい').first.headword, '一杯');
    expect(alike.lookup('一敗').first.headword, '一敗');
  });

  test('an entry reads its Chinese meanings', () {
    final entry = JapaneseEntry.parse('主権\tしゅけん\t\tsovereignty\t1\tn. 主权\\nn. 统治权');
    expect(entry.chinese, ['n. 主权', 'n. 统治权']);
    expect(JapaneseEntry.parse('犬\tいぬ\t\tdog\t1').chinese, isEmpty);
  });

  test('inflected verbs and adjectives find their dictionary form', () {
    String base(String text) => d.lookUpInflected(text).first.$2.first.headword;
    expect(base('食べなかった'), '食べる');
    expect(base('食べられませんでした'), '食べる');
    expect(base('読んでいます'), '読む');
    expect(base('行った'), '行く');
    expect(base('美味しくなかった'), '美味しい');
    expect(base('勉強しています'), '勉強');
  });

  test('a line splits into words with kana for kanji', () {
    final tokens = d.segment('私はまだ食べていない。');
    expect(tokens.map((t) => t.text), ['私', 'は', 'まだ', '食べていない', '。']);
    expect(tokens[0].reading, 'わたし');
    expect(tokens[3].reading, 'たべていない');
    expect(tokens[1].reading, isNull);
    expect(tokens[3].language, 'ja');
  });

  test('来る is read by what follows it', () {
    expect(d.segment('来ない').single.reading, 'こない');
    expect(d.segment('来ました').single.reading, 'きました');
  });

  test('Japanese is told by its kana', () {
    expect(JapaneseDictionary.looksJapanese('私は学生です'), isTrue);
    expect(JapaneseDictionary.looksJapanese('我是学生'), isFalse);
  });
}
