import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/ui/pages/settings_page.dart';
import 'package:lumtub/ui/pages/settings_sections.dart';
import 'package:lumtub/ui/pages/settings_subpages.dart';
import 'package:lumtub/ui/theme.dart';

void main() {
  late AppController controller;
  setUp(() => controller = AppController());

  Future<void> pump(WidgetTester tester, {double width = 1280}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Colors.red, Brightness.light),
      home: Scaffold(body: SettingsPage(controller: controller)),
    ));
    await tester.pump();
  }

  testWidgets('wide windows show the groups beside the chosen group', (tester) async {
    await pump(tester);
    for (final category in SettingsCategory.values) {
      expect(find.text(category.title), findsOneWidget);
    }
    await tester.tap(find.text(SettingsCategory.quality.title));
    await tester.pump();
    expect(find.text('Default quality'), findsOneWidget);
    expect(find.text('Enable hardware decoding'), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow windows open a group on its own page', (tester) async {
    await pump(tester, width: 600);
    expect(find.text('Default quality'), findsNothing);
    await tester.tap(find.text(SettingsCategory.play.title));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, SettingsCategory.play.title), findsOneWidget);
    expect(find.text('Playback order'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search finds rows across groups', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'hardware decod');
    await tester.pump();
    expect(find.text('Enable hardware decoding'), findsOneWidget);
    expect(find.text('Hardware decoding mode'), findsOneWidget);
    expect(find.text('Autoplay next'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '没有这种设置');
    await tester.pump();
    expect(find.text('No matching settings'), findsOneWidget);
  });

  testWidgets('the theme mode menu changes the theme mode', (tester) async {
    await pump(tester);
    // Theme mode is on the skins page.
    await tester.tap(find.text(SettingsCategory.style.title));
    await tester.pump();
    await tester.tap(find.text('Skins'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme mode'));
    await tester.pumpAndSettle();
    // The menu item's text sits under its ink; the tap still lands on the item.
    await tester.tap(find.text('Dark'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(controller.appearance.themeMode, ThemeMode.dark);
    // Settings are written a moment after the last change.
    await tester.pump(const Duration(seconds: 1));
  });

  Future<void> openRow(WidgetTester tester, SettingsCategory category, String row) async {
    await tester.tap(find.text(category.title));
    await tester.pump();
    await tester.scrollUntilVisible(find.text(row), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text(row));
    await tester.pumpAndSettle();
  }

  testWidgets('sub-pages open from their rows', (tester) async {
    await pump(tester);
    for (final (category, row, title, content) in [
      (SettingsCategory.play, 'Speed settings', 'Speed settings', 'Speed list'),
      (SettingsCategory.subtitles, 'Subtitle settings', 'Subtitle settings', 'First subtitle language'),
      (SettingsCategory.subtitles, 'Translation & AI', 'Translation & AI', 'Google Translate (free)'),
      (SettingsCategory.style, 'App font', 'App font', 'Microsoft YaHei'),
      (SettingsCategory.storage, 'Components', 'Components', 'Preparing components…'),
      (SettingsCategory.about, 'Error log', 'Logs', 'No logs yet'),
    ]) {
      await openRow(tester, category, row);
      expect(find.widgetWithText(AppBar, title), findsOneWidget, reason: row);
      expect(find.text(content), findsWidgets, reason: row);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a theme preset sets the colour and palette style in one tap', (tester) async {
    await pump(tester);
    // The presets sit with the color schemes on the skins page.
    await openRow(tester, SettingsCategory.style, 'Skins');
    expect(find.text('Classic red'), findsOneWidget);
    await tester.ensureVisible(find.text('Forest green'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forest green'));
    await tester.pumpAndSettle();
    final appearance = controller.appearance;
    expect((appearance.accentIndex, appearance.customAccent, appearance.pureBlack), (-1, 0xFF2E7D32, false));
    await tester.scrollUntilVisible(find.text('OLED black'), 60, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('OLED black'));
    await tester.pumpAndSettle();
    expect(controller.appearance.pureBlack, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the SponsorBlock row opens its categories and keeps its switch', (tester) async {
    await pump(tester);
    await openRow(tester, SettingsCategory.enhance, 'SponsorBlock');
    expect(find.text('Segment types to skip'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(8));
  });

  testWidgets('blocked channels can be removed', (tester) async {
    await controller.savePreferences(controller.preferences.copyWith(blockedChannels: const [ChannelRef('UC0123456789abcdefghijkl', '测试频道')]));
    await pump(tester);
    await openRow(tester, SettingsCategory.filters, 'Blocked channels');
    expect(find.text('测试频道'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(controller.preferences.blockedChannels, isEmpty);
    expect(find.textContaining('No channels blocked yet'), findsOneWidget);
  });

  testWidgets('account and about sit at the bottom without a subtitle', (tester) async {
    await pump(tester);
    expect(find.text(SettingsCategory.quality.subtitle), findsOneWidget);
    expect(find.text(SettingsCategory.about.subtitle), findsNothing);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('block lists open to their entries, each tickable', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller.preferences = controller.preferences.copyWith(blockGroups: true);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Colors.red, Brightness.light),
      home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => openBlockedGroups(context, controller), child: const Text('open')))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Falun Gong-linked (unproven)'), findsOneWidget);
    await tester.tap(find.text('Falun Gong-linked hosts and shows'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Channel names · '), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, '文昭谈古论今'));
    await tester.pump();
    expect(controller.preferences.allowedEntries.single, startsWith('falun-gong-linked-hosts-and-shows/'));
    expect(controller.preferences.blocksChannel('文昭談古論今'), isFalse);
    expect(controller.preferences.blocksChannel('江峰时刻'), isTrue);
    await tester.tap(find.text('Untick all'));
    await tester.pump();
    expect(controller.preferences.blocksChannel('江峰时刻'), isFalse);
    await tester.tap(find.text('Tick all'));
    await tester.pump();
    expect(controller.preferences.allowedEntries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every group holds settings and each setting sits in one group only', (tester) async {
    await pump(tester);
    final seen = <String, SettingsCategory>{};
    for (final category in SettingsCategory.values) {
      final entries = settingEntries(category, controller);
      expect(entries, isNotEmpty, reason: category.name);
      expect(entries.length, lessThanOrEqualTo(25), reason: '${category.name} is getting crowded again');
      for (final entry in entries) {
        if (entry.title.contains(RegExp(r'\d'))) continue;
        expect(seen[entry.title], isNull, reason: '${entry.title} is in ${seen[entry.title]?.name} and ${category.name}');
        seen[entry.title] = category;
      }
    }
  });
}
