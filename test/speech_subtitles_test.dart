import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/speech_subtitles.dart';
import 'package:lumtub/subtitle_files.dart';
import 'package:lumtub/subtitle_translation.dart';
import 'package:lumtub/translation.dart';
import 'package:lumtub/translation_services.dart';

class _Upper implements Translator {
  @override
  Future<String> translate(String text, String target) async => text.toUpperCase();
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('lumtub_speech'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('asks /audio/transcriptions for timed segments and reads the answer', () async {
    late http.BaseRequest seen;
    String? fields;
    final client = MockClient.streaming((request, body) async {
      seen = request;
      fields = utf8.decode(await body.toBytes(), allowMalformed: true);
      final answer = {'language': 'english', 'segments': [{'start': 0.0, 'end': 1.5, 'text': 'Hi'}]};
      return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(answer))), 200);
    });
    final audio = File('${dir.path}/audio.webm')..writeAsBytesSync([1, 2, 3]);
    final recognizer = SpeechRecognizer(client, baseUrl: 'https://api.groq.com/openai/v1/', key: 'k', model: 'whisper-large-v3-turbo');
    final answer = await recognizer.transcribe(audio, language: 'en');
    expect(seen.url.toString(), 'https://api.groq.com/openai/v1/audio/transcriptions');
    expect(seen.headers['Authorization'], 'Bearer k');
    expect(fields, allOf(contains('verbose_json'), contains('whisper-large-v3-turbo'), contains('filename="audio.webm"'), contains('name="language"')));
    expect(answer['segments'], hasLength(1));
    expect(speechLanguageTag(answer['language']), 'en');
  });

  test('says why a service fails or gives no timing', () async {
    Future<String> failure(int status, Object body) async {
      final client = MockClient((_) async => http.Response(jsonEncode(body), status));
      final audio = File('${dir.path}/a.m4a')..writeAsBytesSync([1]);
      try {
        await SpeechRecognizer(client, baseUrl: 'https://x.example/v1', key: '', model: 'm').transcribe(audio);
        return '';
      } on TranslationException catch (e) {
        return e.message;
      }
    }

    expect(await failure(401, {}), 'The speech recognition key is not valid');
    expect(await failure(429, {}), 'Too many speech recognition requests or the quota is used up; try again later');
    expect(await failure(200, {'text': 'only text'}), 'This speech recognition service returns no timing, so it cannot make subtitles');
  });

  test('fetches the smallest audio stream with yt-dlp', () {
    final args = SpeechAudio.arguments('abc', dir, proxy: 'socks5://p', deno: 'deno.exe');
    expect(args, containsAllInOrder(['--format', 'wa[acodec=opus]/wa/ba']));
    expect(args, containsAllInOrder(['--fixup', 'never']));
    expect(args, containsAllInOrder(['--proxy', 'socks5://p']));
    expect(args, containsAllInOrder(['--js-runtimes', 'deno:deno.exe']));
    expect(args.last, 'https://www.youtube.com/watch?v=abc');
  });

  test('a long video is cut by lumtub_core, and the audio is kept when it cannot be', () async {
    final runs = File('${dir.path}/runs');
    final fake = File('${dir.path}/yt-dlp.sh')
      ..writeAsStringSync('#!/bin/sh\necho run >> ${runs.path}\nhead -c 21000000 /dev/zero > ${dir.path}/work/audio.webm\necho "3600.0|${dir.path}/work/audio.webm"\n');
    await Process.run('chmod', ['+x', fake.path]);
    Future<List<SpeechPart>> fetch() => SpeechAudio.fetch('abc', Directory('${dir.path}/work'), ytDlp: fake.path, environment: const {});
    final notAudio = throwsA(isA<TranslationException>().having((e) => e.message, 'message', 'Could not split the audio'));
    await expectLater(fetch(), notAudio);
    await expectLater(fetch(), notAudio);
    expect(runs.readAsLinesSync(), hasLength(1));
  }, skip: Platform.isWindows ? 'uses a shell script for yt-dlp' : null);

  test('lumtub_core turns the answers into subtitles at their offsets', () async {
    final vtt = await speechVtt([
      (offset: Duration.zero, answer: {'segments': [{'start': 0.0, 'end': 2.0, 'text': 'first'}]}),
      (offset: const Duration(minutes: 10), answer: {'segments': [{'start': 1.0, 'end': 2.0, 'text': 'second'}]}),
    ]);
    expect(vtt, contains('00:00:00.000 --> 00:00:02.000\nfirst'));
    expect(vtt, contains('00:10:01.000 --> 00:10:02.000\nsecond'));
  });

  test('keeps recognized subtitles by video and language', () async {
    final store = SpeechSubtitleStore(Directory('${dir.path}/speech'), keep: 2);
    expect(await store.of('vid'), isNull);
    await store.save('vid', 'en', 'WEBVTT\n\n');
    expect((await store.of('vid'))?.language, 'en');
    await store.save('two', 'ja', 'WEBVTT\n\n');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await store.save('three', 'ja', 'WEBVTT\n\n');
    expect(Directory('${dir.path}/speech').listSync(), hasLength(2));
  });

  test('a recognized track is the original and can be translated', () async {
    final file = File('${dir.path}/vid.en.vtt')..writeAsStringSync('WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nhello\n');
    final speech = SubtitleOption(language: 'en', name: '', url: file.uri.toString(), kind: SubtitleKind.speech);
    expect(speech.label, contains('speech recognition'));
    expect(originalSubtitle([speech], language: null), same(speech));
    final translated = translationOf([speech], TranslationLanguage.all.firstWhere((l) => l.code == 'zh-CN'))!;
    final files = SubtitleFiles(MockClient((_) async => http.Response('', 500)), Directory('${dir.path}/subs'), _Upper.new);
    expect(await File(await files.pathFor(speech)).readAsString(), contains('hello'));
    expect(await File(await files.pathFor(translated)).readAsString(), contains('HELLO'));
  });

  test('语音识别 settings survive a round trip and reuse an OpenAI key', () {
    const config = TranslationConfig(aiPreset: 'openai', speechPreset: 'openai', speechModel: 'gpt-4o-transcribe');
    final again = TranslationConfig.fromJson(jsonDecode(jsonEncode(config.toJson())));
    expect(again, config);
    expect(again.effectiveSpeechBaseUrl, 'https://api.openai.com/v1');
    expect(speechKeyFor(config, const {'ai': 'sk'}), 'sk');
    expect(speechReady(config, const {'ai': 'sk'}), isTrue);
    expect(speechReady(const TranslationConfig(), const {'ai': 'sk'}), isFalse);
    expect(speechReady(const TranslationConfig(), const {'speech': 'gsk'}), isTrue);
    expect(config.cacheScope, const TranslationConfig(aiPreset: 'openai').cacheScope);
  });
}
