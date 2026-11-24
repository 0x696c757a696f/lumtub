import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/edge_swipe_back.dart';

void main() {
  Future<int> swipe(WidgetTester tester, {required Offset from, required double by, bool canGoBack = true}) async {
    var backs = 0;
    await tester.pumpWidget(MaterialApp(
      home: EdgeSwipeBack(enabled: true, canGoBack: () => canGoBack, onBack: () => backs++, child: const SizedBox.expand()),
    ));
    // Slow, so only the distance decides.
    await tester.timedDragFrom(from, Offset(by, 0), const Duration(seconds: 1));
    await tester.pumpAndSettle();
    return backs;
  }

  testWidgets('a long swipe from the left edge goes back', (tester) async {
    expect(await swipe(tester, from: const Offset(5, 300), by: 500), 1);
  });

  testWidgets('a short or mid-screen swipe does not', (tester) async {
    expect(await swipe(tester, from: const Offset(5, 300), by: 40), 0);
    expect(await swipe(tester, from: const Offset(200, 300), by: 500), 0);
  });

  testWidgets('nothing to go back to: nothing happens', (tester) async {
    expect(await swipe(tester, from: const Offset(5, 300), by: 500, canGoBack: false), 0);
  });
}
