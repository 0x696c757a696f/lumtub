import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/live_chat_composer.dart';
import 'package:lumtub/ui/emoji_picker.dart';

void main() {
  test('groups split into whole emoji in their emoji form', () {
    expect(emojiOf('😀😮‍💨❤👍'), ['😀', '😮‍💨', '❤\u{FE0F}', '👍']);
    for (final (_, group) in emojiGroups) {
      expect(emojiOf(group).toSet().length, emojiOf(group).length);
    }
  });

  test('a picked emoji goes where the cursor is', () {
    final field = TextEditingController(text: 'ab')..selection = const TextSelection.collapsed(offset: 1);
    insertAtCursor(field, '😀');
    expect(field.text, 'a😀b');
    expect(field.selection.baseOffset, 3);
    field.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    insertAtCursor(field, ':_wave:');
    expect(field.text, ':_wave:😀b');
  });

  testWidgets('the picker inserts emoji and channel emoji, not locked ones', (tester) async {
    final field = TextEditingController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: EmojiButton(field: field, channel: const [
      ChannelEmoji(id: 'UCx/wave', shortcut: ':_wave:', url: 'https://example.com/w.png'),
      ChannelEmoji(id: 'UCx/vip', shortcut: ':_vip:', url: 'https://example.com/v.png', locked: true),
    ])))));
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('😂'));
    await tester.tap(find.byTooltip(':_wave:'));
    await tester.tap(find.byTooltip(':_vip: (for members)'));
    await tester.pump();
    expect(field.text, '😂:_wave:');
  });
}
