import 'dart:convert';

import 'lexicon.dart';
import 'word_token.dart';

/// The English pack: common English words (ECDICT's list) with their
/// phonetics and Chinese meanings from the Wiktionaries. One word a line:
/// word, phonetic, meanings (`\n` between lines), forms, exam tags,
/// Collins stars (0 now), frequency rank, English meanings (Wiktionary's,
/// else WordNet's), CEFR level and where the Chinese came from (`w`
/// Wiktionary, `d` WikDict), between tabs, where forms are ECDICT's
/// `p:ran/d:run/i:running/3:runs/0:run` and tags its `zk gk cet4`. Packs
/// built before the last columns existed still read.
class EnglishDictionary {
  EnglishDictionary(this._source);

  final LineSource _source;

  int get size => _source.size;

  /// The word list in memory, for tests and packs not moved to SQLite.
  static EnglishDictionary parse(String text) => EnglishDictionary(MemoryLines(const LineSplitter().convert(text), formsOf: formsOf));

  /// The forms a line names: ECDICT's forms field without the lemma
  /// (`0:`) and lemma kind (`1:`) parts.
  static Iterable<String> formsOf(String line) {
    final columns = line.split('\t');
    if (columns.length < 4) return const [];
    return [
      for (final part in columns[3].split('/'))
        if (part.length > 2 && part[1] == ':' && part[0] != '0' && part[0] != '1') part.substring(2),
    ];
  }

  /// The entries for [word] as written, then for the words it is a form
  /// of: `ran` gives `ran`, if listed, and `run`.
  List<EnglishEntry> lookup(String word) {
    final found = <EnglishEntry>[];
    final seen = <String>{};
    void add(String w) {
      for (final row in _source.find(w)) {
        if (seen.add(row.line)) found.add(EnglishEntry.parse(row.line));
      }
    }

    add(word);
    // A possessive or a contraction the list lacks: the word before it.
    if (found.isEmpty && word.contains("'")) add(word.substring(0, word.indexOf("'")));
    return found;
  }

  bool knows(String word) => lookup(word).isNotEmpty;

  final _levels = <String, int?>{};

  /// How hard [word] is, as an index into [EnglishLevel.values]: the
  /// first exam whose list has it or the word it is a form of, or a guess
  /// from how common it is. Null for words the pack cannot place, such as
  /// names.
  int? levelOf(String word) {
    if (_levels.containsKey(word)) return _levels[word];
    // With a capital, a word no exam lists is likely a name, not a hard
    // word: only the lists count.
    final capital = word != word.toLowerCase();
    int? best;
    for (final entry in lookup(word)) {
      final level = capital && entry.tags.isEmpty && entry.cefr.isEmpty ? null : entry.level;
      if (level != null && (best == null || level < best)) best = level;
    }
    // No exam lists it: a short form (vocab) or a word made of two
    // listed ones (skincare) is as hard as its full form or harder part,
    // not as rare as the corpus counts make it.
    if (!capital && best != null && lookup(word).every((e) => e.tags.isEmpty && e.cefr.isEmpty)) {
      final easier = _listedLevel(_clippings[word.toLowerCase()]) ?? _compoundLevel(word.toLowerCase());
      if (easier != null && easier < best) best = easier;
    }
    if (_levels.length > 20000) _levels.clear();
    return _levels[word] = best;
  }

  /// The easiest exam that lists [word] or what it is a form of.
  int? _listedLevel(String? word) {
    if (word == null) return null;
    int? best;
    for (final entry in lookup(word)) {
      final level = entry.tags.isEmpty && entry.cefr.isEmpty ? null : entry.level;
      if (level != null && (best == null || level < best)) best = level;
    }
    return best;
  }

  /// For a closed compound (skincare, weekend), the level of its harder
  /// part when both parts are on an exam list.
  int? _compoundLevel(String word) {
    if (word.length < 6 || !RegExp(r'^[a-z]+$').hasMatch(word)) return null;
    int? best;
    for (var i = 3; i <= word.length - 3; i++) {
      final first = _listedLevel(word.substring(0, i));
      final second = first == null ? null : _listedLevel(word.substring(i));
      if (first == null || second == null) continue;
      final level = first > second ? first : second;
      if (best == null || level < best) best = level;
    }
    return best;
  }

  /// Common short forms and the words they stand for.
  static const _clippings = {
    'vocab': 'vocabulary', 'info': 'information', 'app': 'application', 'apps': 'application', 'ad': 'advertisement', 'ads': 'advertisement',
    'photo': 'photograph', 'photos': 'photograph', 'exam': 'examination', 'exams': 'examination', 'lab': 'laboratory', 'labs': 'laboratory',
    'gym': 'gymnasium', 'math': 'mathematics', 'maths': 'mathematics', 'phone': 'telephone', 'fridge': 'refrigerator', 'bike': 'bicycle',
    'flu': 'influenza', 'memo': 'memorandum', 'demo': 'demonstration', 'intro': 'introduction', 'promo': 'promotion', 'specs': 'specification',
    'stats': 'statistics', 'pic': 'picture', 'pics': 'picture', 'vet': 'veterinary', 'uni': 'university', 'admin': 'administration',
    'convo': 'conversation', 'congrats': 'congratulation', 'fave': 'favourite', 'fav': 'favourite', 'prof': 'professor', 'bro': 'brother',
    'sis': 'sister', 'mic': 'microphone', 'doc': 'doctor', 'docs': 'document', 'rep': 'representative', 'reps': 'repetition', 'ref': 'referee',
    'temp': 'temperature', 'max': 'maximum', 'min': 'minimum', 'approx': 'approximately', 'etc': 'etcetera', 'tech': 'technology',
  };

