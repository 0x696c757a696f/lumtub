import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/chip_strip.dart';
import 'package:lumtub/ui/common.dart';

Future<List<int>> _show(WidgetTester tester, {required int count, int selected = 0, double width = 400}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final picked = <int>[];
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: CustomScrollView(slivers: [
    const SliverToBoxAdapter(child: SizedBox(height: 300)),
    SliverToBoxAdapter(child: StatefulBuilder(builder: (context, setState) => ChipStrip(
      title: 'Topics',
      choices: [for (var i = 0; i < count; i++) (label: 'Chip $i', icon: null)],
      selected: selected,
      onSelected: (i) => setState(() {
        picked.add(i);
        selected = i;
      }),
    ))),
    const SliverToBoxAdapter(child: SizedBox(height: 1000)),
  ]))));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return picked;
}

double _pageOffset(WidgetTester tester) => tester.state<ScrollableState>(find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)).position.pixels;

void main() {
  tearDown(() => debugTouchFirst = null);

  testWidgets('a short row has no Show all button', (tester) async {
    await _show(tester, count: 2);
    expect(find.byTooltip('Show all'), findsNothing);
  });

  testWidgets('a long row stays one line, keeps the selected chip in view without moving the page', (tester) async {
    await _show(tester, count: 30, selected: 20);
    expect(find.byTooltip('Show all'), findsOneWidget);
    final rect = tester.getRect(find.text('Chip 20'));
    expect(rect.left, greaterThan(0));
    expect(rect.right, lessThan(400));
    expect(tester.getRect(find.text('Chip 0')).top, rect.top, reason: 'one line');
    expect(_pageOffset(tester), 0);
  });

  testWidgets('Show all lists every choice; picking one selects it and scrolls to it', (tester) async {
    final picked = await _show(tester, count: 30);
    await tester.tap(find.byTooltip('Show all'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.widgetWithText(MenuItemButton, 'Chip 25'), 100, scrollable: find.descendant(of: find.byType(MenuAnchor), matching: find.byType(Scrollable)).last);
    await tester.tap(find.widgetWithText(MenuItemButton, 'Chip 25'));
    await tester.pumpAndSettle();
    expect(picked, [25]);
    final rect = tester.getRect(find.text('Chip 25'));
    expect(rect.left, greaterThan(0));
    expect(rect.right, lessThan(400));
  });

  testWidgets('on a phone Show all is a sheet', (tester) async {
    debugTouchFirst = true;
    tester.view.physicalSize = const Size(390, 800);
    final picked = await _show(tester, count: 30, width: 390);
    await tester.tap(find.byTooltip('Show all'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Chip 3'));
    await tester.pumpAndSettle();
    expect(picked, [3]);
  });

  testWidgets('the mouse wheel scrolls the row sideways, then the page at its end', (tester) async {
    await _show(tester, count: 30);
    final row = find.byType(ChipStrip);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(row)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 200)));
    await tester.pump();
    expect(_pageOffset(tester), 0);
    expect(tester.getRect(find.text('Chip 0')).left, lessThan(0));
    for (var i = 0; i < 40; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 200)));
      await tester.pump();
    }
    expect(_pageOffset(tester), greaterThan(0));
  });
}
