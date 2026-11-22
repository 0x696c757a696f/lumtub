import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../l10n/l10n.dart';

/// The levels a learner of one language can say they are at, easiest
/// first: HSK for Chinese, JLPT for Japanese, the Korean Basic
/// Dictionary's three for Korean, and about CEFR, from how often words
/// are used, for the others.
enum LevelScale {
  hsk(['HSK 1', 'HSK 2', 'HSK 3', 'HSK 4', 'HSK 5', 'HSK 6', 'HSK 7–9'], official: true),
  jlpt(['N5', 'N4', 'N3', 'N2', 'N1'], official: true),
  korean(['Beginner', 'Intermediate', 'Advanced'], official: true),
  cefr(['A1', 'A2', 'B1', 'B2', 'C1', 'C2'], official: false);

  const LevelScale(this.names, {required this.official});
  final List<String> names;

  /// From an exam's own lists; otherwise a guide from word frequency.
  final bool official;

  /// The name of level [level], 1 the easiest.
  String nameOf(int level) {
    final name = names[(level - 1).clamp(0, names.length - 1)];
    if (this == korean) return tr(name);
    return official ? name : '≈ $name';
  }

  int get top => names.length;

  static LevelScale? of(String language) => switch (language) {
        'zh' => hsk,
        'ja' => jlpt,
        'ko' => korean,
        'es' || 'fr' || 'de' || 'it' || 'ru' => cefr,
        _ => null,
      };
}

/// The level of each word of one language, from `<lang>-levels.tsv.gz`:
/// `word<TAB>level` lines, level 1 the easiest.
class WordLevels {
  WordLevels._(this._levels);

  final Map<String, int> _levels;

  int get length => _levels.length;

  /// [word]'s level, by its spelling and then lower-cased; null when no
  /// list has it.
  int? of(String word) => _levels[word] ?? _levels[word.toLowerCase()];

  /// For a Chinese word no list has (这个, 经济发展): the level of its
  /// hardest part, cutting it into the longest listed words from the
  /// left; null unless every part is listed.
  int? ofParts(String word) {
    if (word.length < 2 || word.length > 12) return null;
    var hardest = 0;
    var at = 0;
    while (at < word.length) {
      int? found;
      var end = word.length;
      for (; end > at; end--) {
        found = _levels[word.substring(at, end)];
        if (found != null) break;
      }
      if (found == null) return null;
      if (found > hardest) hardest = found;
      at = end;
    }
    return hardest;
  }

  /// Reads the text of a levels file. Lines that are not `word<TAB>1..9`
  /// are skipped, so a damaged file gives fewer levels, never an error.
  static WordLevels parse(String text) {
    final levels = <String, int>{};
    for (final line in const LineSplitter().convert(text)) {
      final tab = line.indexOf('\t');
      if (tab <= 0 || tab > 64 || line.length != tab + 2) continue;
      final level = line.codeUnitAt(tab + 1) - 0x30;
      if (level < 1 || level > 9) continue;
      levels[line.substring(0, tab)] = level;
    }
    return WordLevels._(levels);
  }

  static WordLevels fromBytes(Uint8List gzipped) => parse(utf8.decode(gzip.decode(gzipped), allowMalformed: true));

  /// Reads [file] away from the window's thread.
  static Future<WordLevels> read(File file) async {
    final path = file.path;
    return Isolate.run(() => fromBytes(File(path).readAsBytesSync()));
  }
}
