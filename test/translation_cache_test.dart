import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/language_guess.dart';
import 'package:lumtub/translation.dart';
import 'package:lumtub/translation_cache.dart';

class _Counting implements Translator {
  int calls = 0;
  @override
  Future<String> translate(String text, String target) async {
    calls++;
    return '[$target] $text';
  }
}

void main() {
  test('keeps translations on disk and drops them after a week', () async {
    final dir = await Directory.systemTemp.createTemp('lumtub-cache');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/translations.json');
    var now = DateTime(2026, 10, 1);
    final inner = _Counting();
    final cache = TranslationCache(file: file, now: () => now);
    final translator = CachingTranslator(inner, cache, 'google');
    expect(await translator.translate('hi', 'ja'), '[ja] hi');
    expect(await translator.translate('hi', 'ja'), '[ja] hi');
    expect(await CachingTranslator(inner, cache, 'deepl').translate('hi', 'ja'), '[ja] hi');
    expect(inner.calls, 2, reason: 'another service translates afresh');
    await cache.save();

    final reread = TranslationCache(file: file, now: () => now);
    expect(await CachingTranslator(inner, reread, 'google').translate('hi', 'ja'), '[ja] hi');
    expect(inner.calls, 2);

    now = now.add(const Duration(days: 8));
    final stale = TranslationCache(file: file, now: () => now);
    await CachingTranslator(inner, stale, 'google').translate('hi', 'ja');
    expect(inner.calls, 3);
  });

  test('keeps at most maxEntries, dropping the oldest', () async {
    final cache = TranslationCache(maxEntries: 2);
    cache.put('s', 'en', 'a', '1');
    cache.put('s', 'en', 'b', '2');
    cache.get('s', 'en', 'a');
    cache.put('s', 'en', 'c', '3');
    expect(cache.get('s', 'en', 'b'), isNull);
    expect(cache.get('s', 'en', 'a'), '1');
  });

  test('guesses text already in the target language from its script', () {
    expect(looksLike('这个视频真不错，学到了', 'zh-CN'), isTrue);
    expect(looksLike('這個視頻真不錯，學到了', 'zh-CN'), isFalse);
    expect(looksLike('這個視頻真不錯，學到了', 'zh-TW'), isTrue);
    expect(looksLike('このビデオは本当に良かった', 'ja'), isTrue);
    expect(looksLike('このビデオは本当に良かった', 'zh-CN'), isFalse);
    expect(looksLike('이 영상 정말 좋네요', 'ko'), isTrue);
    expect(looksLike('Это видео очень хорошее', 'ru'), isTrue);
    expect(looksLike('This is a really great video, thanks!', 'en'), isTrue);
    expect(looksLike('Cette vidéo est vraiment super', 'en'), isFalse);
    expect(looksLike('Cette vidéo est vraiment super', 'fr'), isFalse);
    expect(looksLike('😂😂', 'zh-CN'), isFalse);
  });
}
