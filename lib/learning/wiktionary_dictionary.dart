import 'dart:convert';

import 'lexicon.dart';
import 'word_token.dart';

/// A dictionary built from Wiktionary for one language (Korean, Spanish,
/// French, German, Italian, Russian). One word a line, between tabs:
/// word, reading, IPA, parts of speech (`|` between), Chinese meanings,
/// English meanings (a literal `\n` between meanings), and the words it is
/// a form of (`|` between).
class WiktionaryDictionary {
  WiktionaryDictionary(this.language, this._source);

  /// The language's code, such as `es`.
  final String language;
  final LineSource _source;

  int get size => _source.size;

  /// The word list in memory, for tests.
  static WiktionaryDictionary parse(String text, String language) => WiktionaryDictionary(language, MemoryLines(const LineSplitter().convert(text)));

  /// The entries for [word]: the word itself, then the words it is a form
  /// of (`hablo` gives `hablar`). Korean words carry their particles and
  /// endings, so there the longest known start counts too.
  List<WiktionaryEntry> lookup(String word) {
    final found = <WiktionaryEntry>[];
    final seen = <String>{};
    void add(String key, {bool form = false, int depth = 0}) {
      for (final row in _source.find(key)) {
        if (!seen.add(row.line)) continue;
        final entry = WiktionaryEntry.parse(row.line, form: form || row.form);
        found.add(entry);
        if (depth < 1) {
          for (final lemma in entry.lemmas) {
            add(lemma, form: true, depth: depth + 1);
          }
        }
      }
    }

    add(word);
    if (found.isEmpty && language == 'ko') {
      for (final stem in koreanStems(word)) {
        add(stem);
        if (found.isNotEmpty) break;
      }
    }
    // French l'homme, Italian dell'anno: the word after the apostrophe.
    if (found.isEmpty) {
      final apostrophe = word.lastIndexOf(RegExp("['’]"));
      if (apostrophe > 0 && apostrophe < word.length - 1) add(word.substring(apostrophe + 1));
    }
    return found;
  }

  bool knows(String word) => lookup(word).isNotEmpty;

  /// What a Korean word may be without its particle or ending, longest
  /// first: 학교에서 → 학교에, 학교; 갔어요 → 가다 by its first syllable.
  static List<String> koreanStems(String word) {
    final syllables = word.runes.toList();
    final stems = <String>[];
    for (var n = syllables.length; n >= 1; n--) {
      final start = String.fromCharCodes(syllables.take(n));
      if (n < syllables.length) stems.add(start);
      stems.add('$start다');
      // A contracted past or polite form: 갔 → 가, 했 → 하, 봤 → 보.
      final last = syllables[n - 1];
      if (_isHangul(last) && (last - 0xac00) % 28 == 20) {
        final open = last - 20;
        final base = String.fromCharCodes([...syllables.take(n - 1), open]);
        stems.add('$base다');
        const contracted = {'와': '오', '워': '우', '해': '하', '봐': '보', '줘': '주', '돼': '되', '셔': '시', '써': '쓰', '져': '지', '쳐': '치'};
        final plain = contracted[String.fromCharCode(open)];
        if (plain != null) stems.add('${String.fromCharCodes(syllables.take(n - 1))}$plain다');
      }
    }
    return stems;
  }

  static final _word = RegExp(r"[\p{L}\p{M}]+(?:['’\-][\p{L}\p{M}]+)*", unicode: true);

  /// [text] as words and the pieces between them, Korean words with
  /// their romanization above them.
  List<WordToken> segment(String text) {
    final tokens = <WordToken>[];
    var last = 0;
    for (final m in _word.allMatches(text)) {
      if (m.start > last) tokens.add(WordToken(text.substring(last, m.start), null, isWord: false, language: language));
      final word = m[0]!;
      final reading = language == 'ko' ? romanizeKorean(word) : null;
      tokens.add(WordToken(word, reading, isWord: true, lookup: word.replaceAll('’', "'"), language: language));
      last = m.end;
    }
    if (last < text.length) tokens.add(WordToken(text.substring(last), null, isWord: false, language: language));
    return tokens;
  }

