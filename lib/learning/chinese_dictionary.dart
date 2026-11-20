import 'dart:convert';

import 'word_token.dart';

export 'word_token.dart';

/// CC-CEDICT, read from the Chinese pack: words by both their
/// simplified and traditional forms, splitting a line into words, and
/// pinyin with tone marks.
class ChineseDictionary {
  ChineseDictionary._(this._lines, this._index, this.longest);

  final List<String> _lines;
  final Map<String, List<int>> _index;

  /// The most characters any word has, capped: no subtitle word is longer.
  final int longest;

  int get size => _lines.length;

  /// Reads CC-CEDICT's text: `傳統 传统 [chuan2 tong3] /tradition/...`.
  static ChineseDictionary parse(String text) {
    final lines = <String>[];
    final index = <String, List<int>>{};
    var longest = 1;
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final firstSpace = line.indexOf(' ');
      final secondSpace = firstSpace < 0 ? -1 : line.indexOf(' ', firstSpace + 1);
      if (secondSpace < 0 || !line.contains('[', secondSpace)) continue;
      final traditional = line.substring(0, firstSpace);
      final simplified = line.substring(firstSpace + 1, secondSpace);
      final at = lines.length;
      lines.add(line);
      (index[simplified] ??= []).add(at);
      if (traditional != simplified) (index[traditional] ??= []).add(at);
      final count = simplified.runes.length;
      if (count > longest) longest = count;
    }
    return ChineseDictionary._(lines, index, longest.clamp(1, 8));
  }

  /// Every entry for [word], in either script.
  List<ChineseEntry> lookup(String word) => [for (final i in _index[word] ?? const <int>[]) ChineseEntry.parse(_lines[i])];

  bool contains(String word) => _index.containsKey(word);

  /// The usual reading of [word], with tone marks: a common particle or
  /// character is read as it mostly is, otherwise the first entry that
  /// is not a name.
  String? readingOf(String word) {
    final usual = _usualReadings[word];
    if (usual != null) return pinyinMarks(usual);
    final found = _index[word];
    if (found == null) return null;
    String? first;
    for (final i in found) {
      final pinyin = ChineseEntry.pinyinOf(_lines[i]);
      first ??= pinyin;
      if (pinyin.isNotEmpty && pinyin[0] == pinyin[0].toLowerCase()) return pinyinMarks(pinyin);
    }
    return first == null ? null : pinyinMarks(first);
  }

  /// [text] as words and the pieces between them. Both directions of
  /// longest matching are tried; the split with fewer pieces wins, then
  /// the one with fewer lone characters, then the backward one, which
  /// suits Chinese better.
  List<WordToken> segment(String text) {
    final chars = text.runes.map(String.fromCharCode).toList();
    final tokens = <WordToken>[];
    var i = 0;
    while (i < chars.length) {
      if (!isHan(chars[i])) {
        final start = i;
        while (i < chars.length && !isHan(chars[i])) {
          i++;
        }
        tokens.add(WordToken(chars.sublist(start, i).join(), null, isWord: false));
        continue;
      }
      final start = i;
      while (i < chars.length && isHan(chars[i])) {
        i++;
      }
      for (final word in _split(chars.sublist(start, i))) {
        tokens.add(WordToken(word, readingOf(word) ?? _charsReading(word), isWord: true));
      }
    }
    return tokens;
  }

  /// A word the dictionary lacks, read character by character.
  String? _charsReading(String word) {
    final parts = [for (final c in word.runes.map(String.fromCharCode)) readingOf(c)];
    return parts.every((p) => p == null) ? null : parts.map((p) => p ?? '').join(' ');
  }

  List<String> _split(List<String> run) {
    final forward = <String>[];
    var i = 0;
    while (i < run.length) {
      var n = longest < run.length - i ? longest : run.length - i;
      while (n > 1 && !_index.containsKey(run.sublist(i, i + n).join())) {
        n--;
      }
      forward.add(run.sublist(i, i + n).join());
      i += n;
    }
    final backward = <String>[];
    var end = run.length;
    while (end > 0) {
      var n = longest < end ? longest : end;
      while (n > 1 && !_index.containsKey(run.sublist(end - n, end).join())) {
        n--;
      }
      backward.insert(0, run.sublist(end - n, end).join());
      end -= n;
    }
    if (forward.length != backward.length) return forward.length < backward.length ? forward : backward;
    int singles(List<String> words) => words.where((w) => w.runes.length == 1).length;
    return singles(forward) < singles(backward) ? forward : backward;
  }

  /// Whether [text] reads as Chinese: it has Chinese characters and no
  /// Japanese kana.
  static bool looksChinese(String text) {
    var han = false;
    for (final r in text.runes) {
      if ((r >= 0x3040 && r <= 0x30ff) || (r >= 0x31f0 && r <= 0x31ff)) return false;
      if (!han && _isHanRune(r)) han = true;
    }
    return han;
  }

  static bool isHan(String char) => char.isNotEmpty && _isHanRune(char.runes.first);

  static bool _isHanRune(int r) =>
      (r >= 0x4e00 && r <= 0x9fff) || (r >= 0x3400 && r <= 0x4dbf) || (r >= 0x20000 && r <= 0x323af) || (r >= 0xf900 && r <= 0xfaff) || r == 0x3007;

  /// How the most common characters with more than one reading are
  /// usually read, which the dictionary cannot tell without context.
  static const _usualReadings = {
    '了': 'le5', '的': 'de5', '得': 'de5', '地': 'de5', '着': 'zhe5', '著': 'zhe5', '都': 'dou1', '还': 'hai2', '還': 'hai2',
    '和': 'he2', '为': 'wei4', '為': 'wei4', '行': 'xing2', '长': 'chang2', '長': 'chang2', '只': 'zhi3', '要': 'yao4',
    '会': 'hui4', '會': 'hui4', '种': 'zhong3', '種': 'zhong3', '重': 'zhong4', '便': 'bian4', '觉': 'jue2', '覺': 'jue2',
    '看': 'kan4', '好': 'hao3', '少': 'shao3', '没': 'mei2', '沒': 'mei2', '说': 'shuo1', '說': 'shuo1', '一': 'yi1', '不': 'bu4',
    '个': 'ge4', '個': 'ge4', '们': 'men5', '們': 'men5', '吗': 'ma5', '嗎': 'ma5', '呢': 'ne5', '吧': 'ba5', '么': 'me5',
    '麼': 'me5', '这': 'zhe4', '這': 'zhe4', '那': 'na4', '哪': 'na3', '啊': 'a5', '大': 'da4', '中': 'zhong1', '发': 'fa1',
    '發': 'fa1', '干': 'gan4', '乐': 'le4', '樂': 'le4', '差': 'cha4', '数': 'shu4', '數': 'shu4', '处': 'chu4', '處': 'chu4',
    '当': 'dang1', '當': 'dang1', '相': 'xiang1', '空': 'kong1', '教': 'jiao1', '将': 'jiang1', '將': 'jiang1', '给': 'gei3',
    '給': 'gei3', '把': 'ba3', '被': 'bei4', '也': 'ye3', '是': 'shi4', '我': 'wo3', '你': 'ni3', '他': 'ta1', '她': 'ta1',
    '它': 'ta1', '有': 'you3', '在': 'zai4', '就': 'jiu4', '都是': 'dou1 shi4', '什么': 'shen2 me5', '什麼': 'shen2 me5',
    '怎么': 'zen3 me5', '怎麼': 'zen3 me5', '这么': 'zhe4 me5', '這麼': 'zhe4 me5', '那么': 'na4 me5', '那麼': 'na4 me5',
    '多么': 'duo1 me5', '为什么': 'wei4 shen2 me5', '為什麼': 'wei4 shen2 me5', '觉得': 'jue2 de5', '覺得': 'jue2 de5',
    '东西': 'dong1 xi5', '東西': 'dong1 xi5', '朋友': 'peng2 you5', '时候': 'shi2 hou5', '時候': 'shi2 hou5',
  };
}

