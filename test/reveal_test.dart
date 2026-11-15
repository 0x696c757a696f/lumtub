import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/motion.dart';
import 'package:lumtub/ui/page_switcher.dart';
import 'package:lumtub/ui/reveal.dart';

/// A page that loads: a spinner, then its content.
Widget _page({required bool loaded}) => MaterialApp(
      home: Scaffold(
        body: loaded ? const Reveal(child: Text('content')) : const Center(child: CircularProgressIndicator()),
      ),
    );

double _opacity(WidgetTester tester, Finder finder) => tester.widget<FadeTransition>(find.ancestor(of: finder, matching: find.byType(FadeTransition)).first).opacity.value;

void main() {
  tearDown(() => Motion.reduced = false);

  testWidgets('content that replaces a spinner fades and grows in once', (tester) async {
    await tester.pumpWidget(_page(loaded: false));
    await tester.pumpWidget(_page(loaded: true));
    final content = find.text('content');
    expect(_opacity(tester, content), 0);
    expect(tester.getSize(content), isNotNull);
    await tester.pump(const Duration(milliseconds: 100));
    final halfway = _opacity(tester, content);
    expect(halfway, greaterThan(0.5));
    expect(halfway, lessThan(1));
    final scale = tester.widget<ScaleTransition>(find.ancestor(of: content, matching: find.byType(ScaleTransition)).first).scale.value;
    expect(scale, greaterThan(Reveal.scale));
    expect(scale, lessThan(1));
    await tester.pump(Ease.fade);
    expect(_opacity(tester, content), 1);

    // Building again does not bring it in again.
    await tester.pumpWidget(_page(loaded: true));
    expect(_opacity(tester, content), 1);
  });

  testWidgets('is simply there with animations reduced, or when not enabled', (tester) async {
    Motion.reduced = true;
    await tester.pumpWidget(_page(loaded: true));
    expect(_opacity(tester, find.text('content')), 1);
    Motion.reduced = false;
    await tester.pumpWidget(const MaterialApp(home: Reveal(enabled: false, child: Text('later'))));
    expect(_opacity(tester, find.text('later')), 1);
  });

  testWidgets('content that comes with its page waits for no entrance of its own', (tester) async {
    Widget area(String page) => MaterialApp(home: PageSwitcher(pageKey: page, child: Reveal(child: Text(page))));
    await tester.pumpWidget(area('home'));
    await tester.pumpWidget(area('explore'));
    await tester.pump();
    final reveal = find.ancestor(of: find.text('explore'), matching: find.byType(Reveal));
    final fade = find.descendant(of: reveal, matching: find.byType(FadeTransition)).first;
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('a sliver of results fades in as one', (tester) async {
    Widget list(bool loaded) => MaterialApp(
          home: CustomScrollView(slivers: [
            if (loaded) SliverReveal(sliver: SliverList.list(children: const [Text('a'), Text('b')])),
          ]),
        );
    await tester.pumpWidget(list(false));
    await tester.pumpWidget(list(true));
    SliverFadeTransition fade() => tester.widget<SliverFadeTransition>(find.byType(SliverFadeTransition));
    expect(fade().opacity.value, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(fade().opacity.value, inExclusiveRange(0, 1));
    await tester.pump(Ease.fade);
    expect(fade().opacity.value, 1);
  });
}
