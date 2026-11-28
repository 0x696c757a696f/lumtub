import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('a selected chip label is readable on its fill ($brightness)', (tester) async {
      final theme = buildAppTheme(Colors.blue, brightness);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
            body: Column(children: [
          FilterChip(label: const Text('on'), selected: true, onSelected: (_) {}),
          FilterChip(label: const Text('off'), onSelected: (_) {}),
        ])),
      ));
      Color? colorOf(String text) => tester
          .widget<DefaultTextStyle>(
              find.ancestor(of: find.text(text), matching: find.byType(DefaultTextStyle)).first)
          .style
          .color;
      expect(colorOf('on'), theme.colorScheme.surface);
      expect(colorOf('off'), theme.colorScheme.onSurface);
    });
  }
}
