import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/live_chat.dart';
import 'package:lumtub/ui/live_chat_list.dart';

void main() {
  List<LiveChatMessage> messages(int count) => [
        for (var i = 0; i < count; i++) LiveChatMessage(id: 'm$i', author: 'a', text: 'message $i', kind: LiveChatKind.message),
      ];

  Widget chat(List<LiveChatMessage> list) => MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 300, child: LiveChatList(messages: list, messageAt: (i) => SizedBox(height: 40, child: Text(list[i].text)))),
        ),
      );

  testWidgets('the newest message stands at the bottom and new ones follow', (tester) async {
    await tester.pumpWidget(chat(messages(20)));
    expect(find.text('message 19'), findsOneWidget);
    expect(tester.getTopLeft(find.text('message 19')).dy, greaterThan(tester.getTopLeft(find.text('message 18')).dy));
    await tester.pumpWidget(chat(messages(21)));
    expect(find.text('message 20'), findsOneWidget);
  });

  testWidgets('scrolled up, the chat holds still and offers the new messages', (tester) async {
    await tester.pumpWidget(chat(messages(40)));
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('message 30')).dy;
    await tester.pumpWidget(chat(messages(43)));
    await tester.pump();
    expect(tester.getTopLeft(find.text('message 30')).dy, before);
    expect(find.text('3 条新消息'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('message 42'), findsOneWidget);
  });
}
