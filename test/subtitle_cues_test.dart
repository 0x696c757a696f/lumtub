import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/subtitle_cues.dart';

void main() {
  const vtt = 'WEBVTT\n\n00:00:01.000 --> 00:00:02.500 align:start\n<c>Hello</c> &amp; hi\n\n00:00:02.500 --> 00:00:04.000\nHello &amp; hi\nworld\n';
  const srt = '1\r\n01:02:03,040 --> 01:02:04,500\r\n{\\an8}Line one\r\nLine two\r\n\r\n';

  for (final (name, parse) in [('native', parseSubtitleCues), ('Dart', dartSubtitleCues)]) {
    test('$name: reads WebVTT and SRT lines with their times', () {
      final lines = parse(vtt);
      expect([for (final c in lines) (c.start.inMilliseconds, c.end.inMilliseconds, c.text)], [(1000, 2500, 'Hello & hi'), (2500, 4000, 'world')]);
      final srtLines = parse(srt);
      expect([for (final c in srtLines) (c.start.inMilliseconds, c.text)], [(3723040, 'Line one Line two')]);
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
}
