import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/appearance_settings.dart';
import 'package:lumtub/main.dart';
import 'package:lumtub/ui/app_shell.dart';

/// Without a skin the pages sit on the theme's own page colour, light or
/// dark, not on whatever the window shows under Flutter.
void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('the default look paints its ${mode.name} page', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = AppController(appearance: AppearanceSettings(themeMode: mode));
      await tester.pumpWidget(LumtubApp(controller: controller));
      await tester.pump();
      final scaffold = find.descendant(of: find.byType(AppShell), matching: find.byType(Scaffold)).first;
      final theme = Theme.of(tester.element(scaffold));
      final page = tester.widget<Scaffold>(scaffold).backgroundColor ?? theme.scaffoldBackgroundColor;
      expect(page.a, 1);
      expect(page, theme.colorScheme.surface);
      expect(theme.brightness, mode == ThemeMode.light ? Brightness.light : Brightness.dark);
    });
  }
}
