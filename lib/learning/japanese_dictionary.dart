import 'dart:convert';
import 'dart:typed_data';

import 'packed_lines.dart';

import 'word_token.dart';

/// JMdict, read from the Japanese pack. One entry a line:
/// `kanji|forms<TAB>kana|forms<TAB>v1,vs<TAB>sense\nsense<TAB>1`, the last
/// field 1 for a common word. Words are found by longest match, with
/// verb and adjective endings taken back to the dictionary form, so
/// 食べなかった finds 食べる and is read たべなかった.
class JapaneseDictionary {
  JapaneseDictionary._(this._lines);

  final PackedLines _lines;

  int get size => _lines.size;

  static const _longest = 12;

  static JapaneseDictionary parse(String text) => fromBytes(utf8.encode(text));

  /// Reads the pack's UTF-8 text: each line found by its kanji and kana
  /// forms, the first two fields.
  static JapaneseDictionary fromBytes(Uint8List bytes) =>
      JapaneseDictionary._(PackedLines.build(bytes, (start, end, key) {
        var first = start;
        while (first < end && bytes[first] != 0x09) {
          first++;
        }
        var second = first + 1;
        while (second < end && bytes[second] != 0x09) {
          second++;
        }
        if (second >= end) return;
        void forms(int from, int to) {
          var at = from;
          for (var i = from; i <= to; i++) {
            if (i == to || bytes[i] == 0x7c) {
              key(at, i);
              at = i + 1;
            }
          }
        }

        forms(start, first);
        forms(first + 1, second);
      }));

  /// The entries written [word], common ones first.
  List<JapaneseEntry> lookup(String word) {
    final found = [for (final i in _lines.linesOf(word)) JapaneseEntry.parse(_lines.line(i))];
    // Entries where [word] is the main way of writing come first, then
    // common ones; otherwise JMdict's order.
    int rank(JapaneseEntry e) =>
        ((e.kanji.isEmpty ? e.kana.first : e.kanji.first) == word ? 0 : 2) + (e.common ? 0 : 1);
    // Written in kana only, a word may be any of several kanji words read
    // alike (いっぱい: 一杯, 一敗); the one with more senses is the one
    // people mean far more often.
    final kanaOnly = found.any((e) => e.kanji.isNotEmpty && e.kana.contains(word));
    int order((int, JapaneseEntry) a, (int, JapaneseEntry) b) {
      final byRank = rank(a.$2) - rank(b.$2);
      if (byRank != 0) return byRank;
      if (kanaOnly) {
        final bySenses = b.$2.senses.length - a.$2.senses.length;
        if (bySenses != 0) return bySenses;
      }
      return a.$1 - b.$1;
    }

    final ranked = [for (final (i, e) in found.indexed) (i, e)]..sort(order);
    return [for (final (_, e) in ranked) e];
  }

  /// The dictionary forms [text] may be, with the entries for each, the
  /// form as written first.
  List<(JapaneseMatch, List<JapaneseEntry>)> lookUpInflected(String text) {
    final out = <(JapaneseMatch, List<JapaneseEntry>)>[];
    for (final match in deinflect(text)) {
      final entries = [
        for (final e in lookup(match.base))
          if (match.type == null || e.takes(match.type!)) e,
      ];
      if (entries.isNotEmpty) out.add((match, entries));
    }
    return out;
  }

  /// [text] as words and the pieces between them.
  List<WordToken> segment(String text) {
    final chars = text.runes.map(String.fromCharCode).toList();
    final tokens = <WordToken>[];
    var i = 0;
    while (i < chars.length) {
      if (!isJapanese(chars[i])) {
        final start = i;
        while (i < chars.length && !isJapanese(chars[i])) {
          i++;
        }
        tokens.add(WordToken(chars.sublist(start, i).join(), null, isWord: false));
        continue;
      }
      var end = i + _longest < chars.length ? i + _longest : chars.length;
      while (end > i && !isJapanese(chars[end - 1])) {
        end--;
      }
      WordToken? found;
      var n = _longestAt(chars, i, end);
      // A particle followed by a word reads better than a rare word that
      // swallows it: は + まだ, not はま + だ.
      if (n > 1 &&
          _particles.contains(chars[i]) &&
          !chars.sublist(i, i + n).any((c) => _isKanji(c.runes.first))) {
        final next = _longestAt(
            chars, i + 1, i + 1 + _longest < chars.length ? i + 1 + _longest : chars.length);
        if (1 + next > n) n = 1;
      }
      if (n > 0) {
        final surface = chars.sublist(i, i + n).join();
        final (match, entries) = lookUpInflected(surface).first;
        found = WordToken(surface, _readingOf(surface, match, entries.first),
            isWord: true, lookup: surface, language: 'ja');
        i += n;
      }
      if (found == null) {
        found = WordToken(chars[i], null, isWord: true, language: 'ja');
        i++;
      }
      tokens.add(found);
    }
    return tokens;
  }

