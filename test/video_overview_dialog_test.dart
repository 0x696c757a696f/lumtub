import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/ui/summary_dialog.dart';
import 'package:lumtub/ui/video_notes.dart';

void main() {
  Future<AppController> pump(WidgetTester tester, Size size, void Function(BuildContext context, AppController controller) open) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = AppController()..ready = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(onPressed: () => open(context, controller), child: const Text('open'))),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return controller;
  }

  for (final size in const [Size(1400, 900), Size(400, 800)]) {
    testWidgets('AI summary shows the notes on the video under it at ${size.width.toInt()} px', (tester) async {
      await pump(tester, size, (context, controller) => showVideoSummary(context, controller));
      expect(find.text('My notes'), findsOneWidget);
      expect(find.byTooltip('Add a note here'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a note starts from the subtitle words', (tester) async {
    await pump(tester, const Size(1000, 800), (context, controller) => showNoteEditor(context, controller, at: const Duration(seconds: 65), quote: 'Batteries hate the cold.'));
    expect(find.text('Note at 01:05'), findsOneWidget);
    expect(find.text('Batteries hate the cold.'), findsOneWidget);
    expect(find.text('Your note'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Your note'), findsNothing);
  });
}
