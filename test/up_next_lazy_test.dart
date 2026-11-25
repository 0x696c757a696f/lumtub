import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/l10n/l10n.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/playing_list.dart';
import 'package:lumtub/translation.dart' show TranslationStyle;
import 'package:lumtub/ui/pages/watch_page.dart';
import 'package:lumtub/ui/translatable.dart';
import 'package:lumtub/ui/video_card.dart';

void main() {
  setUpAll(loadTranslations);

  testWidgets('the up next list builds only the tiles on screen', (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final videos = [for (var i = 0; i < 200; i++) VideoItem(id: 'video${i.toString().padLeft(6, '0')}', title: 'Video $i', channel: 'C', url: 'u$i', duration: 60)];
    final controller = AppController();
    controller.queue = videos;
    controller.playing = videos.first;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: upNextForTest(controller))));
    await tester.pump();
    final built = find.byType(CompactVideoTile).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(30));
  });

  testWidgets('a long playlist builds only the tiles on screen, the playing one marked in either order', (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final videos = [for (var i = 0; i < 3000; i++) VideoItem(id: 'video${i.toString().padLeft(6, '0')}', title: 'Video $i', channel: 'C', url: 'u$i', duration: 60)];
    final controller = AppController();
    controller.playingList = PlayingList(id: 'PL1', title: 'Long list', items: videos);
    controller.playing = videos[2];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: upNextForTest(controller))));
    await tester.pump();
    final built = find.byType(CompactVideoTile).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(30));
    expect(find.text('Playlist · 3/3000'), findsOneWidget);
    controller.playingList = controller.playingList!.withReversed(true);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: upNextForTest(controller))));
    await tester.pump();
    expect(find.text('Playlist · 2998/3000'), findsOneWidget);
    expect(find.text('Video 2999'), findsOneWidget, reason: 'the last video plays first');
  });

    testWidgets('a blurred translation is revealed by focus and toggled by Enter', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TranslationView(style: TranslationStyle.blur, child: Text('hello')))));
    bool blurred() => tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled;
    expect(blurred(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(blurred(), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(blurred(), isTrue);
  });
}
