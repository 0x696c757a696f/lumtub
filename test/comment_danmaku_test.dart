import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/comment_danmaku.dart';
import 'package:lumtub/danmaku.dart';
import 'package:lumtub/youtube_comments.dart';

void main() {
  YoutubeComment comment(String id, String text) => YoutubeComment(id: id, author: '@a', text: text);

  test('comments that name a moment fly at it', () {
    final lines = timedComments([
      comment('a', '3:45 this part is the best'),
      comment('b', 'The drop at 1:02:03 😂'),
      comment('c', 'no time here, 3.45 or 12:3 either'),
      comment('d', '0:00 Intro\n1:00 - Verse\n2:00 Chorus\n3:00 Outro'),
      comment('e', 'first line\n0:30 | the bridge\n9:99 nonsense'),
      comment('f', '2:00'),
      comment('g', '59:00 past the end'),
    ], length: const Duration(minutes: 70));
    expect([for (final l in lines) (l.offset, l.text)], [
      (const Duration(seconds: 30), 'the bridge'),
      (const Duration(minutes: 3, seconds: 45), 'this part is the best'),
      (const Duration(minutes: 59), 'past the end'),
      (const Duration(hours: 1, minutes: 2, seconds: 3), 'The drop at 1:02:03 😂'),
    ]);
    expect(lines.map((l) => l.id).toSet().length, lines.length);
    expect(timedComments([comment('h', '10:00 later')], length: const Duration(minutes: 5)), isEmpty);
  });

  test('a long line is cut', () {
    final line = timedComments([comment('a', '1:00 ${'x' * 200}')]).single.text;
    expect(line.runes.length, 80);
    expect(line.endsWith('…'), isTrue);
  });

  test('timed comments are on by default and saved', () {
    expect(const DanmakuSettings().comments, isTrue);
    expect(DanmakuSettings.fromJson(const DanmakuSettings(comments: false).toJson()).comments, isFalse);
    expect(DanmakuSettings.fromJson({'enabled': true}).comments, isTrue);
  });

  test('turning 弹幕 on with nothing playing changes only the setting', () async {
    final controller = AppController()..ready = true;
    await controller.setDanmaku(const DanmakuSettings(enabled: true));
    expect(controller.preferences.danmaku.enabled, isTrue);
  });
}
