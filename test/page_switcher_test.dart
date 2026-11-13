import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/motion.dart';
import 'package:lumtub/ui/page_switcher.dart';

void main() {
  // The page area: 400 wide, its left edge at 200 in an 800 wide test view.
  const left = 200.0;
  const width = 400.0;

  Widget area(String page, int? index, {TextDirection direction = TextDirection.ltr, bool slides = true, FocusNode? focus}) => Directionality(
        textDirection: direction,
        child: Center(
          child: SizedBox(
            width: width,
            height: 300,
            child: PageSwitcher(
              pageKey: page,
              index: index,
              slides: slides,
              child: Focus(focusNode: page == 'home' ? focus : null, child: SizedBox.expand(key: ValueKey('page $page'))),
            ),
          ),
        ),
      );

  double x(WidgetTester tester, String page) => tester.getTopLeft(find.byKey(ValueKey('page $page'))).dx;

  testWidgets('a later tab comes in from the end side, the old page leaving to the start', (tester) async {
    await tester.pumpWidget(area('home', 0));
    await tester.pumpWidget(area('library', 3));
    await tester.pump(const Duration(milliseconds: 40));
    expect(x(tester, 'library'), greaterThan(left));
    expect(x(tester, 'library'), lessThanOrEqualTo(left + width * PageSwitcher.distance));
    expect(x(tester, 'home'), lessThan(left));
    expect(x(tester, 'home'), greaterThanOrEqualTo(left - width * PageSwitcher.distance));
    await tester.pump(Ease.move);
    expect(find.byKey(const ValueKey('page home')), findsNothing);
    expect(x(tester, 'library'), left);

    // Back to an earlier tab: from the start side.
    await tester.pumpWidget(area('home', 0));
    await tester.pump(const Duration(milliseconds: 40));
    expect(x(tester, 'home'), lessThan(left));
    expect(x(tester, 'library'), greaterThan(left));
    await tester.pump(Ease.move);
    expect(x(tester, 'home'), left);
    expect(tester.takeException(), isNull);
  });

  testWidgets('right to left, a later tab comes in from the left', (tester) async {
    await tester.pumpWidget(area('home', 0, direction: TextDirection.rtl));
    await tester.pumpWidget(area('library', 3, direction: TextDirection.rtl));
    await tester.pump(const Duration(milliseconds: 40));
    expect(x(tester, 'library'), lessThan(left));
    expect(x(tester, 'home'), greaterThan(left));
    await tester.pump(Ease.move);
    expect(x(tester, 'library'), left);
  });

  testWidgets('the page leaving runs no animations and gives up focus', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(area('home', 0, focus: focus));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(TickerMode.valuesOf(tester.element(find.byKey(const ValueKey('page home')))).enabled, isTrue);

    await tester.pumpWidget(area('explore', 1, focus: focus));
    await tester.pump(const Duration(milliseconds: 40));
    expect(TickerMode.valuesOf(tester.element(find.byKey(const ValueKey('page home')))).enabled, isFalse);
    expect(TickerMode.valuesOf(tester.element(find.byKey(const ValueKey('page explore')))).enabled, isTrue);
    expect(focus.hasFocus, isFalse);
    await tester.pump(Ease.move);
  });

  testWidgets('pages that are not tabs, and wide windows, only fade', (tester) async {
    await tester.pumpWidget(area('home', 0));
    await tester.pumpWidget(area('channel:x', null));
    await tester.pump(const Duration(milliseconds: 40));
    expect(x(tester, 'home'), left);
    expect(x(tester, 'channel:x'), left);
    await tester.pump(Ease.move);

    await tester.pumpWidget(area('home', 0, slides: false));
    await tester.pump(Ease.move);
    await tester.pumpWidget(area('library', 3, slides: false));
    await tester.pump(const Duration(milliseconds: 40));
    expect(x(tester, 'home'), left);
    expect(x(tester, 'library'), left);
    await tester.pump(Ease.move);
    expect(find.byKey(const ValueKey('page home')), findsNothing);
  });

  testWidgets('with animations reduced the page changes at once', (tester) async {
    Motion.reduced = true;
    addTearDown(() => Motion.reduced = false);
    await tester.pumpWidget(area('home', 0));
    await tester.pumpWidget(area('library', 3));
    expect(find.byKey(const ValueKey('page home')), findsNothing);
    expect(x(tester, 'library'), left);
  });
}
