import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/app_preferences.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/subtitle_translation.dart';
import 'package:lumtub/translation.dart';
import 'package:lumtub/translation_services.dart';
import 'package:lumtub/ui/translatable.dart';

class _Fake implements Translator {
  int calls = 0;
  bool fail = false;
  @override
  Future<String> translate(String text, String target) async {
    calls++;
    if (fail) throw const TranslationException('出错了');
    return '[$target] $text';
  }
}

void main() {
  test('reads the endpoint reply and joins its segments', () {
    expect(GoogleTranslator.parseResponse('[[["你好，","Hello, ",null],["世界\\n","world\\n"]],null,"en"]'), '你好，世界\n');
    expect(() => GoogleTranslator.parseResponse('<html>'), throwsA(isA<TranslationException>()));
  });

  test('splits long text at line ends so that the pieces join back', () {
    final text = List.generate(30, (i) => 'line number $i').join('\n');
    final chunks = GoogleTranslator.splitText(text, max: 100);
    expect(chunks.length, greaterThan(1));
    expect(chunks.every((c) => c.length <= 100), isTrue);
    expect(chunks.join(), text);
    expect(GoogleTranslator.splitText('x' * 250, max: 100).join(), 'x' * 250);
  });

  test('asks the endpoint with the target language and caches the answer', () async {
    final requests = <Uri>[];
    final translator = GoogleTranslator(MockClient((request) async {
      requests.add(request.url);
      return http.Response('[[["你好","hello"]]]', 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }), cacheSize: 2);
    expect(await translator.translate('hello', 'zh-CN'), '你好');
    expect(await translator.translate('hello', 'zh-CN'), '你好');
    expect(requests, hasLength(1));
    expect(requests.single.host, 'translate.googleapis.com');
    expect(requests.single.queryParameters, {'client': 'gtx', 'sl': 'auto', 'tl': 'zh-CN', 'dt': 't', 'q': 'hello'});
    // The oldest of three entries is dropped from a cache of two.
    await translator.translate('a', 'zh-CN');
    await translator.translate('hello', 'zh-CN');
    await translator.translate('b', 'zh-CN');
    expect(requests, hasLength(3));
    await translator.translate('hello', 'zh-CN');
    expect(requests, hasLength(3));
    await translator.translate('a', 'zh-CN');
    expect(requests, hasLength(4));
  });

  test('turns failures into short messages', () async {
    expect(GoogleTranslator(MockClient((_) async => http.Response('', 429))).translate('x', 'en'), throwsA(isA<TranslationException>()));
    expect(GoogleTranslator(MockClient((_) async => throw http.ClientException('offline'))).translate('x', 'en'), throwsA(isA<TranslationException>()));
  });

  test('the target language is saved and unknown codes fall back', () {
    final prefs = const AppPreferences().copyWith(translateLanguage: 'ja');
    expect(AppPreferences.fromJson(prefs.toJson()).translateLanguage, 'ja');
    expect(AppPreferences.fromJson({'translateLanguage': 'xx'}).translateLanguage, '');
    // Empty follows Windows; the old default, saved before, follows it too.
    expect(const AppPreferences().translateLanguage, '');
    expect(AppPreferences.fromJson({'translateLanguage': TranslationLanguage.defaultCode}).translateLanguage, '');
    final chosen = const AppPreferences().copyWith(translateLanguage: 'zh-CN');
    expect(AppPreferences.fromJson(chosen.toJson()).translateLanguage, 'zh-CN');
    expect(AppPreferences.fromJson(const AppPreferences().toJson()).bilingualTranslation, isTrue);
  });

  test('translated subtitles use a listed track or translate the original', () {
    const en = SubtitleOption(language: 'en', name: 'English', url: 'https://yt.example/api/timedtext?v=1&lang=en&fmt=vtt', kind: SubtitleKind.automatic);
    const zh = SubtitleOption(language: 'zh-Hans', name: 'Chinese', url: 'https://yt.example/zh.vtt', kind: SubtitleKind.translated);
    final target = TranslationLanguage.byCode('zh-CN');
    expect(translationOf([en, zh], target), zh);
    final derived = translationOf([en], target)!;
    expect(derived.kind, SubtitleKind.translated);
    expect(derived.language, 'zh-Hans');
    expect(Uri.parse(derived.url).queryParameters, {'v': '1', 'lang': 'en', 'fmt': 'vtt', 'tlang': 'zh-Hans'});
    // Nothing to translate when the only subtitle is already in the target language.
    expect(translationOf([const SubtitleOption(language: 'zh-Hans', name: '', url: 'https://yt.example/a.vtt')], target), isNull);
    expect(translationOf(const [], target), isNull);
  });

  test('tells languages apart by script and finds the second subtitle', () {
    final simplified = TranslationLanguage.byCode('zh-CN');
    final traditional = TranslationLanguage.byCode('zh-TW');
    final english = TranslationLanguage.byCode('en');
    expect(['zh', 'zh-Hans', 'zh_CN', 'chi'].every((t) => speaks(t, simplified)), isTrue);
    expect(speaks('zh-Hant', simplified), isFalse);
    expect(speaks('zh-HK', traditional), isTrue);
    expect(speaks('en-GB', english), isTrue);
    expect(speaks('eng', english), isFalse);
    expect(speaks(null, english), isFalse);

    const ja = SubtitleOption(language: 'ja', name: '', url: 'https://yt.example/api/timedtext?v=1&lang=ja', kind: SubtitleKind.automatic);
    const enAuto = SubtitleOption(language: 'en', name: '', url: 'https://yt.example/en-auto.vtt', kind: SubtitleKind.automatic);
    const enOwn = SubtitleOption(language: 'en-US', name: '', url: 'https://yt.example/en.vtt');
    expect(subtitleIn([ja, enAuto, enOwn], english), enOwn);
    expect(subtitleIn([ja, enAuto], english), enAuto);
    final translated = subtitleIn([ja], english)!;
    expect((translated.kind, Uri.parse(translated.url).queryParameters['tlang']), (SubtitleKind.translated, 'en'));
  });

  test('finds the subtitle in the language the video is spoken in', () {
    const jaAuto = SubtitleOption(language: 'ja', name: '', url: 'https://yt.example/ja-auto.vtt', kind: SubtitleKind.automatic);
    const jaOwn = SubtitleOption(language: 'ja-JP', name: '', url: 'https://yt.example/ja.vtt');
    const enOwn = SubtitleOption(language: 'en', name: '', url: 'https://yt.example/en.vtt');
    expect(originalSubtitle([enOwn, jaAuto, jaOwn]), jaOwn);
    expect(originalSubtitle([enOwn, jaAuto]), jaAuto);
    expect(originalSubtitle([enOwn]), enOwn);
    expect(originalSubtitle(const []), isNull);
    expect(sameLanguage('zh', 'zh-Hans'), isTrue);
    expect(sameLanguage('zh-Hans', 'zh-Hant'), isFalse);
    expect(sameLanguage('en-US', 'en'), isTrue);
    expect(sameLanguage(null, null), isFalse);
    final simplified = TranslationLanguage.byCode('zh-CN');
    expect(hasOwnSubtitle([enOwn, jaAuto], simplified), isFalse);
    expect(hasOwnSubtitle([const SubtitleOption(language: 'zh-Hans', name: '', url: 'https://yt.example/zh.vtt', kind: SubtitleKind.automatic)], simplified), isTrue);
  });

  test('the translation service settings are saved', () {
    final prefs = const AppPreferences().copyWith(
      translation: const TranslationConfig(service: TranslationService.ai, aiPreset: 'deepseek', promptPreset: 'natural'),
      subtitlesByService: true,
    );
    final read = AppPreferences.fromJson(prefs.toJson());
    expect(read.translation, prefs.translation);
    expect(read.subtitlesByService, isTrue);
    expect(AppPreferences.fromJson({}).translation.service, TranslationService.google);
  });

  testWidgets('translates on tap, shows the original again and reports errors', (tester) async {
    final fake = _Fake();
    final controller = AppController()..translator = fake;
    controller.preferences = controller.preferences.copyWith(translateLanguage: 'zh-CN');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Translatable(controller: controller, text: 'Hello', builder: (context, text) => Text(text)))));
    expect(find.text('Hello'), findsOneWidget);
    expect(fake.calls, 0);
    // 双语对照 (the default) keeps the original above the translation.
    await tester.tap(find.text('翻译'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('[zh-CN] Hello'), findsOneWidget);
    await tester.tap(find.text('隐藏译文'));
    await tester.pump();
    expect(find.text('[zh-CN] Hello'), findsNothing);
    expect(fake.calls, 1);
    fake.calls = 0;
    controller.preferences = controller.preferences.copyWith(bilingualTranslation: false);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Translatable(key: const ValueKey('replace'), controller: controller, text: 'Hello', builder: (context, text) => Text(text)))));
    await tester.tap(find.text('翻译'));
    await tester.pump();
    await tester.pump();
    expect(find.text('[zh-CN] Hello'), findsOneWidget);
    await tester.tap(find.text('显示原文'));
    await tester.pump();
    expect(find.text('Hello'), findsOneWidget);
    // Showing the translation again does not ask a second time.
    await tester.tap(find.text('翻译'));
    await tester.pump();
    expect(find.text('[zh-CN] Hello'), findsOneWidget);
    expect(fake.calls, 1);

    final failing = _Fake()..fail = true;
    controller.translator = failing;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Translatable(key: const ValueKey('b'), controller: controller, text: 'Other', builder: (context, text) => Text(text)))));
    await tester.tap(find.text('翻译'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('出错了'), findsOneWidget);
  });
}