  static final _word = RegExp(r"[A-Za-z]+(?:['’][A-Za-z]+)*");

  /// [text] as words and the pieces between them.
  List<WordToken> segment(String text) {
    final tokens = <WordToken>[];
    var last = 0;
    for (final m in _word.allMatches(text)) {
      if (m.start > last) tokens.add(WordToken(text.substring(last, m.start), null, isWord: false));
      final word = m[0]!;
      tokens.add(WordToken(word, null, isWord: true, lookup: word.replaceAll('’', "'")));
      last = m.end;
    }
    if (last < text.length) tokens.add(WordToken(text.substring(last), null, isWord: false));
    return tokens;
  }

  /// Whether [text] reads as English, or another language in Latin
  /// letters: mostly Latin letters and no Chinese or Japanese.
  static bool looksLatin(String text) {
    var latin = 0, other = 0;
    for (final r in text.runes) {
      if ((r >= 0x41 && r <= 0x5a) || (r >= 0x61 && r <= 0x7a)) {
        latin++;
      } else if (r >= 0x2e80 && r <= 0x9fff || r >= 0xac00 && r <= 0xd7af || r >= 0x0400 && r <= 0x06ff) {
        other++;
      }
    }
    return latin >= 2 && other == 0;
  }
}

/// The levels a learner can say they are at, easiest first, and the
/// exam word lists that mark them. [beyond] is for rare words no list has.
enum EnglishLevel {
  middleSchool(['zk'], 'Middle school', 'A2'),
  highSchool(['gk'], 'High school', 'B1'),
  cet4(['cet4'], 'CET-4', 'B1+'),
  cet6(['cet6'], 'CET-6', 'B2'),
  postgraduate(['ky'], 'Postgraduate exam', 'B2+'),
  toeflIelts(['toefl', 'ielts'], 'TOEFL / IELTS', 'C1'),
  gre(['gre'], 'GRE', 'C2'),
  beyond([], 'Rare', 'Rare');

  const EnglishLevel(this.tags, this.label, this.cefr);
  final List<String> tags;

  /// The name to translate: the Chinese exam it comes from.
  final String label;

  /// About where the exam's list ends on the CEFR scale, for learners who
  /// never sat Chinese exams. A rough guide, not an official level.
  final String cefr;

  static EnglishLevel? ofTag(String tag) {
    for (final level in values) {
      if (level.tags.contains(tag)) return level;
    }
    return null;
  }
}

class EnglishEntry {
  const EnglishEntry({required this.word, required this.phonetic, required this.meanings, required this.forms, this.tags = const [], this.collins = 0, this.rank = 0, this.english = const [], this.cefr = '', this.chineseReference = false});

  final String word;
  final String phonetic;
  /// Chinese meanings.
  final List<String> meanings;

  /// English meanings, such as `v. To move swiftly on foot.`
  final List<String> english;

  /// The CEFR level (A1–C2) the CEFR-J and Octanove lists give it; empty
  /// when they do not list it.
  final String cefr;

  /// Whether levels follow CEFR first (learners outside China) instead of
  /// Chinese exam lists. Set from the interface language.
  static bool preferCefr = false;

  /// ECDICT's forms field, as `p:ran/d:run`.
  final String forms;

  /// The exam lists that have the word, easiest first.
  final List<EnglishLevel> tags;

  /// Collins stars, 0 to 5: how common the word is in Collins' corpus.
  final int collins;

  /// Its Chinese meanings are WikDict's translations, matched by spelling
  /// rather than by sense: shown as a reference only.
  final bool chineseReference;

  /// Its frequency rank, 1 the most common; 0 unknown.
  final int rank;

  /// The first exam that lists it; otherwise a guess from its rank.
  int? get level {
    if (preferCefr && cefr.isNotEmpty) {
      return switch (cefr) {
        'A1' || 'A2' => EnglishLevel.middleSchool.index,
        'B1' => EnglishLevel.highSchool.index,
        'B2' => EnglishLevel.cet6.index,
        'C1' => EnglishLevel.toeflIelts.index,
        _ => EnglishLevel.gre.index,
      };
    }
    if (tags.isNotEmpty) return tags.first.index;
    if (rank <= 0) return null;
    if (rank < 5000) return EnglishLevel.cet4.index;
    if (rank < 10000) return EnglishLevel.postgraduate.index;
    if (rank < 20000) return EnglishLevel.gre.index;
    return EnglishLevel.beyond.index;
  }

  static EnglishEntry parse(String line) {
    final parts = line.split('\t');
    String at(int i) => i < parts.length ? parts[i] : '';
    return EnglishEntry(
      word: at(0),
      phonetic: at(1),
      meanings: at(2).split(r'\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      forms: at(3),
      tags: at(4).split(' ').map(EnglishLevel.ofTag).whereType<EnglishLevel>().toSet().toList()..sort((a, b) => a.index - b.index),
      collins: int.tryParse(at(5)) ?? 0,
      rank: int.tryParse(at(6)) ?? 0,
      english: at(7).split(r'\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      cefr: at(8),
      chineseReference: at(9) == 'd',
    );
  }

  /// The forms worth showing, such as `过去式 ran · 现在分词 running`.
  List<(String, String)> get namedForms {
    const names = {'p': 'Past', 'd': 'Past participle', 'i': 'Present participle', '3': 'Third person', 'r': 'Comparative', 't': 'Superlative', 's': 'Plural'};
    return [
      for (final part in forms.split('/'))
        if (part.length > 2 && part[1] == ':' && names.containsKey(part[0])) (names[part[0]]!, part.substring(2)),
    ];
  }
}
