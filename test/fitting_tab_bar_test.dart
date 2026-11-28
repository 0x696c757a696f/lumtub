import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/common.dart';
import 'package:lumtub/ui/fitting_tab_bar.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpTabs(WidgetTester tester, List<String> labels, double width) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                    width: width,
                    child: DefaultTabController(
                      length: labels.length,
                      child: Builder(
                          builder: (context) => FittingTabBar(
                              controller: DefaultTabController.of(context), labels: labels)),
                    ))))));
  }

  testWidgets('tabs share the width when every label fits its share', (tester) async {
    await pumpTabs(tester, ['A', 'B', 'C'], 300);
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isFalse);
  });

  testWidgets('tabs tighten their padding before they scroll', (tester) async {
    // Test letters are 14 wide: 32 letters, 448 in all.
    await pumpTabs(tester, ['Chatxxx', 'Upnextxx', 'Comments', 'Subtitle'], 500);
    final bar = tester.widget<TabBar>(find.byType(TabBar));
    expect(bar.labelPadding, const EdgeInsets.symmetric(horizontal: 6));
    final last = tester.getRect(find.text('Subtitle'));
    expect(last.right, lessThanOrEqualTo(500));
  });

  testWidgets('the buttons go under the title when they leave it no room', (tester) async {
    Future<Rect> buttons(double width) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: width,
                      child: HeadingLine(children: [
                        const Text('Title'),
                        const SizedBox(width: 400, height: 20, key: Key('buttons')),
                      ]))))));
      expect(tester.takeException(), isNull);
      return tester.getRect(find.byKey(const Key('buttons')));
    }

    expect((await buttons(800)).top, 0);
    expect((await buttons(500)).top, greaterThan(0));
  });
}
