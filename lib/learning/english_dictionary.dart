import 'dart:convert';

import 'word_token.dart';

/// The English pack: common English words with their phonetics and
/// Chinese meanings, from ECDICT. One word a line:
/// `word<TAB>phonetic<TAB>meanings, \n between lines<TAB>forms`, where
/// forms are ECDICT's `p:ran/d:run/i:running/3:runs/0:run`.
class EnglishDictionary {
  EnglishDictionary._(this._lines, this._index, this._forms);

  final List<String> _lines;
  final Map<String, int> _index;

  /// Each inflected form, lower case, to the words it comes from.
  final Map<String, List<String>> _forms;

  int get size => _lines.length;

  static EnglishDictionary parse(String text) {
    final lines = <String>[];
    final index = <String, int>{};
    final forms = <String, List<String>>{};
    for (final line in const LineSplitter().convert(text)) {
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      final word = line.substring(0, tab);
      final at = lines.length;
      lines.add(line);
      index.putIfAbsent(word, () => at);
      index.putIfAbsent(word.toLowerCase(), () => at);
      final last = line.lastIndexOf('\t');
      if (last > tab) {
        for (final part in line.substring(last + 1).split('/')) {
          final colon = part.indexOf(':');
          if (colon < 0 || part.startsWith('0:') || part.startsWith('1:')) continue;
          final form = part.substring(colon + 1).toLowerCase();
          if (form.isEmpty || form == word.toLowerCase()) continue;
          final list = forms[form] ??= [];
          if (!list.contains(word)) list.add(word);
        }
      }
    }
    return EnglishDictionary._(lines, index, forms);
  }

  /// The entries for [word] as written, then for the words it is a form
  /// of: `ran` gives `ran`, if listed, and `run`.
  List<EnglishEntry> lookup(String word) {
    final found = <EnglishEntry>[];
    final seen = <int>{};
    void add(String w) {
      final at = _index[w] ?? _index[w.toLowerCase()];
      if (at != null && seen.add(at)) found.add(EnglishEntry.parse(_lines[at]));
    }

    add(word);
    for (final base in _forms[word.toLowerCase()] ?? const <String>[]) {
      add(base);
    }
    // A possessive or a contraction the list lacks: the word before it.
    if (found.isEmpty && word.contains("'")) add(word.substring(0, word.indexOf("'")));
    return found;
  }

  bool knows(String word) => lookup(word).isNotEmpty;

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

class EnglishEntry {
  const EnglishEntry({required this.word, required this.phonetic, required this.meanings, required this.forms});

  final String word;
  final String phonetic;
  final List<String> meanings;

  /// ECDICT's forms field, as `p:ran/d:run`.
  final String forms;

  static EnglishEntry parse(String line) {
    final parts = line.split('\t');
    String at(int i) => i < parts.length ? parts[i] : '';
    return EnglishEntry(
      word: at(0),
      phonetic: at(1),
      meanings: at(2).split(r'\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      forms: at(3),
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
