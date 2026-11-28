import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/player_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit_video/media_kit_video.dart' show VideoObstructionAvoider;

import 'tooltip_finder.dart';

void main() {
  const rtl = {'ar', 'fa', 'he', 'ur', 'ps', 'sd', 'ug', 'yi', 'dv', 'ckb'};

  Future<void> pumpHeader(WidgetTester tester, {required double width, required Map<String, String> words, TextDirection direction = TextDirection.ltr}) async {
    String w(String key) => words[key] ?? key;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: PanelHeader(
                title: w('Subtitles'),
                closes: true,
                actions: [
                  PanelAction(icon: Icons.list, label: w('Subtitle list'), onPressed: (_) {}),
                  PanelAction(icon: Icons.tune, label: w('Subtitle settings'), onPressed: (_) {}),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('the title stays on one line in every language and width', (tester) async {
    final files = Directory('assets/l10n').listSync().whereType<File>().where((file) => file.path.endsWith('.json')).toList();
    expect(files.length, greaterThan(70));
    for (final file in files) {
      final language = file.uri.pathSegments.last.replaceAll('.json', '');
      final words = (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>().map((key, value) => MapEntry(key, '$value'));
      for (final width in [536.0, 420.0, 340.0, 260.0]) {
        await pumpHeader(tester, width: width, words: words, direction: rtl.contains(language) ? TextDirection.rtl : TextDirection.ltr);
        expect(tester.takeException(), isNull, reason: '$language at $width');
        final title = tester.getRect(find.text(words['Subtitles'] ?? 'Subtitles'));
        final line = tester.getRect(find.byType(PanelHeader));
        // One line of titleMedium, never a column of letters.
        expect(title.height, lessThan(40), reason: '$language at $width');
        final text = words['Subtitles'] ?? 'Subtitles';
        final style = Theme.of(tester.element(find.text(text))).textTheme.titleMedium;
        final natural = (TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout()).width;
        expect(title.width, greaterThanOrEqualTo(natural < 90 ? natural - 0.5 : 90), reason: '$language at $width');
        expect(line.height, lessThan(60), reason: '$language at $width');
      }
    }
  });

  testWidgets('buttons keep their labels where they fit and turn into icons where not', (tester) async {
    await pumpHeader(tester, width: 1200, words: const {});
    expect(find.text('Subtitle list'), findsOneWidget);
    await pumpHeader(tester, width: 360, words: const {});
    expect(find.text('Subtitle list'), findsNothing);
    expect(byTooltip('Subtitle list'), findsOneWidget);
  });

  test('the picture moves out from under a panel only when enough is left', () {
    const box = Rect.fromLTWH(0, 0, 932, 430);
    expect(VideoObstructionAvoider.insetsFor(box, null), EdgeInsets.zero);
    expect(VideoObstructionAvoider.insetsFor(box, const Rect.fromLTWH(372, 0, 560, 430)), const EdgeInsets.only(right: 560));
    expect(VideoObstructionAvoider.insetsFor(box, const Rect.fromLTWH(0, 0, 560, 430)), const EdgeInsets.only(left: 560));
    expect(VideoObstructionAvoider.insetsFor(box, const Rect.fromLTWH(232, 0, 700, 430)), EdgeInsets.zero);
    // A player beside the panel, not under it.
    expect(VideoObstructionAvoider.insetsFor(const Rect.fromLTWH(0, 0, 300, 200), const Rect.fromLTWH(400, 0, 400, 800)), EdgeInsets.zero);
  });
}