  static bool _isHangul(int rune) => rune >= 0xac00 && rune <= 0xd7a3;

  static bool looksKorean(String text) => text.runes.where(_isHangul).length >= 2;

  static bool looksCyrillic(String text) => text.runes.where((r) => r >= 0x0400 && r <= 0x04ff).length >= 2;

  static const _initials = ['g', 'kk', 'n', 'd', 'tt', 'r', 'm', 'b', 'pp', 's', 'ss', '', 'j', 'jj', 'ch', 'k', 't', 'p', 'h'];
  static const _vowels = ['a', 'ae', 'ya', 'yae', 'eo', 'e', 'yeo', 'ye', 'o', 'wa', 'wae', 'oe', 'yo', 'u', 'wo', 'we', 'wi', 'yu', 'eu', 'ui', 'i'];
  static const _finals = ['', 'k', 'k', 'k', 'n', 'n', 'n', 't', 'l', 'k', 'm', 'l', 'l', 'l', 'p', 'l', 'm', 'p', 'p', 't', 't', 'ng', 't', 't', 'k', 't', 'p', 't'];

  /// Revised Romanization, syllable by syllable: 학교 → hakgyo. A final
  /// consonant before a vowel moves on (한국어 → hangugeo); other sound
  /// changes are left out.
  static String romanizeKorean(String word) {
    final runes = word.runes.toList();
    final out = StringBuffer();
    for (var i = 0; i < runes.length; i++) {
      final r = runes[i];
      if (!_isHangul(r)) {
        out.writeCharCode(r);
        continue;
      }
      final index = r - 0xac00;
      final initial = index ~/ 588, vowel = (index % 588) ~/ 28, last = index % 28;
      out.write(_initials[initial]);
      out.write(_vowels[vowel]);
      final next = i + 1 < runes.length && _isHangul(runes[i + 1]) ? runes[i + 1] - 0xac00 : null;
      if (last != 0 && next != null && next ~/ 588 == 11 && last != 21) {
        // Linked to the next vowel: the final's sound as an initial.
        const moved = {1: 'g', 2: 'kk', 4: 'n', 7: 'd', 8: 'r', 16: 'm', 17: 'b', 19: 's', 20: 'ss', 22: 'j', 23: 'ch', 24: 'k', 25: 't', 26: 'p', 27: 'h'};
        out.write(moved[last] ?? _finals[last]);
      } else {
        out.write(_finals[last]);
      }
    }
    return out.toString();
  }
}

class WiktionaryEntry {
  const WiktionaryEntry({required this.word, this.reading = '', this.ipa = '', this.pos = const [], this.chinese = const [], this.english = const [], this.lemmas = const [], this.form = false});

  final String word;

  /// A Korean word's romanization, or a Russian word with its stress.
  final String reading;
  final String ipa;
  final List<String> pos;
  final List<String> chinese;
  final List<String> english;

  /// The words this is a form of.
  final List<String> lemmas;

  /// Found as the word that what was looked up is a form of.
  final bool form;

  static WiktionaryEntry parse(String line, {bool form = false}) {
    final parts = line.split('\t');
    String at(int i) => i < parts.length ? parts[i] : '';
    List<String> lines(String text) => text.split(r'\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    List<String> list(String text) => text.split('|').where((s) => s.isNotEmpty).toList();
    return WiktionaryEntry(
      word: at(0),
      reading: at(1),
      ipa: at(2),
      pos: list(at(3)),
      chinese: lines(at(4)),
      english: lines(at(5)),
      lemmas: list(at(6)),
      form: form,
    );
  }

  bool get hasMeanings => chinese.isNotEmpty || english.isNotEmpty;
}
