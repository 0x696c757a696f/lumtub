import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('a selected chip label is readable on its fill ($brightness)', (tester) async {
      final theme = buildAppTheme(Colors.blue, brightness);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(body: Column(children: [
          FilterChip(label: const Text('on'), selected: true, onSelected: (_) {}),
          FilterChip(label: const Text('off'), selected: false, onSelected: (_) {}),
        ])),
      ));
      Color? colorOf(String text) => tester.widget<DefaultTextStyle>(find.ancestor(of: find.text(text), matching: find.byType(DefaultTextStyle)).first).style.color;
      expect(colorOf('on'), theme.colorScheme.surface);
      expect(colorOf('off'), theme.colorScheme.onSurface);
    });
  }
}
