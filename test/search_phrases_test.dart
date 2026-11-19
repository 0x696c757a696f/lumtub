import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/search_phrases.dart';
import 'package:lumtub/translation.dart';

class _Fake implements Translator {
  final asked = <String>[];
  bool refuse = false;

  @override
  Future<String> translate(String text, String target) async {
    asked.add(text);
    if (refuse) throw TranslationException.busy();
    return text.split('\n').map((l) => '$target:$l').join('\n');
  }
}

void main() {
  test('phrases are asked together once per language and kept on disk', () async {
    final dir = Directory.systemTemp.createTempSync('phrases');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/search_phrases.json');
    final fake = _Fake();
    final phrases = SearchPhrases(fake, file: file);
    expect(await phrases.translate(['sports', 'painting', 'sports'], 'it'), {'sports': 'it:sports', 'painting': 'it:painting'});
    expect(fake.asked, ['sports\npainting']);
    await phrases.translate(['sports', 'chess'], 'it');
    expect(fake.asked.last, 'chess');
    // Another start reads them back, and asks nothing while refused.
    final again = _Fake()..refuse = true;
    Object? why;
    final back = await SearchPhrases(again, file: file).translate(['sports', 'chess', 'cooking'], 'it', failure: (e) => why = e);
    expect(back, {'sports': 'it:sports', 'chess': 'it:chess'});
    expect(again.asked, ['cooking']);
    expect(why, isA<TranslationException>());
  });

  test('many phrases go in requests of at most linesPerRequest lines', () async {
    final fake = _Fake();
    final words = [for (var i = 0; i < 70; i++) 'w$i'];
    final out = await SearchPhrases(fake).translate(words, 'es');
    expect(out.length, 70);
    expect(fake.asked.map((a) => a.split('\n').length), [30, 30, 10]);
  });
}
