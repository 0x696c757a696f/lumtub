import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/common.dart';
import 'package:lumtub/ui/side_sheet.dart';

/// Opens a [PanelDialog] with [show] from a button in a window [size]
/// across, written in [direction].
Future<void> _open(WidgetTester tester, Size size, Future<void> Function(BuildContext, WidgetBuilder) show, {TextDirection direction = TextDirection.ltr}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => Directionality(textDirection: direction, child: child!),
    home: Builder(builder: (context) => Center(child: TextButton(
      onPressed: () => show(context, (context) => PanelDialog(
        title: const Text('Panel'),
        content: Column(children: [const Text('Body'), TextButton(onPressed: () {}, child: const Text('Inside'))]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      )),
      child: const Text('open'),
    ))),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Rect _sheet(WidgetTester tester) => tester.getRect(find.ancestor(of: find.text('Body'), matching: find.byType(Material)).first);

void main() {
  test('a side sheet is two fifths of the window, between 360 and 560 wide', () {
    expect(sideSheetWidth(800), 360);
    expect(sideSheetWidth(1200), 480);
    expect(sideSheetWidth(2000), 560);
  });

  testWidgets('a wide window opens a panel as a full-height sheet at the end edge', (tester) async {
    await _open(tester, const Size(1200, 800), showPanel);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(_sheet(tester), const Rect.fromLTWH(720, 0, 480, 800));
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Esc closes the side sheet', (tester) async {
    await _open(tester, const Size(1200, 800), showSheet);
    expect(find.text('Body'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('a tap on the scrim and the close button close the side sheet', (tester) async {
    await _open(tester, const Size(1200, 800), showPanel);
    await tester.tapAt(const Offset(100, 400));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('the back button closes the side sheet', (tester) async {
    await _open(tester, const Size(1200, 800), showPanel);
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    expect(await widgetsAppState.didPopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('Tab keeps the focus inside the side sheet', (tester) async {
    await _open(tester, const Size(1200, 800), showPanel);
    final sheet = find.ancestor(of: find.text('Body'), matching: find.byType(Material)).first;
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(focused, isNotNull);
      expect(find.descendant(of: sheet, matching: find.byWidget(focused!.widget)), findsWidgets);
    }
  });

  testWidgets('a right-to-left window opens the side sheet at its left edge', (tester) async {
    await _open(tester, const Size(1200, 800), showPanel, direction: TextDirection.rtl);
    expect(_sheet(tester), const Rect.fromLTWH(0, 0, 480, 800));
    // The close button sits at the end of the title, on the left.
    expect(tester.getCenter(find.byTooltip('Close')).dx, lessThan(tester.getCenter(find.text('Panel')).dx));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('a narrow window keeps the dialog', (tester) async {
    await _open(tester, const Size(640, 800), showPanel);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('a phone keeps the sheet from the bottom, and showSheet its dialog', (tester) async {
    debugTouchFirst = true;
    addTearDown(() => debugTouchFirst = null);
    await _open(tester, const Size(400, 800), showPanel);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byTooltip('Close'), findsNothing);
    final sheet = tester.getRect(find.byType(BottomSheet));
    expect(sheet.bottom, 800);
    expect(sheet.width, 400);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);

    await _open(tester, const Size(400, 800), showSheet);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('a tablet held either way opens the side sheet', (tester) async {
    debugTouchFirst = true;
    addTearDown(() => debugTouchFirst = null);
    await _open(tester, const Size(1024, 768), showPanel);
    expect(find.byType(BottomSheet), findsNothing);
    expect(_sheet(tester).right, 1024);
    expect(_sheet(tester).height, 768);
  });
}
