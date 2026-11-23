import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// The languages the level test is made for, in the order offered.
const levelTestLanguages = ['en', 'zh', 'ja', 'ko', 'es', 'fr', 'de', 'it', 'ru'];

/// The file of [language]'s items on the learning release.
String levelTestFile(String language) => '$language-leveltest.tsv.gz';

/// One word of the test: a real word of [level], or a made-up one shaped
/// like the real words of [level].
class LevelTestItem {
  const LevelTestItem({required this.real, required this.level, required this.text, this.traditional});
  final bool real;
  final int level;
  final String text;

  /// The Chinese item in traditional characters.
  final String? traditional;

  String shown({bool traditionalChinese = false}) => traditionalChinese && traditional != null ? traditional! : text;
}

/// Every item one language's test can draw from.
class LevelTestBank {
  LevelTestBank._(this.language, this.items);

  final String language;
  final List<LevelTestItem> items;

  /// The made-up words are still checked only by the generator, not yet by
  /// native speakers.
  bool get beta => language != 'zh';

  List<int> get levels => ({for (final i in items) if (i.real) i.level}.toList()..sort());

  /// Reads a `<lang>-leveltest.tsv.gz` text: `w|n<TAB>level<TAB>text[<TAB>traditional]`
  /// lines. Lines it does not understand are skipped.
  static LevelTestBank parse(String language, String text) {
    final items = <LevelTestItem>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.startsWith('#')) continue;
      final parts = line.split('\t');
      if (parts.length < 3 || (parts[0] != 'w' && parts[0] != 'n')) continue;
      final level = int.tryParse(parts[1]);
      final word = parts[2].trim();
      if (level == null || level < 1 || level > 9 || word.isEmpty || word.length > 40) continue;
      final traditional = parts.length > 3 && parts[3].trim().isNotEmpty ? parts[3].trim() : null;
      items.add(LevelTestItem(real: parts[0] == 'w', level: level, text: word, traditional: traditional));
    }
    return LevelTestBank._(language, items);
  }

  static LevelTestBank fromBytes(String language, Uint8List gzipped) => parse(language, utf8.decode(gzip.decode(gzipped), allowMalformed: true));

  /// Whether there is enough to draw a test from.
  bool get usable {
    final levels = this.levels;
    return levels.length >= 3 && levels.every((l) => items.where((i) => i.real && i.level == l).length >= 4) && items.any((i) => !i.real);
  }

  /// One test: about [words] real words spread evenly over the levels and
  /// half as many made-up ones, each made-up word shaped like one of the
  /// real words drawn (same script, about as long), so neither tells
  /// itself apart by its look. In Chinese and Japanese no character is
  /// met twice. A new draw every time.
  List<LevelTestItem> draw(Random random, {int words = 48}) {
    final levels = this.levels;
    final perLevel = max(4, (words / levels.length).ceil());
    final usedChars = <int>{};
    final han = language == 'zh' || language == 'ja';
    bool fresh(LevelTestItem item) => !han || item.text.runes.every((r) => r < 0x4e00 || !usedChars.contains(r));
    void use(LevelTestItem item) {
      if (han) usedChars.addAll(item.text.runes.where((r) => r >= 0x4e00));
    }

    final drawn = <LevelTestItem>[];
    for (final level in levels) {
      final reals = items.where((i) => i.real && i.level == level).toList()..shuffle(random);
      final made = items.where((i) => !i.real && i.level == level).toList()..shuffle(random);
      final picked = <LevelTestItem>[];
      for (final item in reals) {
        if (picked.length >= perLevel) break;
        if (!fresh(item)) continue;
        picked.add(item);
        use(item);
      }
      drawn.addAll(picked);
      final wanted = (picked.length / 2).ceil();
      var taken = 0;
      for (final real in [...picked]..shuffle(random)) {
        if (taken >= wanted) break;
        final shape = shapeOf(real.text);
        final i = made.indexWhere((m) => shapeOf(m.text) == shape && fresh(m));
        final j = i >= 0 ? i : made.indexWhere(fresh);
        if (j < 0) break;
        final item = made.removeAt(j);
        drawn.add(item);
        use(item);
        taken++;
      }
    }
    return drawn..shuffle(random);
  }

  /// What a word looks like at a glance: its script in Japanese, its
  /// length elsewhere.
  String shapeOf(String word) {
    if (language == 'zh') return '';
    if (language == 'ja') return word.runes.any((r) => r >= 0x4e00 && r <= 0x9fff) ? 'kanji' : 'kana';
    if (language == 'ko') return '${word.length}';
    final n = word.length;
    return n <= 4 ? 's' : (n <= 6 ? 'm' : (n <= 8 ? 'l' : 'xl'));
  }
}

/// How a test went, scored the Ghent way: saying yes to made-up words
/// takes from the yeses to real ones.
class LevelTestResult {
  LevelTestResult._({required this.language, required this.known, required this.level, required this.falseAlarms, required this.score, required this.realCount, required this.madeCount});

  final String language;

  /// Each level's share of real words the learner knows, with guessing
  /// taken out: (yes rate - false alarm rate) / (1 - false alarm rate).
  final Map<int, double> known;

  /// The highest level mostly known; 0 when not even the first is.
  final int level;

  /// The share of made-up words answered yes.
  final double falseAlarms;

  /// The Ghent score as a share of the real words: yeses to real words
  /// minus yeses to made-up ones weighted by how many fewer there are.
  final double score;

  final int realCount;
  final int madeCount;

  /// Many yeses to made-up words: the learner guessed, and the level is
  /// likely too high.
  bool get unreliable => falseAlarms > 0.34;

  /// A level counts as known when, guessing taken out, at least [each] of
  /// its words are, and on average [upTo] of the words up to it.
  static const each = 0.6;
  static const upTo = 0.75;

  static LevelTestResult of(String language, List<(LevelTestItem, bool)> answers) {
    final reals = answers.where((a) => a.$1.real).toList();
    final made = answers.where((a) => !a.$1.real).toList();
    final falseYes = made.where((a) => a.$2).length;
    final f = made.isEmpty ? 0.0 : falseYes / made.length;
    final levels = {for (final a in reals) a.$1.level}.toList()..sort();
    final known = <int, double>{};
    for (final level in levels) {
      final here = reals.where((a) => a.$1.level == level).toList();
      final h = here.where((a) => a.$2).length / here.length;
      known[level] = f >= 1 ? 0 : ((h - f) / (1 - f)).clamp(0.0, 1.0);
    }
    var level = 0;
    var sum = 0.0;
    for (final (i, l) in levels.indexed) {
      sum += known[l]!;
      if (known[l]! >= each && sum / (i + 1) >= upTo) level = l;
    }
    final hits = reals.where((a) => a.$2).length;
    final ghent = reals.isEmpty ? 0.0 : ((hits - (made.isEmpty ? 0 : reals.length / made.length) * falseYes) / reals.length).clamp(0.0, 1.0);
    return LevelTestResult._(language: language, known: known, level: level, falseAlarms: f, score: ghent, realCount: reals.length, madeCount: made.length);
  }
}
