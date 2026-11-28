import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/subtitle_cues.dart';

void main() {
  const vtt =
      'WEBVTT\n\n00:00:01.000 --> 00:00:02.500 align:start\n<c>Hello</c> &amp; hi\n\n00:00:02.500 --> 00:00:04.000\nHello &amp; hi\nworld\n';
  const srt = '1\r\n01:02:03,040 --> 01:02:04,500\r\n{\\an8}Line one\r\nLine two\r\n\r\n';

  for (final (name, parse) in [('native', parseSubtitleCues), ('Dart', dartSubtitleCues)]) {
    test('$name: reads WebVTT and SRT lines with their times', () {
      final lines = parse(vtt);
      expect([for (final c in lines) (c.start.inMilliseconds, c.end.inMilliseconds, c.text)],
          [(1000, 2500, 'Hello & hi'), (2500, 4000, 'world')]);
      final srtLines = parse(srt);
      expect([for (final c in srtLines) (c.start.inMilliseconds, c.text)],
          [(3723040, 'Line one Line two')]);
      expect(parse('[Script Info]\nDialogue: 0,0:00:01.00'), isEmpty);
    });
  }

  test('finds the line at a position', () {
    final cues = dartSubtitleCues(vtt);
    expect(cueIndexAt(cues, Duration.zero), -1);
    expect(cueIndexAt(cues, const Duration(milliseconds: 1500)), 0);
    expect(cueIndexAt(cues, const Duration(seconds: 3)), 1);
    expect(cueIndexAt(cues, const Duration(seconds: 30)), 1);
  });

  test('writes SRT', () {
    final srt = toSrt(dartSubtitleCues(vtt));
    expect(srt,
        '1\n00:00:01,000 --> 00:00:02,500\nHello & hi\n\n2\n00:00:02,500 --> 00:00:04,000\nworld\n\n');
    expect(dartSubtitleCues(srt).map((c) => c.text), ['Hello & hi', 'world']);
  });

  test('short caption lines join into whole sentences for reading', () {
    PairedCue row(int start, String text, [String? second]) => (
          cue: (
            start: Duration(milliseconds: start),
            end: Duration(milliseconds: start + 900),
            text: text
          ),
          second: second
        );
    final rows = sentenceRows([
      row(0, 'so the thing about batteries', '所以电池'),
      row(1000, 'is that they really hate the cold', '真的怕冷'),
      row(2000, 'and lose power when it freezes.'),
      // A pause ends a row even mid-sentence.
      row(6000, 'then'),
      row(9000, '电池在低温下会掉电，'),
      row(10000, '这是因为化学反应变慢了。'),
    ]);
    expect([
      for (final r in rows)
        (r.cue.start.inMilliseconds, r.cue.end.inMilliseconds, r.cue.text, r.second)
    ], [
      (
        0,
        2900,
        'so the thing about batteries is that they really hate the cold and lose power when it freezes.',
        '所以电池真的怕冷'
      ),
      (6000, 6900, 'then', null),
      (9000, 10900, '电池在低温下会掉电，这是因为化学反应变慢了。', null),
    ]);
  });
}
