import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/fill_icon.dart';
import 'package:lumtub/ui/motion.dart';

const _outline = IconData(0xe0e6, fontFamily: 'Phosphor');
const _fill = IconData(0xe0e6, fontFamily: 'Phosphor Fill');

Widget _bar(int selected) => MaterialApp(
      home: Scaffold(
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          destinations: [
            for (var i = 0; i < 2; i++)
              NavigationDestination(icon: FillIcon(_outline, _fill, selected: i == selected), selectedIcon: FillIcon(_outline, _fill, selected: i == selected), label: '$i'),
          ],
        ),
      ),
    );

void main() {
  tearDown(() => Motion.reduced = false);

  testWidgets('a newly selected icon cross-fades to filled and pops, keeping its state', (tester) async {
    await tester.pumpWidget(_bar(0));
    await tester.pumpAndSettle();
    final second = tester.state(find.byType(FillIcon).at(1));
    expect(find.byIcon(_fill), findsOneWidget);

    await tester.pumpWidget(_bar(1));
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.state(find.byType(FillIcon).at(1)), same(second), reason: 'the same state animates across the icon swap');
    expect(find.descendant(of: find.byType(FillIcon).at(1), matching: find.byType(Opacity)), findsNWidgets(2));
    expect(find.descendant(of: find.byType(FillIcon).at(1), matching: find.byType(Transform)), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(FillIcon).at(1), matching: find.byIcon(_fill)), findsOneWidget);
    expect(find.descendant(of: find.byType(FillIcon).at(0), matching: find.byIcon(_outline)), findsOneWidget);
    expect(find.descendant(of: find.byType(FillIcon).at(1), matching: find.byType(Opacity)), findsNothing);
  });

  testWidgets('with animations reduced the icon swaps at once', (tester) async {
    Motion.reduced = true;
    await tester.pumpWidget(_bar(0));
    await tester.pumpWidget(_bar(1));
    await tester.pump();
    expect(find.descendant(of: find.byType(FillIcon).at(1), matching: find.byIcon(_fill)), findsOneWidget);
  });
}
