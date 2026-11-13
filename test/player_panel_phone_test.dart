import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/common.dart';
import 'package:lumtub/ui/player_panel.dart';

void main() {
  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => showPlayerPanel(context, title: 'Panel', builder: (context) => const Text('inside')), child: const Text('open')))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('inside'), findsOneWidget);
  }

  testWidgets('a phone held upright opens player panels as a sheet under the player', (tester) async {
    debugTouchFirst = true;
    addTearDown(() => debugTouchFirst = null);
    await open(tester, const Size(412, 900));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.getTopLeft(find.text('Panel')).dy, greaterThan(412 * 9 / 16));
  });

  testWidgets('sideways or on a computer they slide in from the right', (tester) async {
    debugTouchFirst = true;
    addTearDown(() => debugTouchFirst = null);
    await open(tester, const Size(900, 412));
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.getTopLeft(find.text('Panel')).dx, greaterThan(400));
  });
}
