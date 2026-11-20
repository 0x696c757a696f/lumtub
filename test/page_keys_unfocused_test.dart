import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/app/video_list_loader.dart';
import 'package:lumtub/main.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/video_repository.dart';

void main() {
  // On a desktop nothing is focused when the app starts, nor after a click
  // on a page button: the focus rests on the page's route, above the
  // window's keys. Page Down has to turn the page all the same.
  testWidgets('Page Down turns the page with no control focused', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = AppController();
    await tester.pumpWidget(LumtubApp(controller: controller));
    await tester.pump();
    final videos = [for (var i = 0; i < 120; i++) VideoItem(id: 'abcdefg${'$i'.padLeft(4, '0')}', title: 'Video $i', channel: 'X', url: 'https://youtu.be/x')];
    controller
      ..ready = true
      ..channel = const ChannelRef('UCx', 'X')
      ..channelVideos = (VideoListLoader(() => Listing(() => Stream.fromIterable([for (final v in videos) jsonEncode(v.toJson())])), pageSize: 120)..loadMore());
    controller.navigate(PageMode.channel);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
    final list = tester.state<ScrollableState>(find.descendant(of: find.byKey(const PageStorageKey('list')), matching: find.byType(Scrollable)).first).position;
    expect(list.pixels, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(list.pixels, greaterThan(0));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
