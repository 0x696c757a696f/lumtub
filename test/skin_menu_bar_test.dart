import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/skins/jsonc.dart';
import 'package:lumtub/skins/skin.dart';
import 'package:lumtub/ui/skin_chrome.dart';

void main() {
  testWidgets('a menu bar that replaces another keeps its menus clickable in the title bar', (tester) async {
    final skin = Skin.parse(decodeJsonc(File('skins/desktop/skin.jsonc').readAsStringSync()), folder: 'skins/desktop', builtIn: true);
    final bar = skin.forBrightness(Brightness.light).menuBar!;
    final menus = [SkinMenu('File', [SkinMenuEntry('Quit', () {})])];
    Widget view(Key key) => MaterialApp(home: Material(child: Column(children: [SkinMenuBarView(key: key, bar: bar, menus: menus, embedded: true)])));

    await tester.pumpWidget(view(const ValueKey(1)));
    await tester.pump();
    expect(SkinMenuBarView.menusAbove.value, isNotNull);

    // As at start-up, when the window's frame is built a second time.
    await tester.pumpWidget(view(const ValueKey(2)));
    await tester.pump();
    await tester.pump();
    expect(SkinMenuBarView.menusAbove.value, isNotNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(SkinMenuBarView.menusAbove.value, isNull);
  });
}
