import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/comments_view.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('posts the text and clears the field once it went through', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CommentComposer(hint: 'Add a comment…', onSubmit: (text) async {
      sent.add(text);
      return true;
    }))));
    final send = find.widgetWithText(FilledButton, 'Publish');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  第一条  ');
    await tester.pump();
    await tester.tap(send);
    await tester.pump();
    expect(sent, ['第一条']);
    expect(find.text('  第一条  '), findsNothing);
  });
  testWidgets('long button labels fit a narrow panel', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: 200, child: CommentComposer(
      hint: 'Add a reply…',
      onSubmit: (_) async => true,
      onCancel: () {},
      thanksFor: 'x',
    ))))));
    expect(tester.takeException(), isNull);
  });
}
