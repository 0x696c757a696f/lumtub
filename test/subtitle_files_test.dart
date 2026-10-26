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
    expect(translator.asked, ['hello world\nhow & why']);
    expect(translator.targets, ['zh-CN']);
    expect(await File(path).readAsString(), contains('00:00:02.010 --> 00:00:04.000 align:start position:0%\nHOW &amp; WHY\n'));
  });

  test('asks again in halves when a translation joins lines', () async {
    final vtt = StringBuffer('WEBVTT\n\n');
    for (var i = 0; i < 5; i++) {
      vtt.write('00:00:0$i.000 --> 00:00:0$i.900\nline $i\n\n');
    }
    final client = MockClient((request) async => request.url.queryParameters.containsKey('tlang') ? http.Response('', 429) : http.Response('$vtt', 200));
    final translator = _Joining();
    final files = SubtitleFiles(client, folder, () => translator, pauses: const [Duration.zero]);
    final path = await files.pathFor(const SubtitleOption(language: 'zh-Hans', name: '', url: 'https://www.youtube.com/api/timedtext?v=a&lang=en&tlang=zh-Hans', kind: SubtitleKind.translated));
    expect(WebVtt.cues(await File(path).readAsString()).map((c) => c.text), ['LINE 0', 'LINE 1', 'LINE 2', 'LINE 3', 'LINE 4']);
    expect(translator.asked.first, 'line 0\nline 1\nline 2\nline 3\nline 4');
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