  /// How many characters from [start] the longest known word takes, up
  /// to [end]; 0 for none.
  int _longestAt(List<String> chars, int start, int end) {
    for (var n = end - start; n >= 1; n--) {
      if (!isJapanese(chars[start + n - 1])) continue;
      if (lookUpInflected(chars.sublist(start, start + n).join()).isNotEmpty) return n;
    }
    return 0;
  }

  static const _particles = {'は', 'が', 'を', 'に', 'で', 'と', 'も', 'へ', 'の', 'や', 'か', 'ね', 'よ'};

  /// How the most common single kanji are read on their own.
  static const _usualReadings = {
    '人': 'ひと',
    '彼': 'かれ',
    '日': 'ひ',
    '何': 'なに',
    '方': 'ほう',
    '私': 'わたし',
    '上': 'うえ',
    '下': 'した',
    '中': 'なか',
    '間': 'あいだ',
    '後': 'あと',
    '前': 'まえ',
    '時': 'とき',
    '所': 'ところ',
    '事': 'こと',
    '物': 'もの',
    '今': 'いま',
    '目': 'め',
    '手': 'て',
    '気': 'き',
    '心': 'こころ',
    '家': 'いえ',
    '国': 'くに',
    '本': 'ほん',
    '先': 'さき',
    '外': 'そと',
    '他': 'ほか',
    '金': 'かね',
  };

  /// The kana for [surface], when it has kanji: the entry's reading with
  /// the inflected ending put back.
  String? _readingOf(String surface, JapaneseMatch match, JapaneseEntry entry) {
    if (!surface.runes.any(_isKanji)) return null;
    if (_usualReadings[surface] case final usual?) return usual;
    final base = match.base;
    var reading = entry.readingFor(base);
    // 来る is read き, こ or く by what follows it.
    if (reading != null &&
        base.endsWith('来る') &&
        reading.endsWith('くる') &&
        surface.length > base.length - 2 + 1) {
      final next = surface[base.length - 1];
      final vowel = 'たてまな'.contains(next) && next != 'な'
          ? 'き'
          : 'なよいられさ'.contains(next)
              ? 'こ'
              : 'く';
      return '${reading.substring(0, reading.length - 2)}$vowel${surface.substring(base.length - 1)}';
    }
    if (reading == null) return null;
    // The part of the word that is the same kana in both: the ending.
    var common = 0;
    while (common < base.length && common < surface.length && base[common] == surface[common]) {
      common++;
    }
    final baseTail = base.substring(common);
    if (baseTail.isNotEmpty) {
      if (!reading.endsWith(baseTail)) return reading;
      reading = reading.substring(0, reading.length - baseTail.length);
    }
    return reading + surface.substring(common);
  }

  static bool isJapanese(String char) {
    if (char.isEmpty) return false;
    final r = char.runes.first;
    return (r >= 0x3040 && r <= 0x30ff) || _isKanji(r) || r == 0x30fc || r == 0x3005;
  }

  static bool _isKanji(int r) =>
      (r >= 0x4e00 && r <= 0x9fff) ||
      (r >= 0x3400 && r <= 0x4dbf) ||
      (r >= 0x20000 && r <= 0x2ffff) ||
      r == 0x3005;

  /// Whether [text] reads as Japanese: it has kana.
  static bool looksJapanese(String text) {
    for (final r in text.runes) {
      if ((r >= 0x3040 && r <= 0x30ff) && r != 0x30fb && r != 0x30fc) return true;
    }
    return false;
  }

  /// [text] and the dictionary forms it may be inflected from, nearest
  /// first; each says which kind of word the form must be.
  static List<JapaneseMatch> deinflect(String text) {
    final out = <JapaneseMatch>[JapaneseMatch(text, null, const [])];
    final seen = <String>{text};
    for (var k = 0; k < out.length && out.length < 64; k++) {
      final current = out[k];
      for (final rule in _rules) {
        if (!current.base.endsWith(rule.from) ||
            current.base.length <= rule.from.length && rule.to.isEmpty) {
          continue;
        }
        if (rule.inType != null && current.type != null && current.type != rule.inType) continue;
        if (rule.inType != null && current.type == null && k != 0) continue;
        final base = current.base.substring(0, current.base.length - rule.from.length) + rule.to;
        if (base.isEmpty) continue;
        final key = '$base/${rule.outType}';
        if (!seen.add(key)) continue;
        out.add(JapaneseMatch(base, rule.outType, [...current.steps, rule.name]));
      }
    }
    return out;
  }

