import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/main.dart';
import 'package:lumtub/ui/animated_visibility.dart';
import 'package:lumtub/ui/motion.dart';
import 'package:lumtub/ui/page_switcher.dart';

void main() {
  Future<AppController> pumpApp(WidgetTester tester, Size size, {Brightness? platformBrightness}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    if (platformBrightness != null) tester.platformDispatcher.platformBrightnessTestValue = platformBrightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final controller = AppController();
    await tester.pumpWidget(LumtubApp(controller: controller));
    await tester.pump();
    return controller;
  }

  testWidgets('wide windows show the navigation rail and search box', (tester) async {
    await pumpApp(tester, const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Lumtub'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<PageSwitcher>(find.byType(PageSwitcher)).slides, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow windows switch to a bottom navigation bar', (tester) async {
    await pumpApp(tester, const Size(600, 800));
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    // A phone's tabs slide into each other.
    expect(tester.widget<PageSwitcher>(find.byType(PageSwitcher)).slides, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in the dark theme without layout errors', (tester) async {
    await pumpApp(tester, const Size(1280, 800), platformBrightness: Brightness.dark);
    final context = tester.element(find.byType(NavigationRail));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  group('crossing the breakpoint', () {
    double width(WidgetTester tester, Finder finder) => tester.getSize(finder).width;

    testWidgets('the rail slides away as the bottom bar comes in, and back', (tester) async {
      await pumpApp(tester, const Size(1280, 800));
      final rail = find.ancestor(of: find.byType(NavigationRail), matching: find.byType(AnimatedVisibility));
      final full = width(tester, rail);
      expect(full, greaterThan(0));

      tester.view.physicalSize = const Size(600, 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Halfway: both are there, the rail narrower, the bar not yet tall.
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(width(tester, rail), inExclusiveRange(0, full));
      expect(tester.getSize(find.byType(NavigationBar)).height, 64);
      final bar = find.ancestor(of: find.byType(NavigationBar), matching: find.byType(AnimatedVisibility));
      expect(tester.getSize(bar).height, inExclusiveRange(0, 64));
      expect(tester.takeException(), isNull);

      await tester.pump(AnimatedVisibility.duration);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.getSize(bar).height, 64);

      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(AnimatedVisibility.duration);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(width(tester, rail), full);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bar on its way out cannot be pressed or focused', (tester) async {
      await pumpApp(tester, const Size(1280, 800));
      tester.view.physicalSize = const Size(600, 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      Iterable<T> around<T extends Widget>(Type bar) => tester.widgetList<T>(find.ancestor(of: find.byType(bar), matching: find.byType(T)));
      expect(around<ExcludeFocus>(NavigationRail).any((e) => e.excluding), isTrue);
      expect(around<ExcludeSemantics>(NavigationRail).any((e) => e.excluding), isTrue);
      expect(around<IgnorePointer>(NavigationRail).any((e) => e.ignoring), isTrue);
      // The one coming in can be used already.
      expect(around<ExcludeFocus>(NavigationBar).any((e) => e.excluding), isFalse);
      await tester.pump(AnimatedVisibility.duration);
    });

    testWidgets('with animations reduced the bars swap at once', (tester) async {
      await pumpApp(tester, const Size(1280, 800));
      // Set after the app has applied its own setting.
      Motion.reduced = true;
      addTearDown(() => Motion.reduced = false);
      tester.view.physicalSize = const Size(600, 800);
      await tester.pump();
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a change that is not navigation leaves the rail alone, while the rest follows it', (tester) async {
    final controller = await pumpApp(tester, const Size(1280, 800));
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    final incognito = find.byWidgetPredicate((w) => w is IconButton && w.isSelected == true);
    expect(incognito, findsNothing);

    controller.status = 'Fetching the player';
    controller.setIncognito(true);
    await tester.pump();
    expect(identical(tester.widget(find.byType(NavigationRail)), rail), isTrue);
    // The top bar, the page and the status line did update.
    expect(incognito, findsOneWidget);
    expect(find.textContaining('Fetching the player'), findsNWidgets(2));

    controller.navigate(PageMode.history);
    await tester.pump();
    final moved = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(identical(moved, rail), isFalse);
    expect(moved.selectedIndex, 3);
    expect(tester.takeException(), isNull);
  });
}
