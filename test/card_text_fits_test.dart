import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/appearance_settings.dart';
import 'package:lumtub/skins/jsonc.dart';
import 'package:lumtub/skins/skin.dart';
import 'package:lumtub/ui/theme.dart';
import 'package:lumtub/ui/video_card.dart';
import 'package:lumtub/youtube_related.dart';

/// Every card's title keeps room for its two lines, with a reason line
/// under it, on every built-in skin, compact or not, and at larger text.
void main() {
  final dirs = Directory('skins').listSync().whereType<Directory>().where((d) => File('${d.path}/skin.jsonc').existsSync() && !d.path.endsWith('template')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final skins = <String, Skin?>{'none': null, for (final d in dirs) d.path: Skin.parse(decodeJsonc(File('${d.path}/skin.jsonc').readAsStringSync()), folder: d.path, builtIn: true)};
  final items = [
    for (var i = 0; i < 8; i++)
      videoFromCore({'id': 'aaaaaaaaaa$i', 'title': '一个很长很长的视频标题，长到一定要折成两行才能放得下，还要更长一点 $i', 'channel': 'Channel $i', 'live': false, 'viewCount': 1234, 'age': '3 days ago'}),
  ];

  for (final MapEntry(key: name, value: skin) in skins.entries) {
    for (final (compact, scale, width) in [for (final c in [false, true]) for (final s in [1.0, 1.3]) for (final w in [1200.0, 400.0]) (c, s, w)]) {
      testWidgets('$name${compact ? ' compact' : ''} at text ×$scale, ${width.round()} wide, leaves the title its two lines', (tester) async {
        compactCards = compact;
        addTearDown(() => compactCards = false);
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final side = skin?.forBrightness(Brightness.dark);
        final theme = buildAppTheme(const Color(0xFF3366FF), side?.brightness ?? Brightness.dark, skin: side);
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: CustomScrollView(slivers: [
              SliverVideoGrid(items: items, onOpen: (_) {}, reasons: {for (final item in items) item.id: '你订阅了这个频道，还看过它的很多视频'}),
            ])),
          ),
        ));
        await tester.pump();
        var checked = 0;
        for (final item in items.take(width > 1000 ? 4 : 1)) {
          final p = tester.renderObject<RenderParagraph>(find.text(item.title));
          final needs = p.getMinIntrinsicHeight(p.size.width);
          expect(p.size.height, greaterThanOrEqualTo(needs - 0.5), reason: '${item.title} needs $needs, has ${p.size.height}');
          checked++;
        }
        expect(checked, width > 1000 ? 4 : 1);
      });
    }
  }
}