  static final List<_Rule> _rules = _makeRules();
}

class JapaneseMatch {
  const JapaneseMatch(this.base, this.type, this.steps);
  final String base;

  /// The kind of word [base] must be (`v1`, `v5`, `adj-i`, `vs`, `vk`, or
  /// the inner forms `te`, `masu`); null for the text as written.
  final String? type;
  final List<String> steps;
}

class JapaneseEntry {
  const JapaneseEntry(
      {required this.kanji,
      required this.kana,
      required this.pos,
      required this.senses,
      required this.common,
      this.chinese = const []});

  final List<String> kanji;
  final List<String> kana;
  final List<String> pos;
  final List<String> senses;
  final bool common;

  /// Meanings in Chinese, from the Chinese Wiktionary or WikDict; empty
  /// for words they lack.
  final List<String> chinese;

  String get headword => kanji.isEmpty ? kana.first : kanji.first;

  /// The kana reading for [written], one of this entry's forms.
  String? readingFor(String written) =>
      kana.contains(written) ? written : (kana.isEmpty ? null : kana.first);

  /// Whether this word inflects as [type] says.
  bool takes(String type) => switch (type) {
        'v1' => pos.any((p) => p == 'v1' || p == 'v1-s' || p == 'vk'),
        'v5' => pos.any((p) => p.startsWith('v5')),
        'adj-i' => pos.any((p) => p == 'adj-i' || p == 'adj-ix'),
        'vs-i' => pos.any((p) => p == 'vs-i' || p == 'vs-s'),
        'vs' => pos.any((p) => p.startsWith('vs')),
        'vk' => pos.contains('vk'),
        _ => false,
      };

  static JapaneseEntry parse(String line) {
    final parts = line.split('\t');
    String at(int i) => i < parts.length ? parts[i] : '';
    List<String> list(String s, String by) => s.isEmpty ? const [] : s.split(by);
    return JapaneseEntry(
      kanji: list(at(0), '|'),
      kana: list(at(1), '|'),
      pos: list(at(2), ','),
      senses: list(at(3), r'\n'),
      common: at(4) == '1',
      chinese: list(at(5), r'\n'),
    );
  }
}

class _Rule {
  const _Rule(this.from, this.to, this.inType, this.outType, this.name);
  final String from;
  final String to;

  /// The kind of word [from] ends, for a rule that applies only to a form
  /// an earlier rule found, such as ない as an adjective; null for any.
  final String? inType;
  final String outType;
  final String name;
}

