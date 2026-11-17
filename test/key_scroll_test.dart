import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/common.dart';
import 'package:lumtub/ui/key_scroll.dart';

Widget _twoLists(ScrollController left, ScrollController right, {List<FocusNode>? leftNodes}) => MaterialApp(
      home: Row(children: [
        Expanded(child: ListView.builder(
          key: const Key('left'),
          controller: left,
          itemCount: 100,
          itemExtent: 50,
          itemBuilder: (context, i) => TextButton(focusNode: leftNodes?[i], onPressed: () {}, child: Text('L$i')),
        )),
        Expanded(child: ListView.builder(
          key: const Key('right'),
          controller: right,
          itemCount: 100,
          itemExtent: 50,
          itemBuilder: (context, i) => TextButton(onPressed: () {}, child: Text('R$i')),
        )),
      ]),
    );

void main() {
  setUp(KeyScroll.watch);

  testWidgets('the list under the mouse turns the page', (tester) async {
    final left = ScrollController();
    final right = ScrollController();
    await tester.pumpWidget(_twoLists(left, right));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byKey(const Key('right'))));
    await mouse.moveBy(const Offset(1, 1));
    await tester.pump();
    expect(KeyScroll.byPage(1), isTrue);
    await tester.pumpAndSettle();
    expect(right.offset, greaterThan(0));
    expect(left.offset, 0);
    await mouse.removePointer();
  });

  testWidgets('the focus moved by the keyboard since then wins, and is kept in sight', (tester) async {
    final left = ScrollController();
    final right = ScrollController();
    final nodes = List.generate(100, (i) => FocusNode(debugLabel: 'L$i'));
    addTearDown(() {
      for (final node in nodes) {
        node.dispose();
      }
    });
    await tester.pumpWidget(_twoLists(left, right, leftNodes: nodes));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byKey(const Key('right'))));
    await mouse.moveBy(const Offset(1, 1));
    await tester.pump();
    nodes[0].requestFocus();
    await tester.pump();
    expect(KeyScroll.byPage(1), isTrue);
    await tester.pumpAndSettle();
    expect(left.offset, greaterThan(0));
    expect(right.offset, 0);
    // The first button was scrolled away: the focus is on one in sight.
    expect(nodes[0].hasPrimaryFocus, isFalse);
    final focused = nodes.indexWhere((node) => node.hasPrimaryFocus);
    expect(focused, greaterThan(0));
    expect(focused * 50.0, greaterThanOrEqualTo(left.offset));
    await mouse.removePointer();
  });

  testWidgets('with the mouse away the focused list turns', (tester) async {
    final left = ScrollController();
    final right = ScrollController();
    final nodes = List.generate(100, (i) => FocusNode());
    addTearDown(() {
      for (final node in nodes) {
        node.dispose();
      }
    });
    await tester.pumpWidget(_twoLists(left, right, leftNodes: nodes));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byKey(const Key('right'))));
    await mouse.removePointer();
    nodes[3].requestFocus();
    await tester.pump();
    KeyScroll.byPage(1);
    await tester.pumpAndSettle();
    expect(left.offset, greaterThan(0));
    expect(right.offset, 0);
  });

  testWidgets('arrow keys leave a one-line field once at its end, Esc leaves it', (tester) async {
    final field = FocusNode();
    final below = FocusNode();
    final text = TextEditingController(text: 'abc');
    addTearDown(() {
      field.dispose();
      below.dispose();
      text.dispose();
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
      LeavesByKeys(child: TextField(focusNode: field, controller: text)),
      TextButton(focusNode: below, onPressed: () {}, child: const Text('below')),
    ]))));
    field.requestFocus();
    await tester.pump();
    text.selection = const TextSelection.collapsed(offset: 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // The caret goes to the end first.
    expect(field.hasPrimaryFocus, isTrue);
    expect(text.selection.baseOffset, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(below.hasPrimaryFocus, isTrue);

    field.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(field.hasFocus, isFalse);
  });

  testWidgets('a page finds what it kept when it comes back', (tester) async {
    final kept = <String?>[];
    Widget page() => Builder(builder: (context) {
          final memory = PageMemory<String>('test');
          kept.add(memory.recall(context));
          memory.keep('picked');
          return const SizedBox();
        });
    await tester.pumpWidget(MaterialApp(home: page()));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(MaterialApp(home: page()));
    expect(kept, [null, 'picked']);
  });

  testWidgets('a sideways strip in a page list keeps its own scroll position', (tester) async {
    final strip = ScrollController();
    final list = ScrollController();
    Widget page(bool shown) => MaterialApp(home: shown
        ? ListView(key: const PageStorageKey('list'), controller: list, children: [
            SizedBox(height: 40, child: FilterFlowStrip(controller: strip)),
            for (var i = 0; i < 100; i++) SizedBox(height: 50, child: Text('$i')),
          ])
        : const SizedBox());
    await tester.pumpWidget(page(true));
    strip.jumpTo(30);
    await tester.pump();
    strip.position.didEndScroll();
    list.jumpTo(800);
    await tester.pump();
    list.position.didEndScroll();
    await tester.pumpWidget(page(false));
    await tester.pumpWidget(page(true));
    expect(list.offset, 800);
  });
}

/// A sideways list keyed as the pages key theirs.
class FilterFlowStrip extends StatelessWidget {
  const FilterFlowStrip({super.key, required this.controller});
  final ScrollController controller;

  @override
  Widget build(BuildContext context) => ListView(
        key: const PageStorageKey('channel-strip'),
        controller: controller,
        scrollDirection: Axis.horizontal,
        children: [for (var i = 0; i < 40; i++) SizedBox(width: 60, child: Text('$i'))],
      );
}
