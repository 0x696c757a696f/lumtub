import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
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

  static VideoLevel levelFor(double known) => known >= 0.98 ? VideoLevel.easy : (known >= 0.90 ? VideoLevel.right : (known >= 0.80 ? VideoLevel.hard : VideoLevel.tooHard));
}

/// From studies of viewing (Durbahn et al. 2024, Webb & Rodgers 2009):
/// 98 % of words known watches with ease, 90 to 98 % is where a learner
/// with subtitles learns most, 80 % still gets the gist with help, and
/// below that every line stops for a word.
enum VideoLevel { easy, right, hard, tooHard }

final _cache = <String, Future<VideoWords?>>{};

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
  for (final (i, line) in lines.indexed) {
    // A breath every few lines keeps frames coming while a long video is cut.
    if (i % 40 == 39) await Future<void>.delayed(Duration.zero);
    final words = learning.wordsOf(line);
    if (words == null) {
      keys.add(const []);
      continue;
    }
    final row = <String>[];
    for (final t in words) {
      if (!t.isWord || !KnownWords.counts(t)) continue;
      final key = KnownWords.tokenKey(t);
      row.add(key);
      languages.update(Learning.languageOf(t), (n) => n + 1, ifAbsent: () => 1);
      if (tokens.putIfAbsent(key, () => t) == t && (known.knows(t) || learning.belowLevel(t))) knownKeys.add(key);
    }
    keys.add(row);
  }
  if (tokens.isEmpty) return null;
  final input = jsonEncode({'lines': keys, 'known': knownKeys.toList(), 'most': most});
  final answer = await Isolate.run(() {
    final core = NativeCore.instance!;
    final coverage = core.library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_word_coverage');
    return core.take(core.withText(input, coverage));
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
