import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/subtitle_files.dart';

/// The core's WebVTT (native/lumtub_core/src/vtt.rs) against the Dart it
/// replaced, on tracks made at random with the odd corners real ones have.
void main() {
  const words = [
    'hello', 'world.', 'so,', 'and then', 'what?', 'yes!', '你好', '世界。', '我们，', '今天', '안녕하세요', '세계.', 'สวัสดี', 'ครับ',
    'こんにちは', '「はい」', 'end…', '"quoted."', '(aside)', '😀', 'a&amp;b', '&lt;tag&gt;', '&nbsp;', '<c>word</c>', '<00:00:01.200>', 'x<y', 'ok;', '،', 'हाँ।',
    ' ', '\u0085', '﻿', '　', ' ', '', 'Ελλάδα', 'مرحبا؟', 'ok:', 'line,', '»fin.«',
  ];
  const stamps = ['00:00:01.000', '00:01.500', '1:00:00.000', '00:00:02', '00:00:01.0005', '0:0:3.', '.5', '00:00:1e1', '00:-1:00.000', '0x1:00.000', '99999999999999999999:00.0', '00:00:01.000x'];
  final random = Random(7);

  String stamp(int ms) {
    if (random.nextInt(12) == 0) return stamps[random.nextInt(stamps.length)];
    final h = ms ~/ 3600000, m = ms ~/ 60000 % 60, s = ms ~/ 1000 % 60, f = ms % 1000;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${random.nextBool() ? '${two(h)}:' : ''}${two(m)}:${two(s)}.${f.toString().padLeft(3, '0')}';
  }

  String text() => [for (var k = random.nextInt(4); k >= 0; k--) words[random.nextInt(words.length)]].join(random.nextInt(5) == 0 ? '' : ' ');

  String track() {
    final out = StringBuffer(random.nextInt(4) == 0 ? '' : 'WEBVTT\n\n');
    var at = random.nextInt(5000);
    String? last;
    for (var n = random.nextInt(40); n > 0; n--) {
      final length = 200 + random.nextInt(4000);
      final gap = random.nextInt(5) == 0 ? random.nextInt(3000) : 0;
      if (random.nextInt(8) == 0) out.write('cue-$n\n');
      final space = [' ', '  ', '\t', ' '][random.nextInt(4)];
      out.write('${random.nextBool() ? '' : ' '}${stamp(at + gap)}$space-->$space${stamp(at + gap + length)}${random.nextInt(4) == 0 ? ' align:start position:0%' : ''}\n');
      final lines = [if (last != null && random.nextBool()) last, for (var k = random.nextInt(3); k >= 0; k--) text()];
      out.write(lines.join(random.nextInt(6) == 0 ? '\r\n' : '\n'));
      last = lines.last;
      out.write(['\n\n', '\n\n\n', '\r\n\r\n', '\n\n\n\n\n', '\n \n'][random.nextInt(5)]);
      at += gap + length;
    }
    return out.toString();
  }

  test('reads tracks as the Dart did', () {
    var compared = 0;
    for (var round = 0; round < 3000; round++) {
      final vtt = track();
      final List<({String timing, String text})> cues;
      final Object planCues, planPieces, sentences;
      try {
        cues = WebVtt.dartCues(vtt);
        final p = WebVtt.dartPlan(vtt);
        planCues = p.cues;
        planPieces = p.pieces;
        sentences = WebVtt.sentences(cues);
      } on UnsupportedError {
        continue; // Dart could not round an infinite time; the core reads 0.
      }
      expect(WebVtt.cues(vtt), cues, reason: vtt);
      final p = WebVtt.plan(vtt);
      expect(p.cues, planCues, reason: vtt);
      expect(p.pieces, planPieces, reason: vtt);
      expect(WebVtt.sentencesOf(vtt), sentences, reason: vtt);
      compared++;
    }
    expect(compared, greaterThan(2900));
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);

  test('cuts translations as the Dart did', () {
    final asks = <(String, List<int>)>[];
    for (var round = 0; round < 5000; round++) {
      final text = [for (var k = random.nextInt(12); k >= 0; k--) words[random.nextInt(words.length)]].join(random.nextInt(3) == 0 ? '' : ' ');
      asks.add((text, [for (var k = random.nextInt(5); k >= 0; k--) random.nextInt(30) - (random.nextInt(10) == 0 ? 10 : 0)]));
    }
    expect(WebVtt.splitMany(asks), [for (final (text, weights) in asks) WebVtt.splitLike(text, weights)]);
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);
}
