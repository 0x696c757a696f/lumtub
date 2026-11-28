import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/latin_language.dart';
import 'package:lumtub/learning/wiktionary_dictionary.dart';

void main() {
  test('a Korean Basic Dictionary line carries its level and source', () {
    final entry = WiktionaryEntry.parse('가다\t\tka̠da̠\tv.\tv. 去\tv. go\t\t1\tkrdict');
    expect(entry.level, 1);
    expect(entry.source, 'krdict');
    expect(entry.chinese, ['v. 去']);
    expect(WiktionaryEntry.parse('casa\t\t\tn.\t\tn. house\t').level, 0);
  });

  test('a form finds its word', () {
    final es = WiktionaryDictionary.parse('hablar\t\taˈβlaɾ\tv.\tv. 说话\tv. to speak\\nv. to talk\t\nhablo\t\t\tv.\t\t\thablar\n', 'es');
    expect(es.lookup('hablo').map((e) => e.word), ['hablo', 'hablar']);
    expect(es.lookup('Hablar').single.chinese, ['v. 说话']);
    expect(es.lookup('hablar').single.english, ['v. to speak', 'v. to talk']);
    expect(es.lookup('nada'), isEmpty);
  });

  test('French elision looks up the word after the apostrophe', () {
    final fr = WiktionaryDictionary.parse('homme\t\tɔm\tn.\tn. 人\tn. man\t\n', 'fr');
    expect(fr.lookup("l'homme").single.word, 'homme');
    final tokens = fr.segment('C’est l’homme.');
    expect(tokens.where((t) => t.isWord).map((t) => t.key), ["C'est", "l'homme"]);
    expect(tokens.map((t) => t.text).join(), 'C’est l’homme.');
  });

  test('Korean words lose their particles and endings', () {
    final ko = WiktionaryDictionary.parse('학교\thakgyo\t\tn.\tn. 学校\tn. school\t\n가다\tgada\t\tv.\tv. 去\tv. to go\t\n하다\thada\t\tv.\t\tv. to do\t\n', 'ko');
    expect(ko.lookup('학교에서').single.word, '학교');
    expect(ko.lookup('가요').single.word, '가다');
    expect(ko.lookup('갔어요').single.word, '가다');
    expect(ko.lookup('했어요').single.word, '하다');
    expect(WiktionaryDictionary.romanizeKorean('학교'), 'hakgyo');
    expect(WiktionaryDictionary.romanizeKorean('한국어'), 'hangugeo');
    expect(WiktionaryDictionary.romanizeKorean('사랑해요'), 'saranghaeyo');
    expect(WiktionaryDictionary.romanizeKorean('2027'), isNull);
    expect(WiktionaryDictionary.romanizeKorean('20번이'), 'beoni');
    expect(ko.segment('학교에 가요').first.reading, 'hakgyoe');
  });

  test('Latin subtitles settle on their language', () {
    final guess = LatinLanguageGuess();
    const all = ['en', 'es', 'fr', 'de', 'it'];
    expect(guess.guess('¿Qué tal? Yo estoy muy bien, gracias.', all), 'es');
    expect(LatinLanguageGuess().guess("C'est la vie, je ne sais pas.", all), 'fr');
    expect(LatinLanguageGuess().guess('Ich weiß nicht, was das ist.', all), 'de');
    expect(LatinLanguageGuess().guess('Non lo so, perché è difficile.', all), 'it');
    expect(LatinLanguageGuess().guess('What is this? I don\'t know.', all), 'en');
    // One unclear line keeps the language heard so far.
    expect(guess.guess('Hola', all), 'es');
    expect(LatinLanguageGuess().guess('Okay', ['en']), 'en');
  });

  test('the next video in another language is told at once', () {
    final guess = LatinLanguageGuess();
    const all = ['en', 'es', 'fr', 'de', 'it'];
    for (final line in ['Ich habe gestern einen Film gesehen.', 'Kannst du mir bitte das Fenster aufmachen?', 'Das ist nicht so einfach.']) {
      expect(guess.guess(line, all), 'de');
    }
    expect(guess.guess("Non me ne ero accorto, ma ci siamo già visti l'anno scorso.", all), 'it');
  });

  test('a word spelled as asked comes before an acronym or a letter', () {
    final fr = WiktionaryDictionary.parse('CE\t\t\tname\t\tEC (European Community)\t\nce\t\t\tdet.\t\tthis\t\nque\t\t\tconj.\t\tthat\t', 'fr');
    expect(fr.lookup('ce').first.word, 'ce');
    expect(fr.lookup('Ce').first.word, 'ce');
    expect(fr.lookup('CE').first.word, 'CE');
    expect(fr.lookup("Qu'").first.word, 'que');
  });
}

