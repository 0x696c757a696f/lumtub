import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/player_controls.dart';
import 'package:lumtub/ui/player_panel.dart';

void main() {
  testWidgets('a collapsed list shows the chosen one until opened', (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PanelChoices<int>(label: 'Audio track', value: 2, values: const [(1, 'One'), (2, 'Two'), (3, 'Three')], collapsed: true, onSelected: (v) => picked = '$v'),
      ),
    ));
    expect(find.text('Two'), findsOneWidget);
    expect(find.text('One'), findsNothing);
    await tester.tap(find.byType(ActionChip));
    await tester.pump();
    expect(find.text('One'), findsOneWidget);
    await tester.tap(find.text('Three'));
    expect(picked, '3');
    await tester.tap(find.byType(ActionChip));
    await tester.pump();
    expect(find.text('Three'), findsNothing);
  });

  test('names yt-dlp audio formats plainly', () {
    expect(trackLabel('2', '251-4 - audio only (English (US) original (default), medium)', 'en'), 'English (US) original (default), medium · Opus');
    expect(trackLabel('3', '140-drc - audio only (Hindi, medium)', null), startsWith('Hindi, medium · AAC · '));
    expect(trackLabel('4', 'Commentary', 'en'), 'Commentary · en');
    expect(trackLabel('5', null, null), contains('5'));
  });
}