class ChineseEntry {
  const ChineseEntry({required this.traditional, required this.simplified, required this.pinyin, required this.senses});

  final String traditional;
  final String simplified;

  /// Numbered, as CC-CEDICT writes it: `zhong1 guo2`.
  final String pinyin;
  final List<String> senses;

  String get marked => pinyinMarks(pinyin);

  static ChineseEntry parse(String line) {
    final firstSpace = line.indexOf(' ');
    final secondSpace = line.indexOf(' ', firstSpace + 1);
    final open = line.indexOf('[', secondSpace);
    final close = line.indexOf(']', open);
    final senses = line.substring(close + 1).trim().split('/').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return ChineseEntry(
      traditional: line.substring(0, firstSpace),
      simplified: line.substring(firstSpace + 1, secondSpace),
      pinyin: line.substring(open + 1, close),
      senses: senses,
    );
  }

  static String pinyinOf(String line) {
    final open = line.indexOf('[');
    final close = line.indexOf(']', open);
    return open < 0 || close < 0 ? '' : line.substring(open + 1, close);
  }
}

/// `ni3 hao3` as `nǐ hǎo`; `lu:4` as `lǜ`. Syllables without a tone number
/// stay as they are.
String pinyinMarks(String numbered) => numbered.split(' ').map(_syllable).join(' ');

const _marks = {
  'a': ['ā', 'á', 'ǎ', 'à'],
  'e': ['ē', 'é', 'ě', 'è'],
  'i': ['ī', 'í', 'ǐ', 'ì'],
  'o': ['ō', 'ó', 'ǒ', 'ò'],
  'u': ['ū', 'ú', 'ǔ', 'ù'],
  'ü': ['ǖ', 'ǘ', 'ǚ', 'ǜ'],
  'A': ['Ā', 'Á', 'Ǎ', 'À'],
  'E': ['Ē', 'É', 'Ě', 'È'],
  'O': ['Ō', 'Ó', 'Ǒ', 'Ò'],
};

String _syllable(String s) {
  var text = s.replaceAll('u:', 'ü').replaceAll('U:', 'Ü').replaceAll('v', 'ü');
  if (text.isEmpty) return text;
  final last = text[text.length - 1];
  final tone = int.tryParse(last);
  if (tone == null) return text;
  text = text.substring(0, text.length - 1);
  if (tone < 1 || tone > 4) return text;
  final lower = text.toLowerCase();
  int at;
  if (lower.contains('a')) {
    at = lower.indexOf('a');
  } else if (lower.contains('e')) {
    at = lower.indexOf('e');
  } else if (lower.contains('ou')) {
    at = lower.indexOf('o');
  } else {
    at = -1;
    for (var i = lower.length - 1; i >= 0; i--) {
      if ('aeiouü'.contains(lower[i])) {
        at = i;
        break;
      }
    }
  }
  if (at < 0) return text;
  final marks = _marks[text[at]] ?? _marks[text[at].toLowerCase()];
  if (marks == null) return text;
  return '${text.substring(0, at)}${marks[tone - 1]}${text.substring(at + 1)}';
}