List<_Rule> _makeRules() {
  final rules = <_Rule>[];
  void add(String from, String to, String? inType, String outType, String name) =>
      rules.add(_Rule(from, to, inType, outType, name));

  // Ichidan verbs: 食べ + ending.
  const v1 = {
    'た': 'past',
    'て': 'te',
    'ない': 'negative',
    'ます': 'polite',
    'ません': 'polite negative',
    'ました': 'polite past',
    'ませんでした': 'polite past negative',
    'ましょう': 'polite volitional',
    'よう': 'volitional',
    'れば': 'conditional',
    'たら': 'conditional',
    'られる': 'passive',
    'させる': 'causative',
    'たい': 'want',
    'ろ': 'imperative',
    'ず': 'negative',
    'ながら': 'while',
    'なさい': 'imperative',
    'たり': 'tari',
    'ちゃう': 'chau',
    'れる': 'potential',
  };
  for (final MapEntry(key: from, value: name) in v1.entries) {
    add(from, 'る', null, 'v1', name);
  }
  // Godan verbs by their last kana: a, i, e, o rows, past and te.
  const godan = {
    'う': ['わ', 'い', 'え', 'お', 'った', 'って'],
    'く': ['か', 'き', 'け', 'こ', 'いた', 'いて'],
    'ぐ': ['が', 'ぎ', 'げ', 'ご', 'いだ', 'いで'],
    'す': ['さ', 'し', 'せ', 'そ', 'した', 'して'],
    'つ': ['た', 'ち', 'て', 'と', 'った', 'って'],
    'ぬ': ['な', 'に', 'ね', 'の', 'んだ', 'んで'],
    'ぶ': ['ば', 'び', 'べ', 'ぼ', 'んだ', 'んで'],
    'む': ['ま', 'み', 'め', 'も', 'んだ', 'んで'],
    'る': ['ら', 'り', 'れ', 'ろ', 'った', 'って'],
  };
  for (final MapEntry(key: u, value: rows) in godan.entries) {
    final [a, i, e, o, ta, te] = rows;
    add(ta, u, null, 'v5', 'past');
    add(te, u, null, 'v5', 'te');
    add('${ta.substring(0, ta.length - 1)}${ta.endsWith('だ') ? 'だら' : 'たら'}', u, null, 'v5',
        'conditional');
    add('${ta.substring(0, ta.length - 1)}${ta.endsWith('だ') ? 'だり' : 'たり'}', u, null, 'v5',
        'tari');
    for (final (end, name) in [
      ('ない', 'negative'),
      ('ず', 'negative'),
      ('れる', 'passive'),
      ('せる', 'causative')
    ]) {
      add('$a$end', u, null, 'v5', name);
    }
    for (final (end, name) in [
      ('ます', 'polite'),
      ('ません', 'polite negative'),
      ('ました', 'polite past'),
      ('ませんでした', 'polite past negative'),
      ('ましょう', 'polite volitional'),
      ('たい', 'want'),
      ('ながら', 'while'),
      ('なさい', 'imperative'),
    ]) {
      add('$i$end', u, null, 'v5', name);
    }
    add('$eば', u, null, 'v5', 'conditional');
    add('$eる', u, null, 'v5', 'potential');
    add(e, u, null, 'v5', 'imperative');
    add('$oう', u, null, 'v5', 'volitional');
  }
  // 行く: 行った, 行って.
  add('った', 'く', null, 'v5', 'past');
  add('って', 'く', null, 'v5', 'te');
  // i-adjectives.
  for (final (from, name) in [
    ('かった', 'past'),
    ('くない', 'negative'),
    ('くなかった', 'past negative'),
    ('くて', 'te'),
    ('く', 'adverb'),
    ('ければ', 'conditional'),
    ('さ', 'noun'),
    ('そう', 'seems'),
    ('かったら', 'conditional'),
    ('すぎる', 'too'),
  ]) {
    add(from, 'い', null, 'adj-i', name);
  }
  // ない, たい and the like inflect as adjectives: 食べなかった → 食べない.
  for (final (from, name) in [
    ('かった', 'past'),
    ('くて', 'te'),
    ('ければ', 'conditional'),
    ('く', 'adverb')
  ]) {
    add('な$from', 'ない', null, 'adj-i', name);
    add('た$from', 'たい', null, 'adj-i', name);
  }
  // Helpers after the te form: 食べている → 食べて.
  for (final (from, name) in [
    ('いる', 'progressive'),
    ('る', 'progressive'),
    ('いた', 'progressive'),
    ('た', 'progressive'),
    ('います', 'progressive'),
    ('しまう', 'completed'),
    ('しまった', 'completed'),
    ('ください', 'request'),
    ('おく', 'in advance'),
    ('ある', 'resultative'),
    ('みる', 'try')
  ]) {
    add('て$from', 'て', null, 'te', name);
    add('で$from', 'で', null, 'te', name);
  }
  add('て', 'る', 'te', 'v1', 'te');
  for (final MapEntry(key: u, value: rows) in godan.entries) {
    add(rows[5], u, 'te', 'v5', 'te');
  }
  // Polite and passive forms are ichidan verbs themselves; chains such as
  // 食べられなかった take them back step by step.
  add('られる', 'る', 'v1', 'v1', 'passive');
  add('させる', 'る', 'v1', 'v1', 'causative');
  // する and 来る.
  for (final (from, name) in [
    ('した', 'past'),
    ('して', 'te'),
    ('しない', 'negative'),
    ('します', 'polite'),
    ('しました', 'polite past'),
    ('しません', 'polite negative'),
    ('しよう', 'volitional'),
    ('すれば', 'conditional'),
    ('される', 'passive'),
    ('させる', 'causative'),
    ('しろ', 'imperative'),
    ('したい', 'want'),
    ('しなかった', 'past negative'),
    ('しましょう', 'polite volitional'),
    ('したら', 'conditional'),
    ('できる', 'potential'),
  ]) {
    add(from, 'する', null, 'vs-i', name);
  }
  add('する', '', 'vs-i', 'vs', 'suru');
  add('する', '', null, 'vs', 'suru');
  for (final (from, name) in [
    ('きた', 'past'),
    ('きて', 'te'),
    ('こない', 'negative'),
    ('きます', 'polite'),
    ('きました', 'polite past'),
    ('こよう', 'volitional'),
    ('くれば', 'conditional'),
    ('こい', 'imperative'),
    ('られる', 'potential')
  ]) {
    add(from, 'くる', null, 'vk', name);
  }
  for (final (from, name) in [
    ('た', 'past'),
    ('て', 'te'),
    ('ない', 'negative'),
    ('ます', 'polite'),
    ('ました', 'polite past')
  ]) {
    add('来$from', '来る', null, 'vk', name);
  }
  return rules;
}
