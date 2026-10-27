import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/subtitle_files.dart';
import 'package:lumtub/translation.dart';

class _Upper implements Translator {
  final asked = <String>[];
  final targets = <String>[];
  @override
  Future<String> translate(String text, String target) async {
    asked.add(text);
    targets.add(target);
    return text.toUpperCase();
  }
}

/// Joins every two lines into one, as machine translation does with short
/// caption fragments.
class _Joining implements Translator {
  final asked = <String>[];
  @override
  Future<String> translate(String text, String target) async {
    asked.add(text);
    final lines = text.split('\n');
    return [for (var i = 0; i < lines.length; i += 2) lines.skip(i).take(2).join(' ').toUpperCase()].join('\n');
  }
}

/// Uppercases after a short wait, recording how many requests overlap.
class _Slow implements Translator {
  _Slow(this.running, this.set);
  final int Function() running;
  final void Function(int) set;
  @override
  Future<String> translate(String text, String target) async {
    set(running() + 1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    set(running() - 1);
    return text.toUpperCase();
  }
}

const _auto = '''WEBVTT
Kind: captions
Language: en

00:00:00.000 --> 00:00:02.000 align:start position:0%
hello<00:00:00.500><c> world</c>

00:00:02.000 --> 00:00:02.010 align:start position:0%
hello world

00:00:02.010 --> 00:00:04.000 align:start position:0%
hello world
how &amp; why
''';

void main() {
  late Directory folder;
  setUp(() async => folder = await Directory.systemTemp.createTemp('lumtub-subs'));
  tearDown(() async {
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  test('reads cues without word timings or repeated lines', () {
    expect(WebVtt.cues(_auto).map((c) => c.text), ['hello world', 'how & why']);
    expect(WebVtt.cues(_auto).last.timing, '00:00:02.010 --> 00:00:04.000 align:start position:0%');
  });

  test('skips cues with no text, as automatic captions have between lines', () {
    const vtt = 'WEBVTT\n\n00:00:00.000 --> 00:00:01.000\n \n\n00:00:01.000 --> 00:00:02.000\nhello\n\n00:00:02.000 --> 00:00:02.010\n&nbsp;\n';
    expect(WebVtt.cues(vtt).map((c) => c.text), ['hello']);
  });

  test('retries a 429 and saves the track to a file', () async {
    var calls = 0;
    final client = MockClient((request) async => ++calls < 3 ? http.Response('', 429) : http.Response('WEBVTT\n', 200));
    final files = SubtitleFiles(client, folder, _Upper.new, pauses: const [Duration.zero, Duration.zero]);
    final path = await files.pathFor(const SubtitleOption(language: 'en', name: 'English', url: 'https://www.youtube.com/api/timedtext?v=a&lang=en'));
    expect(calls, 3);
    expect(await File(path).readAsString(), 'WEBVTT\n');
  });

  test('translates the original itself when YouTube refuses the translation', () async {
    final asked = <Uri>[];
    final client = MockClient((request) async {
      asked.add(request.url);
      return request.url.queryParameters.containsKey('tlang') ? http.Response('', 429) : http.Response(_auto, 200);
    });
    final translator = _Upper();
    final files = SubtitleFiles(client, folder, () => translator, pauses: const [Duration.zero]);
    final path = await files.pathFor(const SubtitleOption(language: 'zh-Hans', name: '', url: 'https://www.youtube.com/api/timedtext?v=a&lang=en&tlang=zh-Hans', kind: SubtitleKind.translated));
    expect(asked.last.queryParameters.containsKey('tlang'), isFalse);
    expect(translator.asked, ['hello world how & why']);
    expect(translator.targets, ['zh-CN']);
    expect(await File(path).readAsString(), contains('00:00:00.000 --> 00:00:04.000\nHELLO WORLD HOW &amp; WHY\n'));
  });

  test('asks again in halves when a translation joins lines', () async {
    final vtt = StringBuffer('WEBVTT\n\n');
    for (var i = 0; i < 5; i++) {
      vtt.write('00:00:0$i.000 --> 00:00:0$i.900\nline $i.\n\n');
    }
    final client = MockClient((request) async => request.url.queryParameters.containsKey('tlang') ? http.Response('', 429) : http.Response('$vtt', 200));
    final translator = _Joining();
    final files = SubtitleFiles(client, folder, () => translator, pauses: const [Duration.zero]);
    final path = await files.pathFor(const SubtitleOption(language: 'zh-Hans', name: '', url: 'https://www.youtube.com/api/timedtext?v=a&lang=en&tlang=zh-Hans', kind: SubtitleKind.translated));
    expect(WebVtt.cues(await File(path).readAsString()).map((c) => c.text), ['LINE 0.', 'LINE 1.', 'LINE 2.', 'LINE 3.', 'LINE 4.']);
    expect(translator.asked.first, 'line 0.\nline 1.\nline 2.\nline 3.\nline 4.');
  });

  test('translates a long track a few requests at a time, in order', () async {
    final vtt = StringBuffer('WEBVTT\n\n');
    for (var i = 0; i < 40; i++) {
      vtt.write('00:00:${i.toString().padLeft(2, '0')}.000 --> 00:00:${i.toString().padLeft(2, '0')}.900\n${'word$i ' * 300}\n\n');
    }
    final client = MockClient((request) async => request.url.queryParameters.containsKey('tlang') ? http.Response('', 429) : http.Response('$vtt', 200));
    var running = 0, most = 0;
    final translator = _Slow(() => running, (n) {
      running = n;
      if (n > most) most = n;
    });
    final updated = <String>[];
    final files = SubtitleFiles(client, folder, () => translator, pauses: const [Duration.zero], concurrency: 3, position: () => const Duration(seconds: 20), onUpdated: updated.add);
    const option = SubtitleOption(language: 'zh-Hans', name: '', url: 'https://www.youtube.com/api/timedtext?v=a&lang=en&tlang=zh-Hans', kind: SubtitleKind.translated);
    final path = await files.pathFor(option);
    // First the pieces from where playback is.
    final first = WebVtt.cues(await File(path).readAsString());
    expect(first, isNotEmpty);
    expect(first.length, lessThan(40));
    expect(first.first.text, startsWith('WORD20'));
    expect(await files.wholePathFor(option), path);
    final cues = WebVtt.cues(await File(path).readAsString());
    expect(cues, hasLength(40));
    expect([for (final c in cues) c.text.split(' ').first], [for (var i = 0; i < 40; i++) 'WORD$i']);
    expect(most, 3);
    expect(updated, [path]);
  });

  test('joins caption fragments into sentences for translation', () {
    ({String timing, String text}) cue(String from, String to, String text) => (timing: '00:00:$from --> 00:00:$to align:start', text: text);
    final joined = WebVtt.sentences([
      cue('00.000', '01.500', 'so today we are'),
      cue('01.500', '03.000', 'going to talk about'),
      cue('03.000', '04.000', 'subtitles.'),
      cue('04.100', '05.000', 'Next one'),
      cue('09.000', '10.000', 'after a pause'),
      cue('10.000', '11.000', '我们今天'),
      cue('11.000', '12.000', '来聊字幕。'),
    ]);
    expect([for (final c in joined) c.text], ['so today we are going to talk about subtitles.', 'Next one', 'after a pause 我们今天来聊字幕。']);
    expect(joined.first.timing, '00:00:00.000 --> 00:00:04.000');
    expect(joined[1].timing, '00:00:04.100 --> 00:00:05.000 align:start');
  });

  test('a sentence stops growing past what can be read at once', () {
    final cues = [for (var i = 0; i < 10; i++) (timing: '00:00:0$i.000 --> 00:00:0$i.900', text: 'and then some more words')];
    final joined = WebVtt.sentences(cues);
    expect(joined.length, greaterThan(1));
    expect(joined.every((c) => WebVtt.endOf(c.timing) - WebVtt.startOf(c.timing) <= const Duration(seconds: 7)), isTrue);
    expect(joined.every((c) => c.text.length <= 90), isTrue);
  });

  test('reads when a cue starts', () {
    expect(WebVtt.startOf('00:01:02.500 --> 00:01:04.000 align:start'), const Duration(minutes: 1, seconds: 2, milliseconds: 500));
    expect(WebVtt.startOf('1:00:00.000 --> 1:00:01.000'), const Duration(hours: 1));
    expect(WebVtt.startOf('02.250 --> 03.000'), const Duration(seconds: 2, milliseconds: 250));
  });

  test('a track that cannot be fetched fails and is asked again next time', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('', 403);
    });
    final files = SubtitleFiles(client, folder, _Upper.new);
    const option = SubtitleOption(language: 'en', name: '', url: 'https://www.youtube.com/api/timedtext?v=a&lang=en');
    await expectLater(files.pathFor(option), throwsA(anything));
    await expectLater(files.pathFor(option), throwsA(anything));
    expect(calls, 2);
  });

  test('asks the chosen translator instead of YouTube when told to', () async {
    final asked = <Uri>[];
    final client = MockClient((request) async {
      asked.add(request.url);
      return http.Response(_auto, 200);
    });
    var translator = _Upper();
    final files = SubtitleFiles(client, folder, () => translator, byTranslator: () => true);
    const option = SubtitleOption(language: 'ja', name: '', url: 'https://www.youtube.com/api/timedtext?v=a&lang=en&tlang=ja', kind: SubtitleKind.translated);
    final path = await files.pathFor(option);
    expect(asked.map((u) => u.queryParameters.containsKey('tlang')), [false]);
    expect(translator.targets, ['ja']);
    expect(await File(path).readAsString(), contains('HELLO WORLD'));
    await files.pathFor(option);
    expect(translator.asked, hasLength(1));
    // Another translator, chosen in the settings, translates it again.
    translator = _Upper();
    await files.pathFor(option);
    expect(translator.asked, hasLength(1));
  });
}
