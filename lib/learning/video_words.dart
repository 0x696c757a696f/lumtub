import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../native_core.dart';
import 'known_words.dart';
import 'learning.dart';
import 'word_token.dart';

/// What a video's subtitles hold for this learner: the share of what is
/// said that they know, how many different words there are and how many
/// are new, the new words said most often, and the lines with exactly
/// one new word.
@immutable
class VideoWords {
  const VideoWords({required this.known, required this.words, required this.newWords, required this.often, required this.oneNew, this.language = ''});

  /// From 0 to 1, each word counted every time it is said.
  final double known;
  final int words;
  final int newWords;

  /// The new words said most often, with how often, most first.
  final List<(WordToken, int)> often;

  /// The language most of its words are in.
  final String language;

  /// Indexes of the lines with exactly one new word.
  final List<int> oneNew;

  /// About how hard the video is for this learner, from what is known.
  VideoLevel get level => levelFor(known);

  static VideoLevel levelFor(double known) => known >= 0.98
      ? VideoLevel.easy
      : known >= 0.95
          ? VideoLevel.right
          : known >= 0.90
              ? VideoLevel.challenging
              : known >= 0.80
                  ? VideoLevel.hard
                  : VideoLevel.tooHard;
}

/// From studies of viewing (Webb & Rodgers 2009, Durbahn et al. 2024):
/// 98 % of words known watches with ease, about 95 % is where a learner
/// with subtitles follows well and still meets new words, 90 to 95 % asks
/// for careful listening and looking words up, 80 % still gets the gist
/// with help, and below that every line stops for a word. Starting
/// points for the product, to be tuned by what learners say.
enum VideoLevel { easy, right, challenging, hard, tooHard }

final _cache = <String, Future<VideoWords?>>{};

final _sentenceEnd = RegExp(r'[.!?…。！？]');
final _han = RegExp(r'\p{Script=Han}', unicode: true);
final _upper = RegExp(r'^\p{Lu}', unicode: true);

/// A capitalised word inside a sentence in a language that writes only
/// names that way: Lisboa, Pierre. German capitalises every noun.
bool looksLikeName(WordToken t) {
  final language = Learning.languageOf(t);
  if (language == 'de' || language == 'zh' || language == 'ja' || language == 'ko') return false;
  // I'm, I've, I'll: the English I, not a name.
  if (language == 'en' && RegExp("^I['’]").hasMatch(t.text)) return false;
  return _upper.hasMatch(t.text) && t.text != t.text.toUpperCase();
}

/// [VideoWords] of [lines] for the words [known] holds; words at or
/// below the learner's level count as known. Cut into words a few lines
/// at a time, so the interface never waits; counted by lumtub_core off
/// the interface thread. Null without the core or a dictionary.
Future<VideoWords?> videoWordsOf(Learning learning, KnownWords known, String id, List<String> lines, {int most = 12}) {
  final key = '$id|${lines.length}|${known.revision}|${learning.levelKey}';
  if (_cache.length > 8) _cache.remove(_cache.keys.first);
  return _cache[key] ??= _videoWords(learning, known, lines, most);
}

Future<VideoWords?> _videoWords(Learning learning, KnownWords known, List<String> lines, int most) async {
  if (NativeCore.instance == null) return null;
  final keys = <List<String>>[];
  final tokens = <String, WordToken>{};
  final knownKeys = <String>{};
  final languages = <String, int>{};
  final characters = {'zh': known.characters('zh'), 'ja': known.characters('ja')};
  final compounds = <String>{};
  for (final (i, line) in lines.indexed) {
    // A breath every few lines keeps frames coming while a long video is cut.
    if (i % 40 == 39) await Future<void>.delayed(Duration.zero);
    final words = learning.wordsOf(line);
    if (words == null) {
      keys.add(const []);
      continue;
    }
    final row = <String>[];
    var start = true;
    for (final t in words) {
      if (!t.isWord) {
        if (_sentenceEnd.hasMatch(t.text)) start = true;
        continue;
      }
      final first = start;
      start = false;
      if (!KnownWords.counts(t)) continue;
      // A name says nothing about the words one knows.
      if (!first && looksLikeName(t) && !known.knows(t)) continue;
      final key = KnownWords.tokenKey(t);
      row.add(key);
      languages.update(Learning.languageOf(t), (n) => n + 1, ifAbsent: () => 1);
      if (tokens.putIfAbsent(key, () => t) == t) {
        if (known.knows(t) || learning.belowLevel(t)) {
          knownKeys.add(key);
          characters[Learning.languageOf(t)]?.addAll(t.text.runes);
        }
      }
    }
    keys.add(row);
  }
  if (tokens.isEmpty) return null;
  // A new Chinese or Japanese word made only of characters known from
  // other words counts as half known: its meaning can often be guessed.
  for (final MapEntry(:key, value: t) in tokens.entries) {
    final chars = characters[Learning.languageOf(t)];
    if (chars == null || knownKeys.contains(key) || t.text.runes.length < 2) continue;
    if (t.text.runes.every((c) => _han.hasMatch(String.fromCharCode(c)) && chars.contains(c))) compounds.add(key);
  }
  final input = jsonEncode({'lines': keys, 'known': knownKeys.toList(), 'half': compounds.toList(), 'most': most});
  final answer = await Isolate.run(() {
    final core = NativeCore.instance!;
    return core.take(core.withText(input, core.wordCoverage));
  });
  final json = answer == null ? null : jsonDecode(answer);
  if (json is! Map) return null;
  return VideoWords(
    known: (json['known'] as num?)?.toDouble() ?? 0,
    words: json['words'] as int? ?? 0,
    newWords: json['unknownWords'] as int? ?? 0,
    often: [
      for (final pair in (json['often'] as List? ?? const []))
        if (pair is List && pair.length == 2 && pair[0] is String && tokens[pair[0] as String] != null) (tokens[pair[0] as String]!, pair[1] as int),
    ],
    oneNew: [for (final i in (json['oneNew'] as List? ?? const [])) if (i is int) i],
    language: languages.entries.fold<MapEntry<String, int>?>(null, (best, e) => best == null || e.value > best.value ? e : best)?.key ?? '',
  );
}
