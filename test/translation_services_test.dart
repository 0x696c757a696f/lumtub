import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/l10n/l10n.dart';
import 'package:lumtub/translation.dart';
import 'package:lumtub/translation_services.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

Future<Object?> _fails(Future<String> future) async {
  try {
    await future;
  } on TranslationException catch (e) {
    return e.message;
  }
  return null;
}

void main() {
  group('DeepLTranslator', () {
    test('uses the free endpoint for :fx keys and the pro one otherwise', () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        return _json({'translations': [{'text': 'x'}]});
      });
      await DeepLTranslator(client, key: 'abc:fx').translate('a', 'ja');
      await DeepLTranslator(client, key: 'abc').translate('a', 'ja');
      expect(hosts, ['api-free.deepl.com', 'api.deepl.com']);
    });

    test('sends one text per non-empty line and keeps empty lines', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        final texts = Uri(query: request.body).queryParametersAll['text']!;
        return _json({'translations': [for (final t in texts) {'text': '译$t'}]});
      });
      final result = await DeepLTranslator(client, key: 'k:fx').translate('a\n\nb\n  \nc', 'zh-TW');
      expect(result, '译a\n\n译b\n  \n译c');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/v2/translate');
      expect(seen.headers['Authorization'], 'DeepL-Auth-Key k:fx');
      final params = Uri(query: seen.body).queryParametersAll;
      expect(params['text'], ['a', 'b', 'c']);
      expect(params['target_lang'], ['ZH-HANT']);
    });

    test('batches 50 lines per request', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        final texts = Uri(query: request.body).queryParametersAll['text']!;
        return _json({'translations': [for (final t in texts) {'text': t}]});
      });
      final text = [for (var i = 0; i < 120; i++) 'l$i'].join('\n');
      expect(await DeepLTranslator(client, key: 'k').translate(text, 'fr'), text);
      expect(calls, 3);
    });

    test('maps target languages', () {
      expect(DeepLTranslator.languageCode('zh-CN'), 'ZH-HANS');
      expect(DeepLTranslator.languageCode('en'), 'EN-US');
      expect(DeepLTranslator.languageCode('pt'), 'PT-BR');
      expect(DeepLTranslator.languageCode('ja'), 'JA');
      expect(DeepLTranslator.languageCode('vi'), isNull);
    });

    test('rejects unsupported languages and maps errors', () async {
      final ok = MockClient((_) async => _json({'translations': []}));
      expect(await _fails(DeepLTranslator(ok, key: 'k').translate('a', 'th')), tr('DeepL 不支持这种语言'));
      for (final entry in {
        403: tr('DeepL 密钥无效'),
        456: tr('DeepL 本月额度已用完'),
        429: tr('翻译请求太频繁，请稍后再试'),
        500: tr('翻译服务暂时不可用（{0}）', [500]),
      }.entries) {
        final client = MockClient((_) async => http.Response('', entry.key));
        expect(await _fails(DeepLTranslator(client, key: 'k').translate('a', 'de')), entry.value);
      }
      final broken = MockClient((_) async => throw http.ClientException('down'));
      expect(await _fails(DeepLTranslator(broken, key: 'k').translate('a', 'de')), tr('无法翻译，请检查网络或代理'));
    });

    test('returns empty input as is and caches results', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _json({'translations': [{'text': 'b'}]});
      });
      final translator = DeepLTranslator(client, key: 'k');
      expect(await translator.translate('  ', 'de'), '  ');
      expect(calls, 0);
      await translator.translate('a', 'de');
      await translator.translate('a', 'de');
      expect(calls, 1);
    });
  });

  group('MicrosoftTranslator', () {
    test('request shape and line preservation', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        final items = jsonDecode(request.body) as List;
        return _json([for (final item in items) {'translations': [{'text': '译${item['Text']}', 'to': 'zh-Hans'}]}]);
      });
      final result = await MicrosoftTranslator(client, key: 'k', region: 'eastasia').translate('a\n\nb', 'zh-CN');
      expect(result, '译a\n\n译b');
      expect(seen.method, 'POST');
      expect(seen.url.host, 'api.cognitive.microsofttranslator.com');
      expect(seen.url.path, '/translate');
      expect(seen.url.queryParameters, {'api-version': '3.0', 'to': 'zh-Hans'});
      expect(seen.headers['Ocp-Apim-Subscription-Key'], 'k');
      expect(seen.headers['Ocp-Apim-Subscription-Region'], 'eastasia');
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(seen.body), [{'Text': 'a'}, {'Text': 'b'}]);
    });

    test('omits the region header when empty and maps codes', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return _json([{'translations': [{'text': 'x'}]}]);
      });
      await MicrosoftTranslator(client, key: 'k').translate('a', 'zh-TW');
      expect(seen.headers.containsKey('Ocp-Apim-Subscription-Region'), isFalse);
      expect(seen.url.queryParameters['to'], 'zh-Hant');
      await MicrosoftTranslator(client, key: 'k').translate('a', 'ja');
      expect(seen.url.queryParameters['to'], 'ja');
    });

    test('batches 100 lines and maps errors', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        final items = jsonDecode(request.body) as List;
        return _json([for (final item in items) {'translations': [{'text': item['Text']}]}]);
      });
      final text = [for (var i = 0; i < 250; i++) 'l$i'].join('\n');
      expect(await MicrosoftTranslator(client, key: 'k').translate(text, 'de'), text);
      expect(calls, 3);
      final unauthorized = MockClient((_) async => http.Response('', 401));
      expect(await _fails(MicrosoftTranslator(unauthorized, key: 'k').translate('a', 'de')), tr('微软翻译密钥无效'));
      final busy = MockClient((_) async => http.Response('', 429));
      expect(await _fails(MicrosoftTranslator(busy, key: 'k').translate('a', 'de')), tr('翻译请求太频繁，请稍后再试'));
    });
  });

  group('LibreTranslator', () {
    test('request shape and line preservation', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        final q = (jsonDecode(request.body)['q'] as List).cast<String>();
        return _json({'translatedText': [for (final s in q) '译$s']});
      });
      final result = await LibreTranslator(client, server: 'https://libre.example.com/', key: 'secret').translate('a\n\nb', 'zh-CN');
      expect(result, '译a\n\n译b');
      expect(seen.url.toString(), 'https://libre.example.com/translate');
      expect(jsonDecode(seen.body), {
        'q': ['a', 'b'],
        'source': 'auto',
        'target': 'zh-Hans',
        'format': 'text',
        'api_key': 'secret',
      });
    });

    test('omits the key when empty and accepts a single string', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return _json({'translatedText': 'bonjour'});
      });
      expect(await LibreTranslator(client, server: 'http://localhost:5000').translate('hello', 'fr'), 'bonjour');
      expect((jsonDecode(seen.body) as Map).containsKey('api_key'), isFalse);
      expect(jsonDecode(seen.body)['target'], 'fr');
    });

    test('needs a http or https server', () async {
      final client = MockClient((_) async => _json({'translatedText': 'x'}));
      for (final server in ['', 'libre.example.com', 'ftp://x.com']) {
        expect(await _fails(LibreTranslator(client, server: server).translate('a', 'fr')), tr('请填写 LibreTranslate 服务器地址'));
      }
      final failing = MockClient((_) async => http.Response('', 503));
      expect(await _fails(LibreTranslator(failing, server: 'http://x.com').translate('a', 'fr')), tr('翻译服务暂时不可用（{0}）', [503]));
    });
  });

  group('AiTranslator', () {
    http.Response reply(String content) => _json({'choices': [{'message': {'role': 'assistant', 'content': content}}]});

    AiTranslator make(MockClient client, {String key = 'sk', String prompt = 'To {target}, {lines} lines.'}) =>
        AiTranslator(client, baseUrl: 'https://api.example.com/v1/', key: key, model: 'm1', prompt: prompt);

    test('request shape', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return reply('一\n二');
      });
      expect(await make(client).translate('one\ntwo', 'zh-CN'), '一\n二');
      expect(seen.url.toString(), 'https://api.example.com/v1/chat/completions');
      expect(seen.headers['Authorization'], 'Bearer sk');
      final body = jsonDecode(seen.body) as Map;
      expect(body['model'], 'm1');
      expect(body['temperature'], 0.2);
      final messages = body['messages'] as List;
      expect(messages[0], {'role': 'system', 'content': 'To ${TranslationLanguage.byCode('zh-CN').label}, 2 lines.'});
      expect(messages[1], {'role': 'user', 'content': 'one\ntwo'});
    });

    test('omits Authorization without a key and keeps empty lines in place', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return reply('一\n二');
      });
      expect(await make(client, key: '').translate('one\n\ntwo', 'zh-CN'), '一\n\n二');
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test('strips a code fence and trailing newline', () async {
      final client = MockClient((_) async => reply('```text\n一\n二\n```\n'));
      expect(await make(client).translate('one\ntwo', 'zh-CN'), '一\n二');
      expect(AiTranslator.cleanReply('```\n甲\n```'), '甲');
      expect(AiTranslator.cleanReply('甲\n\n'), '甲');
    });

    test('retries once with a note when the line count is wrong', () async {
      final bodies = <Map>[];
      final client = MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map);
        return reply(bodies.length == 1 ? '一' : '一\n二');
      });
      expect(await make(client).translate('one\ntwo', 'zh-CN'), '一\n二');
      expect(bodies.length, 2);
      final messages = bodies.last['messages'] as List;
      expect(messages.last, {'role': 'user', 'content': 'Return exactly 2 lines.'});
    });

    test('gives up after the retry', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return reply('一');
      });
      expect(await _fails(make(client).translate('one\ntwo', 'zh-CN')), tr('AI 返回的行数不对，无法对齐字幕'));
      expect(calls, 2);
    });

    test('splits long text at line ends', () async {
      final sizes = <int>[];
      final client = MockClient((request) async {
        final user = (jsonDecode(request.body)['messages'] as List)[1]['content'] as String;
        sizes.add(user.length);
        return reply(user);
      });
      final text = [for (var i = 0; i < 100; i++) 'line $i ${'x' * 90}'].join('\n');
      expect(await make(client).translate(text, 'en'), text);
      expect(sizes.length, greaterThan(1));
      expect(sizes.every((s) => s <= 3000), isTrue);
    });

    test('maps errors', () async {
      for (final entry in {
        401: tr('AI 接口密钥无效'),
        404: tr('AI 接口地址或模型名不对'),
        429: tr('翻译请求太频繁，请稍后再试'),
        500: tr('翻译服务暂时不可用（{0}）', [500]),
      }.entries) {
        final client = MockClient((_) async => http.Response('', entry.key));
        expect(await _fails(make(client).translate('a', 'en')), entry.value);
      }
    });

    test('every prompt preset keeps the line-count rule', () {
      for (final preset in AiTranslator.promptPresets) {
        expect(preset.text, contains('{target}'));
        expect(preset.text, contains('{lines}'));
        expect(preset.text, contains('exactly {lines} lines'));
      }
      expect(AiTranslator.aiPresets.map((p) => p.id), ['openai', 'deepseek', 'anthropic', 'gemini', 'qwen', 'openrouter', 'ollama', 'custom']);
    });
  });

  group('TranslationConfig', () {
    test('defaults', () {
      const config = TranslationConfig();
      expect(config.service, TranslationService.google);
      expect(config.aiPreset, 'openai');
      expect(config.promptPreset, 'subtitle');
      expect(config.effectiveAiBaseUrl, 'https://api.openai.com/v1');
      expect(config.effectiveAiModel, 'gpt-4o-mini');
      expect(config.effectivePrompt, AiTranslator.promptPresets.first.text);
    });

    test('json round trip', () {
      const config = TranslationConfig(
        service: TranslationService.ai,
        libreServer: 'http://x',
        microsoftRegion: 'r',
        aiPreset: 'deepseek',
        aiBaseUrl: 'http://proxy/v1',
        aiModel: 'm',
        promptPreset: 'custom',
        customPrompt: 'hello {target}',
      );
      final restored = TranslationConfig.fromJson(jsonDecode(jsonEncode(config.toJson())));
      expect(restored, config);
      expect(restored.hashCode, config.hashCode);
      expect(restored.effectiveAiBaseUrl, 'http://proxy/v1');
      expect(restored.effectiveAiModel, 'm');
      expect(restored.effectivePrompt, 'hello {target}');
    });

    test('tolerates missing and bad fields', () {
      expect(TranslationConfig.fromJson(null), const TranslationConfig());
      expect(TranslationConfig.fromJson('x'), const TranslationConfig());
      final config = TranslationConfig.fromJson({'service': 'nope', 'aiPreset': 3, 'promptPreset': 'zzz', 'libreServer': 7, 'aiModel': 'q'});
      expect(config.service, TranslationService.google);
      expect(config.aiPreset, 'openai');
      expect(config.promptPreset, 'subtitle');
      expect(config.libreServer, '');
      expect(config.aiModel, 'q');
    });

    test('copyWith and preset overrides', () {
      final config = const TranslationConfig().copyWith(aiPreset: 'ollama', promptPreset: 'faithful');
      expect(config.effectiveAiBaseUrl, 'http://localhost:11434/v1');
      expect(config.effectiveAiModel, 'qwen2.5');
      expect(config.effectivePrompt, AiTranslator.promptPresets.last.text);
      expect(config.copyWith(), config);
    });
  });

  group('translatorFor', () {
    final client = MockClient((_) async => http.Response('', 500));
    final fallback = GoogleTranslator(client);

    test('google gives the fallback', () {
      expect(translatorFor(const TranslationConfig(), {}, client, fallback: fallback), same(fallback));
    });

    test('a missing key gives a translator that throws', () async {
      for (final service in [TranslationService.deepl, TranslationService.microsoft, TranslationService.ai]) {
        final translator = translatorFor(TranslationConfig(service: service), {}, client, fallback: fallback);
        expect(await _fails(translator.translate('a', 'en')), tr('请先在设置里填写 {0} 的密钥', [service.label]));
        expect(await translator.translate(' ', 'en'), ' ');
      }
    });

    test('builds the configured translators', () {
      Translator build(TranslationService service, [Map<String, String> keys = const {}, String preset = 'openai']) =>
          translatorFor(TranslationConfig(service: service, aiPreset: preset), keys, client, fallback: fallback);
      expect(build(TranslationService.deepl, {'deepl': 'k'}), isA<DeepLTranslator>());
      expect(build(TranslationService.microsoft, {'microsoft': 'k'}), isA<MicrosoftTranslator>());
      expect(build(TranslationService.libre), isA<LibreTranslator>());
      expect(build(TranslationService.ai, {'ai': 'k'}), isA<AiTranslator>());
      expect(build(TranslationService.ai, {}, 'ollama'), isA<AiTranslator>());
    });

    test('chunkLengthOf', () {
      expect(chunkLengthOf(fallback), 1200);
      expect(chunkLengthOf(DeepLTranslator(client, key: 'k')), 5000);
      expect(chunkLengthOf(MicrosoftTranslator(client, key: 'k')), 5000);
      expect(chunkLengthOf(LibreTranslator(client, server: 'http://x')), 5000);
      expect(chunkLengthOf(AiTranslator(client, baseUrl: 'http://x', model: 'm', prompt: 'p')), 3000);
    });
  });

  test('TranslationService.needsKey', () {
    expect(TranslationService.google.needsKey, isFalse);
    expect(TranslationService.deepl.needsKey, isTrue);
    expect(TranslationService.libre.needsKey, isFalse);
  });
}
