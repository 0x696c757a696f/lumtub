import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/subtitle_cues.dart';

SubtitleCue cue(int start, int end, String text) => (start: Duration(milliseconds: start), end: Duration(milliseconds: end), text: text);

void main() {
  test('second lines land beside the main line spoken with them', () {
    final paired = pairSubtitleCues(
      [cue(0, 2000, 'Hello'), cue(2000, 4000, 'World'), cue(9000, 10000, 'Alone')],
      [cue(100, 1900, '你好'), cue(1800, 4100, '世界'), cue(5000, 6000, '多余')],
    );
    expect([for (final p in paired) p.second], ['你好', '世界', null]);
  });

  test('a line left untranslated joins the next one, which holds its words', () {
    final paired = pairSubtitleCues(
      [cue(0, 3000, 'Avete davvero fatto pulizia nelle vostre'), cue(3000, 6000, 'relazioni oppure avete semplicemente'), cue(20000, 22000, 'Alone')],
      [cue(3000, 6000, '你是否真的清理了你们的人际关系，还是刚刚停止')],
    );
    expect([for (final p in paired) p.cue.text], ['Avete davvero fatto pulizia nelle vostre relazioni oppure avete semplicemente', 'Alone']);
    expect([for (final p in paired) p.second], ['你是否真的清理了你们的人际关系，还是刚刚停止', null]);
  });

  test('without a second subtitle every line stands alone', () {
    final paired = pairSubtitleCues([cue(0, 1000, 'a')], const []);
    expect(paired.single.cue.text, 'a');
    expect(paired.single.second, isNull);
  });

  test('main lines one translated sentence spans become one row', () {
    final paired = pairSubtitleCues(
      [cue(0, 2000, 'will continue to strengthen line'), cue(2000, 4000, 'management. By the time we got there,'), cue(4000, 6000, 'they were already at the front')],
      [cue(0, 4000, '将继续加强一线管理。当我们到达那里时，'), cue(4000, 6000, '他们已经到了最前面')],
    );
    expect([for (final p in paired) p.cue.text], ['will continue to strengthen line management. By the time we got there,', 'they were already at the front']);
    expect([for (final p in paired) p.second], ['将继续加强一线管理。当我们到达那里时，', '他们已经到了最前面']);
    expect(paired.first.cue.end, const Duration(milliseconds: 4000));
  });

  test('a translation brushing the next line does not pull it in', () {
    final paired = pairSubtitleCues(
      [cue(0, 2000, 'one'), cue(2000, 4000, 'two')],
      [cue(0, 2150, '一'), cue(2150, 4000, '二')],
    );
    expect(paired.length, 2);
  });

  test('rows stop at a sentence length', () {
    final main = [for (var i = 0; i < 10; i++) cue(i * 2000, i * 2000 + 2000, 'w$i')];
    final paired = pairSubtitleCues(main, [cue(0, 20000, '很长')]);
    expect(paired.every((p) => p.cue.end - p.cue.start <= const Duration(seconds: 15)), isTrue);
  });

  test('joins words with spaces and Chinese without', () {
    expect(joinCueText('hello', 'world'), 'hello world');
    expect(joinCueText('你好', '世界'), '你好世界');
    expect(joinCueText('时，', 'and'), '时，and');
  });
}
