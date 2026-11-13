import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/motion.dart';
import 'package:lumtub/ui/theme_cross_fade.dart';

void main() {
  tearDown(() => Motion.reduced = false);

  Future<void Function()> pumpApp(WidgetTester tester, {bool Function()? instant, VoidCallback? onTap}) async {
    var dark = false;
    late StateSetter update;
    await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
      update = setState;
      return MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => ThemeCrossFade(instant: instant, child: child!),
        home: Scaffold(body: Center(child: TextButton(onPressed: onTap, child: const Text('Tap')))),
      );
    }));
    return () => update(() => dark = !dark);
  }

  bool fading(WidgetTester tester) => ThemeCrossFade.fadingAt(tester.element(find.byType(ThemeCrossFade)));

  testWidgets('the first frame shows the theme without a fade', (tester) async {
    await pumpApp(tester);
    expect(fading(tester), isFalse);
  });

  testWidgets('a theme change fades the old frame out and then drops it', (tester) async {
    final toggle = await pumpApp(tester);
    toggle();
    await tester.pump();
    expect(fading(tester), isTrue);
    // The new theme is in place at once, under the fading picture.
    expect(Theme.of(tester.element(find.byType(Scaffold))).brightness, Brightness.dark);
    await tester.pump(const Duration(milliseconds: 120));
    expect(fading(tester), isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    expect(fading(tester), isFalse);
  });

  testWidgets('pointer events reach the new frame during the fade', (tester) async {
    var taps = 0;
    final toggle = await pumpApp(tester, onTap: () => taps++);
    toggle();
    await tester.pump();
    expect(fading(tester), isTrue);
    await tester.tap(find.text('Tap'));
    expect(taps, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion switches at once', (tester) async {
    Motion.reduced = true;
    final toggle = await pumpApp(tester);
    toggle();
    await tester.pump();
    expect(fading(tester), isFalse);
  });

  testWidgets('switches at once while told to, as while a video shows', (tester) async {
    var video = true;
    final toggle = await pumpApp(tester, instant: () => video);
    toggle();
    await tester.pump();
    expect(fading(tester), isFalse);
    video = false;
    toggle();
    await tester.pump();
    expect(fading(tester), isTrue);
    await tester.pumpAndSettle();
    expect(fading(tester), isFalse);
  });

  testWidgets('a change with motion reduced ends a fade still running', (tester) async {
    final toggle = await pumpApp(tester);
    toggle();
    await tester.pump();
    expect(fading(tester), isTrue);
    Motion.reduced = true;
    toggle();
    await tester.pump();
    expect(fading(tester), isFalse);
  });
}
