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

  test('without a second subtitle every line stands alone', () {
    final paired = pairSubtitleCues([cue(0, 1000, 'a')], const []);
    expect(paired.single.cue.text, 'a');
    expect(paired.single.second, isNull);
  });
}
