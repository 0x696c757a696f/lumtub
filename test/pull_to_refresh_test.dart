import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/pull_to_refresh.dart';

void main() {
  Widget page({required bool enabled, required Future<void> Function() onRefresh}) => MaterialApp(
        home: Scaffold(
          body: PullToRefresh(
            enabled: enabled,
            onRefresh: onRefresh,
            child: CustomScrollView(slivers: [
              SliverList.builder(itemCount: 60, itemBuilder: (context, i) => SizedBox(height: 50, child: Text('row $i'))),
            ]),
          ),
        ),
      );

  testWidgets('pulling down loads the page again', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(page(enabled: true, onRefresh: () async => refreshed++));
    await tester.fling(find.text('row 0'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  });

  testWidgets('a page with nothing to load is not refreshed by pulling', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(page(enabled: false, onRefresh: () async => refreshed++));
    await tester.fling(find.text('row 0'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(refreshed, 0);
    expect(PullToRefresh.refresh(), isFalse);
  });

  testWidgets('pressed again: to the top first, then from the top a refresh', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(page(enabled: true, onRefresh: () async => refreshed++));
    final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    position.jumpTo(1200);
    await tester.pump();
    expect(PullToRefresh.topOrRefresh(refresh: true), isTrue);
    await tester.pumpAndSettle();
    expect(position.pixels, 0);
    expect(refreshed, 0);
    expect(PullToRefresh.topOrRefresh(refresh: true), isTrue);
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  });

  testWidgets('F5 from further down goes to the top and refreshes', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(page(enabled: true, onRefresh: () async => refreshed++));
    final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    position.jumpTo(800);
    await tester.pump();
    expect(PullToRefresh.refresh(), isTrue);
    await tester.pumpAndSettle();
    expect(position.pixels, 0);
    expect(refreshed, 1);
  });
}
