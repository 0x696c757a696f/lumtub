import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/translation.dart';
import 'package:lumtub/translation_cache.dart';

class _Upper implements Translator {
  final asked = <String>[];
  bool joinLines = false;

  @override
  Future<String> translate(String text, String target) async {
    asked.add(text);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final out = text.toUpperCase();
    return joinLines ? out.replaceAll('\n', ' ') : out;
  }
}

void main() {
  test('short lines asked together go out as one request and come back split', () async {
    final inner = _Upper();
    final translator = CachingTranslator(inner, TranslationCache(), 'test', batch: true);
    final results = await Future.wait([for (final t in ['one', 'two', 'three']) translator.translate(t, 'en')]);
    expect(results, ['ONE', 'TWO', 'THREE']);
    expect(inner.asked, ['one\ntwo\nthree']);
    expect(await translator.translate('two', 'en'), 'TWO');
    expect(inner.asked, hasLength(1));
  });

  test('the same text asked twice while in flight is sent once', () async {
    final inner = _Upper();
    final translator = CachingTranslator(inner, TranslationCache(), 'test');
    final both = await Future.wait([translator.translate('a\nb', 'en'), translator.translate('a\nb', 'en')]);
    expect(both, ['A\nB', 'A\nB']);
    expect(inner.asked, ['a\nb']);
  });

  test('an answer that loses the line breaks is asked again line by line', () async {
    final inner = _Upper()..joinLines = true;
    final translator = CachingTranslator(inner, TranslationCache(), 'test', batch: true);
    final results = await Future.wait([translator.translate('x', 'en'), translator.translate('y', 'en')]);
    expect(results, ['X', 'Y']);
    expect(inner.asked, ['x\ny', 'x', 'y']);
  });

  test('without batching each text goes alone', () async {
    final inner = _Upper();
    final translator = CachingTranslator(inner, TranslationCache(), 'test');
    await Future.wait([translator.translate('p', 'en'), translator.translate('q', 'en')]);
    expect(inner.asked, ['p', 'q']);
  });
}
