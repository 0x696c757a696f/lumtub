import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/intelligence.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/speech_subtitles.dart';
import 'package:lumtub/translation.dart' show TranslationException;
import 'package:lumtub/translation_services.dart';

class _Local extends IntelligenceProvider {
  const _Local();
  @override
  String get id => 'local';
  @override
  ProviderKind get kind => ProviderKind.local;
  @override
  bool can(Capability capability) => capability == Capability.complete;
  @override
  String modelFor(Capability capability) => 'qwen3-4b';
  @override
  Future<String> complete(String system, String prompt, {double temperature = 0.3}) async => 'local answer';
}

void main() {
  late List<Map<String, dynamic>> asked;
  late http.Client client;

  setUp(() {
    asked = [];
    client = MockClient((request) async {
      if (request.url.path.endsWith('/chat/completions')) {
        asked.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({
          'choices': [
            {'message': {'content': 'cloud answer'}},
          ],
        }), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('no', 404);
    });
  });

  AiTranslator ai() => AiTranslator(client, baseUrl: 'https://api.example.com/v1', key: 'k', model: 'deepseek-chat', prompt: 'Translate into {target}.');

  test('the cloud provider asks the service set up, as before', () async {
    final intelligence = Intelligence([CloudIntelligence(ai: ai())]);
    expect(intelligence.can(Capability.complete), isTrue);
    expect(intelligence.can(Capability.transcribe), isFalse);
    expect(intelligence.can(Capability.embed), isFalse);
    expect(await intelligence.complete('Be brief.', 'Hello'), 'cloud answer');
    final messages = asked.single['messages'] as List;
    expect(messages.first, {'role': 'system', 'content': 'Be brief.'});
    expect(asked.single['model'], 'deepseek-chat');
    expect(intelligence.makerOf(Capability.complete), 'cloud:deepseek-chat');
    expect(intelligence.providerFor(Capability.complete)!.offline, isFalse);
  });

  test('a provider on this device goes before the cloud', () async {
    final intelligence = Intelligence([CloudIntelligence(ai: ai()), const _Local()]);
    expect(await intelligence.complete('s', 'p'), 'local answer');
    expect(intelligence.makerOf(Capability.complete), 'local:qwen3-4b');
    expect(asked, isEmpty);
    // Translation is still only in the cloud.
    expect(intelligence.providerFor(Capability.translate)!.id, 'cloud');
    final cloudFirst = Intelligence([CloudIntelligence(ai: ai()), const _Local()], order: const [ProviderKind.cloud, ProviderKind.local]);
    expect(await cloudFirst.complete('s', 'p'), 'cloud answer');
  });

  test('without a provider the user is told what to set up', () async {
    final intelligence = Intelligence(const [CloudIntelligence()]);
    expect(intelligence.makerOf(Capability.transcribe), '');
    await expectLater(intelligence.complete('s', 'p'), throwsA(isA<TranslationException>()));
    await expectLater(intelligence.transcribe(const []), throwsA(isA<TranslationException>()));
  });

  test('cloud speech recognition sends each part and joins them in order', () async {
    final temp = await Directory.systemTemp.createTemp('lumtub-speech');
    addTearDown(() => temp.delete(recursive: true));
    final heard = <String>[];
    final speech = MockClient((request) async {
      final body = utf8.decode(request.bodyBytes, allowMalformed: true);
      final part = RegExp(r'part(\d)').firstMatch(body)!.group(1)!;
      heard.add(part);
      return http.Response(jsonEncode({
        'language': 'english',
        'segments': [
          {'start': 0.0, 'end': 1.5, 'text': 'part $part'},
        ],
      }), 200, headers: {'content-type': 'application/json'});
    });
    final parts = <SpeechPart>[
      for (var i = 0; i < 3; i++) (file: await File('${temp.path}/part$i.webm').writeAsBytes([1, 2, 3]), offset: Duration(minutes: 10 * i)),
    ];
    final cloud = CloudIntelligence(speech: SpeechRecognizer(speech, baseUrl: 'https://api.example.com/v1/', key: 'k', model: 'whisper-1'));
    final progress = <int>[];
    final transcript = await Intelligence([cloud]).transcribe(parts, language: 'en', onProgress: (done, total) => progress.add(done));
    expect(heard.toSet(), {'0', '1', '2'});
    expect(progress.last, 3);
    expect(transcript.origin, TextOrigin.machineCloud);
    expect(transcript.model, 'whisper-1');
    expect(transcript.language, 'en');
    expect(transcript.vtt, contains('00:20:00.000 --> 00:20:01.500'));
    expect(transcript.vtt.indexOf('part 0'), lessThan(transcript.vtt.indexOf('part 2')));
  }, skip: NativeCore.instance == null ? 'needs lumtub_core (LUMTUB_CORE_DLL)' : false);

  test('a hosted model known to read long texts gets the whole transcript at once', () {
    expect(CloudIntelligence.longContextModel('deepseek-chat', 'https://api.deepseek.com/v1'), isTrue);
    expect(CloudIntelligence.longContextModel('gemini-2.5-flash', 'https://generativelanguage.googleapis.com/v1beta/openai'), isTrue);
    expect(CloudIntelligence.longContextModel('Qwen/Qwen2.5-7B-Instruct', 'https://api.siliconflow.cn/v1'), isFalse);
    // A model on this computer may be set to a short context.
    expect(CloudIntelligence.longContextModel('qwen3', 'http://localhost:11434/v1'), isFalse);
    expect(const CloudIntelligence().completeBudget, IntelligenceProvider.shortBudget);
  });
}
