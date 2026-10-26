import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/ui/video_card.dart';

void main() {
  testWidgets('a card reached with the keyboard shows focus and its actions, and opens', (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 300,
          child: VideoCard(item: const VideoItem(id: 'abcdefghijk', title: '标题', channel: '频道', url: 'u'), onOpen: () => opened++),
        ),
      ),
    ));
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text('复制链接'), findsOneWidget);
  });
}
