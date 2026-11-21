import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/word_token.dart';
import 'package:lumtub/ui/learning/ruby_line.dart';

void main() {
  testWidgets('Japanese words stand close, a long reading fits over its word', (tester) async {
    const tokens = [
      WordToken('商業', 'しょうぎょう', isWord: true, language: 'ja'),
      WordToken('や', null, isWord: true, language: 'ja'),
      WordToken('産業', 'さんぎょう', isWord: true, language: 'ja'),
      WordToken('属する', 'ぞくする', isWord: true, language: 'ja'),
    ];
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: ChineseRubyLine(tokens: tokens, style: TextStyle(fontSize: 20), outline: 1))),
    ));
    expect(tester.takeException(), isNull);
    final word = tester.getRect(find.text('商業').last);
    final next = tester.getRect(find.text('や').last);
    // Only the outline's room between Japanese words, no space.
    expect(next.left - word.right, lessThan(2));
    // The reading stays within its word plus half a letter on each free side.
    final reading = tester.getRect(find.text('しょうぎょう').last);
    expect(reading.width, lessThanOrEqualTo(word.width + 20 + 0.5));
    // Between two words with readings, a long one is set smaller instead.
    final squeezed = tester.getRect(find.text('さんぎょう').last);
    expect(squeezed.width, lessThanOrEqualTo(tester.getRect(find.text('産業').last).width + 10 + 0.5));
  });
}
