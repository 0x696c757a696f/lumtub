import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/app_icons.dart';
import 'package:lumtub/ui/common.dart';
import 'package:lumtub/ui/motion.dart';
import 'package:lumtub/ui/skeleton.dart';
import 'package:lumtub/ui/theme.dart';
import 'package:lumtub/ui/video_card.dart';

void main() {
  tearDown(() => Motion.reduced = false);

  Future<void> pump(WidgetTester tester, Widget body) => tester.pumpWidget(MaterialApp(theme: buildAppTheme(Colors.red, Brightness.light), home: Scaffold(body: body)));

  FadeTransition fadeAbove(WidgetTester tester, Finder finder) => tester.widget<FadeTransition>(find.ancestor(of: finder, matching: find.byType(FadeTransition)).first);

  testWidgets('the skeleton grid shows only once loading takes 400 ms', (tester) async {
    await pump(tester, const CustomScrollView(slivers: [SliverSkeletonGrid()]));
    expect(find.byType(Skeleton), findsNothing);
    await tester.pump(const Duration(milliseconds: 399));
    expect(find.byType(Skeleton), findsNothing);
    await tester.pump(const Duration(milliseconds: 2));
    expect(find.byType(Skeleton), findsOneWidget);
    // It comes in with a fade and a scale.
    final fade = fadeAbove(tester, find.byType(Skeleton));
    expect(fade.opacity.value, lessThan(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(fade.opacity.value, 1);
  });

  testWidgets('a load that ends sooner never shows the skeleton', (tester) async {
    await pump(tester, const CustomScrollView(slivers: [SliverSkeletonGrid()]));
    await tester.pump(const Duration(milliseconds: 300));
    await pump(tester, const CustomScrollView(slivers: [SliverToBoxAdapter(child: Text('Loaded'))]));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(Skeleton), findsNothing);
    expect(find.text('Loaded'), findsOneWidget);
  });

  testWidgets('with motion reduced the skeleton still waits, then shows at once', (tester) async {
    Motion.reduced = true;
    await pump(tester, const DelayedReveal(child: Skeleton(child: SkeletonBox())));
    expect(find.byType(Skeleton), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(fadeAbove(tester, find.byType(Skeleton)).opacity.value, 1);
  });

  testWidgets('an empty state comes in once with a fade and a scale', (tester) async {
    await pump(tester, StatusView(icon: AppIcons.x, title: 'Nothing here'));
    final scale = tester.widget<ScaleTransition>(find.ancestor(of: find.text('Nothing here'), matching: find.byType(ScaleTransition)).first);
    expect(scale.scale.value, closeTo(0.92, 0.001));
    await tester.pumpAndSettle();
    expect(scale.scale.value, 1);
    // Built again with other text, it does not come in a second time.
    await pump(tester, StatusView(icon: AppIcons.x, title: 'Still nothing'));
    expect(tester.widget<ScaleTransition>(find.ancestor(of: find.text('Still nothing'), matching: find.byType(ScaleTransition)).first).scale.value, 1);
  });

  testWidgets('with motion reduced an empty state is simply there', (tester) async {
    Motion.reduced = true;
    await pump(tester, StatusView(icon: AppIcons.x, title: 'Nothing here'));
    expect(fadeAbove(tester, find.text('Nothing here')).opacity.value, 1);
  });
}
