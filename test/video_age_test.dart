import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/ui/video_card.dart';
import 'package:lumtub/youtube_related.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('a related video keeps the age YouTube wrote and shows it after its views', () {
    final item = videoFromCore({'id': 'aaaaaaaaaaa', 'title': 'T', 'channel': 'C', 'live': false, 'viewCount': 1000, 'age': '3 days ago'});
    expect(item.age, '3 days ago');
    expect(VideoItem.fromJson(item.toJson()).age, '3 days ago');
    expect(MetaLine.of(item, style: const TextStyle()).tail, endsWith('3 days ago'));
    final live = videoFromCore({'id': 'aaaaaaaaaaa', 'title': 'T', 'channel': 'C', 'live': true, 'age': '3 days ago'});
    expect(MetaLine.of(live, style: const TextStyle()).tail, isNot(contains('ago')));
  });

  testWidgets('a narrow card shows the views on the picture and the age with the channel', (tester) async {
    final item = videoFromCore({'id': 'aaaaaaaaaaa', 'title': 'T', 'channel': 'A channel with a long name', 'live': false, 'viewCount': 1234567, 'age': '11 months ago'});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 180, height: 260, child: VideoCard(item: item, onOpen: () {}))))));
    expect(find.textContaining('views'), findsOneWidget);
    expect(find.textContaining('ago'), findsOneWidget, reason: 'the picture line holds the views alone');
    expect(find.textContaining(' · 11 months ago'), findsOneWidget);
  });

  test('a long channel name is cut letter by letter, its ellipsis right after the last letter', () {
    const style = TextStyle(fontSize: 12);
    double width(String text) {
      final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    String fit(String lead, String room) => MetaLine.fit(lead, width(room), style, TextScaler.noScaling, TextDirection.ltr);
    expect(fit('Yinuo Li 李一諾', 'Yinuo Li 李一諾'), 'Yinuo Li 李一諾');
    expect(fit('Yinuo Li 李一諾', 'Yinuo Li 李…'), 'Yinuo Li 李…', reason: 'not cut back to the last whole word');
    expect(fit('旅人歸途 • 虞超 Traveller Returning', '旅人歸途 • 虞…'), '旅人歸途 • 虞…');
    expect(fit('旅人歸途 • 虞超 Traveller Returning', '旅人歸途 • …'), '旅人歸途…', reason: 'no dot left hanging before the ellipsis');
  });
}
