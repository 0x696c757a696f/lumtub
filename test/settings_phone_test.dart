import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/ui/pages/settings_sections.dart';
import 'package:lumtub/ui/theme.dart';

/// Every settings group lays out on the narrowest phones, at large text,
/// from top to bottom: a row that doesn't fit shows as a grey block on a
/// phone.
void main() {
  for (final (width, scale) in [(320.0, 1.3), (360.0, 1.0), (390.0, 1.3)]) {
    for (final category in SettingsCategory.values) {
      testWidgets('${category.name} fits $width wide at text ×$scale', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = AppController();
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(Colors.red, Brightness.light),
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          // The group's rows as a phone shows them, on a page of their own.
          home: Scaffold(body: Builder(builder: (context) {
            final entries = settingEntries(category, controller);
            return ListView.builder(itemCount: entries.length, itemBuilder: (context, i) => entries[i].builder(context));
          })),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final list = find.byType(Scrollable).first;
        for (var i = 0; i < 60; i++) {
          final position = tester.state<ScrollableState>(list).position;
          if (position.pixels >= position.maxScrollExtent) break;
          position.jumpTo((position.pixels + 500).clamp(0, position.maxScrollExtent));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
