import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/live_chat_composer.dart';

void main() {
  test('writing in a live chat needs the cookie sign-in', () async {
    final box = await LiveChatComposer(null).open('dQw4w9WgXcQ');
    expect(box, isA<ChatBoxClosed>());
  });
}
