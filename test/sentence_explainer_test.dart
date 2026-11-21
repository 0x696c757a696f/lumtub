import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/learning/sentence_explainer.dart';

const _reply = '{"translation": "你在开玩笑吧", "meaning": "表示惊讶，不太相信。", "grammar": ["You\'ve got to be: 口语里的 must be"], '
    '"why": "很随意的口语。", "alternatives": [{"text": "No way!", "note": "更短"}], "mistakes": ["别说 You have to joke"], '
    '"words": [{"word": "kidding", "reading": "/ˈkɪdɪŋ/", "meaning": "开玩笑"}]}';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('explain'));
  tearDown(() async => dir.delete(recursive: true));

  test('reads the JSON answer, also inside a code fence after reasoning', () {
    final answer = SentenceExplanation.parse('<think>hmm</think>```json\n$_reply\n```');
    expect(answer.translation, '你在开玩笑吧');
    expect(answer.grammar, hasLength(1));
    expect(answer.others.single.text, 'No way!');
    expect(answer.words.single.reading, '/ˈkɪdɪŋ/');
    expect(answer.text, isEmpty);
    expect(answer.plain, contains('No way!'));
  });

  test('keeps a non-JSON answer as text', () {
    final answer = SentenceExplanation.parse('It means he is surprised.');
    expect(answer.text, 'It means he is surprised.');
    expect(answer.plain, 'It means he is surprised.');
  });

  test('asks the own service once, then answers from the cache', () async {
    final explainer = SentenceExplainer(cache: dir, client: MockClient((_) async => http.Response('', 404)));
    var asked = 0;
    String? system;
    Future<String> complete(String s, String user) async {
      asked++;
      system = s;
      expect(user, contains("You've got to be kidding"));
      expect(user, contains('Before:\nWhat?'));
      return _reply;
    }

    final first = await explainer.explain("You've got to be kidding", language: 'Simplified Chinese', before: ['What?'], complete: complete);
    final again = await explainer.explain("You've got to be kidding", language: 'Simplified Chinese', before: ['What?'], complete: complete);
    expect(asked, 1);
    expect(system, contains('Simplified Chinese'));
    expect(again.translation, first.translation);
    await explainer.explain("You've got to be kidding", language: 'Simplified Chinese', before: ['What?'], complete: complete, fresh: true);
    expect(asked, 2);
  });

  test('without its own service it asks the helper with the pass', () async {
    Map<String, dynamic>? sent;
    final explainer = SentenceExplainer(
      cache: dir,
      client: MockClient((request) async {
        if (request.url.path.endsWith('ai-server.txt')) return http.Response('https://helper.example\n', 200);
        expect(request.url.toString(), 'https://helper.example/explain');
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(utf8.encode(jsonEncode({'explanation': jsonDecode(_reply), 'left': 29})), 200);
      }),
    );
    final answer = await explainer.explain('Hi', language: 'Simplified Chinese', pass: (device: 'd' * 32, code: 'c' * 32, receipt: 'LA1.x.y'));
    expect(answer.meaning, '表示惊讶，不太相信。');
    expect(sent!['code'], 'c' * 32);
    expect(sent!['receipt'], 'LA1.x.y');
  });

  test('the helper being off or out of lines says so', () async {
    var error = 'limit';
    final explainer = SentenceExplainer(
      cache: dir,
      client: MockClient((request) async {
        if (request.url.path.endsWith('ai-server.txt')) return http.Response('https://helper.example', 200);
        return http.Response(jsonEncode({'error': error, 'max': 30}), 429);
      }),
    );
    const pass = (device: 'dddddddddddddddddddddddddddddddd', code: '', receipt: '');
    await expectLater(explainer.explain('A', language: 'Simplified Chinese', pass: pass), throwsA(isA<ExplainException>().having((e) => e.limit, 'limit', true)));
    error = 'trial';
    await expectLater(explainer.explain('B', language: 'Simplified Chinese', pass: pass), throwsA(isA<ExplainException>().having((e) => e.needsPack, 'needsPack', true)));
  });

  test('no helper published and no own service asks for a key', () async {
    final explainer = SentenceExplainer(cache: dir, client: MockClient((_) async => http.Response('Not Found', 404)));
    await expectLater(explainer.explain('A', language: 'Simplified Chinese', pass: (device: 'd' * 32, code: '', receipt: '')), throwsA(isA<ExplainException>()));
  });
}
