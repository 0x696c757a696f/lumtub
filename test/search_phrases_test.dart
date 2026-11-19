import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/explore_filters.dart';
import 'package:lumtub/explore_topics.dart';
import 'package:lumtub/faith_topics.dart';
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

  test('bundled phrases are used before the disk and the translator', () async {
    final fake = _Fake();
    final phrases = SearchPhrases(fake, bundled: () async => '{"phrases": ["sports", "chess"], "it": ["sport", ""]}');
    expect(await phrases.translate(['sports', 'chess'], 'it'), {'sports': 'sport', 'chess': 'it:chess'});
    expect(fake.asked, ['chess']);
  });

  test('the phrase list the bundle is made from has every phrase the zones search', () {
    final listed = File('.github/search_phrases/phrases.txt').readAsLinesSync().toSet();
    final missing = <String>{};
    void add(String query) {
      for (final w in searchPhrasesOf(englishSearchOf(query))) {
        if (translatesInto(w, ExploreLanguage.it) && searchGlossary[w] == null && !listed.contains(w)) missing.add(w);
      }
    }

    void sub(ExploreSub s) {
      add(s.query);
      s.subs.forEach(sub);
    }

    for (final f in <WordFilter>[...ContentFormat.values, ...ContentView.values, ...FaithFormat.values, ...FaithView.values]) {
      if (f.words.isNotEmpty) add(f.words);
    }
    for (final section in ExploreSection.values) {
      for (final topic in exploreTopicsOf(section)) {
        add(topic.query);
        topic.subs.forEach(sub);
      }
    }
    // Add them to .github/search_phrases/phrases.txt; the Search phrases
    // workflow then translates them into assets/search_phrases.json.
    expect(missing, isEmpty);
  });

  test('the bundled file has every listed phrase in every language', () async {
    final fake = _Fake();
    final phrases = SearchPhrases(fake, bundled: () async => File('assets/search_phrases.json').readAsStringSync());
    final listed = File('.github/search_phrases/phrases.txt').readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
    for (final language in File('.github/search_phrases/languages.txt').readAsLinesSync().where((l) => l.isNotEmpty)) {
      expect((await phrases.translate(listed, language)).length, listed.length, reason: language);
    }
    expect(fake.asked, isEmpty);
    expect((await phrases.translate(['sports'], 'it'))['sports'], 'sport');
  });
}
