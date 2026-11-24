import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/animated_visibility.dart';

void main() {
  Future<double Function(Finder)> pumpRow(WidgetTester tester, Widget Function(bool) panel, ValueNotifier<bool> open) async {
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder(
        valueListenable: open,
        builder: (context, shown, _) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Expanded(child: SizedBox(key: Key('page'))),
          panel(shown),
        ]),
      ),
    ));
    return (finder) => tester.getSize(finder).width;
  }

  testWidgets('a side panel slides in from the end and the page gives up the room as it moves', (tester) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final open = ValueNotifier(false);
    final width = await pumpRow(tester, (shown) => AnimatedVisibility.side(visible: shown, child: const SizedBox(key: Key('panel'), width: 300)), open);
    expect(find.byKey(const Key('panel')), findsNothing);
    expect(width(find.byKey(const Key('page'))), 1000);
    open.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(width(find.byKey(const Key('page'))), inExclusiveRange(700, 1000));
    await tester.pump(AnimatedVisibility.duration);
    expect(width(find.byKey(const Key('page'))), 700);
    expect(tester.getTopLeft(find.byKey(const Key('panel'))).dx, 700);
    open.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const Key('panel')), findsNothing);
  });

  testWidgets('a top bar folds upward', (tester) async {
    final shown = ValueNotifier(true);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder(
        valueListenable: shown,
        builder: (context, visible, _) => Column(children: [
          AnimatedVisibility.topBar(visible: visible, child: const SizedBox(key: Key('bar'), height: 56)),
          const Expanded(child: SizedBox(key: Key('page'))),
        ]),
      ),
    ));
    expect(tester.getTopLeft(find.byKey(const Key('page'))).dy, 56);
    shown.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(find.byKey(const Key('page'))).dy, inExclusiveRange(0, 56));
    await tester.pump(AnimatedVisibility.duration);
    expect(tester.getTopLeft(find.byKey(const Key('page'))).dy, 0);
    expect(find.byKey(const Key('bar')), findsNothing);
  });
}
