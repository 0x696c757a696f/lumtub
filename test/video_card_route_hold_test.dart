import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/ui/video_card.dart';

const _item = VideoItem(id: 'dQw4w9WgXcQ', title: 'Video', channel: 'Channel', url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', duration: 212);

/// The hover preview's frames; the prefetch starts with them.
Finder get _preview => find.descendant(of: find.byType(VideoCard), matching: find.byType(AnimatedSwitcher));

Widget _card() => Scaffold(body: Center(child: SizedBox(width: 320, height: 300, child: VideoCard(item: _item, onOpen: () {}))));

Future<TestGesture> _hover(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(find.byType(VideoCard)));
  await tester.pump();
  return mouse;
}

PageRouteBuilder<void> _route(Duration duration, Widget page, {bool opaque = true}) => PageRouteBuilder<void>(
      opaque: opaque,
      transitionDuration: duration,
      pageBuilder: (context, _, __) => page,
      transitionsBuilder: (context, animation, _, child) => child,
    );

/// A page that comes and goes slowly, with a page under it moving along.
class _SlowRoute extends MaterialPageRoute<void> {
  _SlowRoute(Widget page) : super(builder: (_) => page);

  @override
  Duration get transitionDuration => const Duration(seconds: 2);
}

void main() {
  testWidgets('a card at rest starts its hover work after a moment', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _card()));
    await _hover(tester);
    await tester.pump(const Duration(milliseconds: 750));
    expect(_preview, findsOneWidget);
  });

  testWidgets('hover work waits while the card\'s route comes in', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: const SizedBox()));
    navigator.currentState!.push(_route(const Duration(seconds: 2), _card()));
    await tester.pump();
    await tester.pump();
    await _hover(tester);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_preview, findsNothing);
    // Once the route settles, the work starts a moment later.
    await tester.pumpAndSettle();
    expect(_preview, findsNothing);
    await tester.pump(const Duration(milliseconds: 750));
    expect(_preview, findsOneWidget);
  });

  testWidgets('hover work waits while the route over the card\'s goes away', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: _card()));
    final centre = tester.getCenter(find.byType(VideoCard));
    navigator.currentState!.push(_SlowRoute(const IgnorePointer(child: SizedBox.expand())));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: centre);
    // Going back: the pointer rests on the card while the page above leaves.
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await mouse.moveTo(centre + const Offset(1, 1));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_preview, findsNothing);
    await tester.pumpAndSettle();
    expect(_preview, findsNothing);
    await tester.pump(const Duration(milliseconds: 750));
    expect(_preview, findsOneWidget);
  });

  testWidgets('leaving the card while held starts nothing later', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: const SizedBox()));
    navigator.currentState!.push(_route(const Duration(seconds: 1), _card()));
    await tester.pump();
    await tester.pump();
    final mouse = await _hover(tester);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 3));
    expect(_preview, findsNothing);
  });
}
