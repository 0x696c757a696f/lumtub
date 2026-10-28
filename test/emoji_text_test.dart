import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/emoji_text.dart';

void main() {
  testWidgets('custom emoji shortcuts become pictures, the rest stays text', (tester) async {
    late List<InlineSpan> spans;
    late List<InlineSpan> plain;
    await tester.pumpWidget(Builder(builder: (context) {
      spans = emojiSpans(context, 'hi :_wave: and :_wave:!', {':_wave:': 'https://yt3/w'});
      plain = emojiSpans(context, 'no :emoji: here', const {});
      return const SizedBox();
    }));
    expect(spans.map((s) => s is TextSpan ? s.text : 'IMG'), ['hi ', 'IMG', ' and ', 'IMG', '!']);
    expect(plain.map((s) => (s as TextSpan).text), ['no :emoji: here']);
  });
}
