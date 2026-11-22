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

  testWidgets('words with a space between stand as far apart as the space', (tester) async {
    const tokens = [
      WordToken('But', null, isWord: true),
      WordToken(' ', null, isWord: false),
      WordToken('we', null, isWord: true),
      WordToken(', ', null, isWord: false),
      WordToken('also', null, isWord: true),
    ];
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: ChineseRubyLine(tokens: tokens, style: TextStyle(fontSize: 20), outline: 3))),
    ));
    final but = tester.getRect(find.text('But').last);
    final we = tester.getRect(find.text('we').last);
    final space = tester.getRect(find.text(' ').last);
    expect(we.left - but.right, closeTo(space.width, 0.5));
  });

  testWidgets('a subtitle background is one box behind the line', (tester) async {
    const tokens = [WordToken('to', null, isWord: true), WordToken(' ', null, isWord: false), WordToken('the', null, isWord: true)];
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: ChineseRubyLine(tokens: tokens, style: TextStyle(fontSize: 20, backgroundColor: Color(0xAA000000))))),
    ));
    expect(find.byType(DecoratedBox), findsOneWidget);
    final words = tester.widgetList<Text>(find.text('to'));
    expect(words.every((t) => t.style?.backgroundColor?.a == 0), isTrue);
  });

  testWidgets('a press drawn across words looks them up as one phrase, spaces kept', (tester) async {
    const tokens = [
      WordToken('I', null, isWord: true, lookup: 'i', language: 'en'),
      WordToken(' ', null, isWord: false),
      WordToken('Looked', null, isWord: true, lookup: 'looked', language: 'en'),
      WordToken(' ', null, isWord: false),
      WordToken('up', null, isWord: true, language: 'en'),
      WordToken(' ', null, isWord: false),
      WordToken('it', null, isWord: true, language: 'en'),
    ];
    final hits = RubyHits();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder(
            valueListenable: hits.selection,
            builder: (context, _, child) => ChineseRubyLine(tokens: tokens, style: const TextStyle(fontSize: 20), hits: hits),
          ),
        ),
      ),
    ));
    final from = tester.getCenter(find.text('up'));
    final to = tester.getCenter(find.text('Looked'));
    expect(hits.select(from, from, done: false), isNull);
    expect(hits.select(from, to, done: false), isNull);
    await tester.pump();
    // The chosen words are marked while the finger is down.
    expect(hits.selection.value, (2, 4));
    expect(find.byWidgetPredicate((w) => w is DecoratedBox && (w.decoration as BoxDecoration).color == const Color(0x993B82F6)), findsNWidgets(2));
    final phrase = hits.select(to, to, done: true)!;
    expect(phrase.text, 'Looked up');
    expect(phrase.key, 'looked up');
    expect(phrase.language, 'en');
    expect(hits.selection.value, isNull);
    // One word stays the token it was.
    hits.select(to, to, done: false);
    expect(hits.select(to, to, done: true)!.key, 'looked');
  });

  test('Chinese words chosen together join without spaces', () {
    final hits = RubyHits()..clear(const [WordToken('人工', 'rén gōng', isWord: true), WordToken('智能', 'zhì néng', isWord: true)]);
    final phrase = hits.phrase(0, 1);
    expect(phrase.text, '人工智能');
    expect(phrase.key, '人工智能');
  });
}
