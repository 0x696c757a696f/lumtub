import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/skins/jsonc.dart';
import 'package:lumtub/skins/skin.dart';
import 'package:lumtub/ui/skin_chrome.dart';
import 'package:lumtub/window_frame.dart';

void main() {
  final calls = <Map<Object?, Object?>>[];
  late Skin skin;

  setUp(() {
    calls.clear();
    WindowFrame.debugCaptions = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel(WindowFrame.channelName), (call) async {
      if (call.method == 'setCaption') calls.add(call.arguments as Map<Object?, Object?>);
      if (call.method == 'state') return {'maximized': false, 'active': true};
      return null;
    });
    skin = Skin.parse(decodeJsonc(File('skins/desktop/skin.jsonc').readAsStringSync()), folder: 'skins/desktop', builtIn: true).forBrightness(Brightness.light);
  });

  tearDown(() => WindowFrame.debugCaptions = false);

  List<double> rect(Object? value) => [for (final n in value as List<Object?>) (n as num).toDouble()];

  testWidgets('the caption follows the window buttons when the layout moves without a rebuild', (tester) async {
    final menus = [SkinMenu('Lumtub', [SkinMenuEntry('Quit', () {})], bold: true), SkinMenu('File', [SkinMenuEntry('Quit', () {})])];
    final menuBar = skin.menuBar!;
    // One widget, never rebuilt: only the space around it changes, as when
    // the window's frame or size changes at start-up.
    final titleBar = SkinTitleBarView(bar: skin.titleBar!, title: 'Lumtub', menuBar: menuBar, menus: SkinMenuBarView(bar: menuBar, menus: menus, embedded: true));
    final width = ValueNotifier<double>(500);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder(valueListenable: width, builder: (context, w, child) => SizedBox(width: w, child: child), child: titleBar),
        ),
      ),
    ));
    await tester.pump();
    expect(rect(calls.last['maximize'])[2], lessThanOrEqualTo(500));

    width.value = 760;
    await tester.pump();
    await tester.pump();
    final last = calls.last;
    expect(rect(last['maximize'])[2], greaterThan(700));
    final interactive = [for (final r in last['interactive'] as List<Object?>) rect(r)];
    expect(interactive.any((r) => r[2] > 700), isTrue, reason: 'close button');
    final menusRect = SkinMenuBarView.menusAbove.value!;
    expect(interactive.any((r) => r[0] == menusRect.left && r[2] == menusRect.right), isTrue, reason: 'menus stay clickable');
  });

  testWidgets('a title bar going away leaves the caption of the one that replaced it', (tester) async {
    Widget app(Key key) => MaterialApp(home: Material(child: Column(children: [SkinTitleBarView(key: key, bar: skin.titleBar!, title: 'Lumtub'), const Expanded(child: SizedBox())])));
    await tester.pumpWidget(app(const ValueKey(1)));
    await tester.pump();
    await tester.pumpWidget(app(const ValueKey(2)));
    await tester.pump();
    await tester.pump();
    expect(calls.last['height'], greaterThan(0));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(calls.last['height'], 0);
  });
}
