import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/app/app_controller.dart';
import 'package:ytplus/ui/pages/settings_page.dart';
import 'package:ytplus/ui/pages/settings_sections.dart';
import 'package:ytplus/ui/theme.dart';

void main() {
  late AppController controller;
  setUp(() => controller = AppController());

  Future<void> pump(WidgetTester tester, {double width = 1280}) async {
    tester.view.physicalSize = Size(width, 900);
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
    await tester.tap(find.text(SettingsCategory.video.title));
    await tester.pump();
    expect(find.text('默认画质'), findsOneWidget);
    expect(find.text('开启硬解'), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow windows open a group on its own page', (tester) async {
    await pump(tester, width: 600);
    expect(find.text('默认画质'), findsNothing);
    await tester.tap(find.text(SettingsCategory.play.title));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, SettingsCategory.play.title), findsOneWidget);
    expect(find.text('自动连播'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search finds rows across groups', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, '硬解');
    await tester.pump();
    expect(find.text('开启硬解'), findsOneWidget);
    expect(find.text('硬解模式'), findsOneWidget);
    expect(find.text('自动连播'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '没有这种设置');
    await tester.pump();
    expect(find.text('没有找到相关设置'), findsOneWidget);
  });

  testWidgets('a choice dialog changes the theme mode', (tester) async {
    await pump(tester);
    await tester.tap(find.text(SettingsCategory.style.title));
    await tester.pump();
    await tester.tap(find.text('主题模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(controller.appearance.themeMode, ThemeMode.dark);
  });
}
