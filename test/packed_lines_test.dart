import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/chinese_dictionary.dart';
import 'package:lumtub/learning/japanese_dictionary.dart';
import 'package:lumtub/learning/packed_lines.dart';

void main() {
  test('keys find their lines in file order, once a line', () {
    final bytes = utf8.encode('a b\r\nb\n\nc a a\nb');
    final lines = PackedLines.build(bytes, (start, end, key) {
      var at = start;
      for (var i = start; i <= end; i++) {
        if (i == end || bytes[i] == 0x20) {
          key(at, i);
          at = i + 1;
        }
      }
    });
    expect(lines.size, 4);
    expect([for (final i in lines.linesOf('a')) lines.line(i)], ['a b', 'c a a']);
    expect([for (final i in lines.linesOf('b')) lines.line(i)], ['a b', 'b', 'b']);
    expect(lines.linesOf('d'), isEmpty);
    expect(lines.contains(''), isFalse);
    expect(lines.contains('c'), isTrue);
  });

  test('many keys, each found', () {
    final text = [for (var i = 0; i < 5000; i++) '語$i\tご$i\t\tword $i\t1'].join('\n');
    final d = JapaneseDictionary.parse(text);
    expect(d.size, 5000);
    for (final i in [0, 1, 2499, 4999]) {
      expect(d.lookup('語$i').single.kana, ['ご$i']);
      expect(d.lookup('ご$i').single.kanji, ['語$i']);
    }
    expect(d.lookup('語5000'), isEmpty);
  });

  test('CC-CEDICT lines found by both scripts, comments left out', () {
    final d = ChineseDictionary.parse('# CC-CEDICT\n傳統 传统 [chuan2 tong3] /tradition/\n中 中 [zhong1] /middle/\nbroken line\n');
    expect(d.size, 2);
    expect(d.lookup('传统').single.traditional, '傳統');
    expect(d.lookup('傳統').single.simplified, '传统');
    expect(d.contains('中'), isTrue);
    expect(d.longest, 2);
  });
}
