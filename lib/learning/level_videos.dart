import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_directories.dart';
import '../app_log.dart';
import '../bounded_get.dart';
import '../caption_tracks.dart';
import '../explore_filters.dart';
import '../models.dart';
import '../native_core.dart';
import '../subtitle_files.dart' show WebVtt;
import '../video_languages.dart';
import '../youtube_player_probe.dart';
import 'english_dictionary.dart' show EnglishLevel;
import 'known_words.dart';
import 'learning.dart';
import 'video_difficulty.dart';
import 'video_words.dart';
import 'word_token.dart';

/// 按水平找视频: videos for a learner of one language, of three kinds.
///
/// * **Graded listening**: videos made for learners, spoken in the
///   language itself, slowly, with pictures and gestures (comprehensible
///   input). They help from the first day, so a low share of known words
///   does not hide them.
/// * **Native videos**: what its own speakers watch (vlogs, podcasts,
///   news, documentaries).
/// * **Lessons**: videos that teach the language in one the learner reads
///   (the interface language unless they pick another).
///
/// The first two are kept only when the explore language check hears them
/// in the language ([VideoLanguages.only]), and measured by their own
/// subtitles in it ([LevelFeatures]). Subtitles translated into it never
/// count: YouTube's machine translations are not among a video's tracks,
/// and a video spoken in another language with the uploader's subtitles
/// in this one is left out by the language check first.
enum LevelVideoKind { graded, native, lessons }

/// The learning languages, as the explore language filter names them.
ExploreLanguage exploreLanguageOf(String language) => ExploreLanguage.parse(language);

/// Three steps: beginner, intermediate and advanced. Which one a level is.
int levelTierOf(String language, int? level) {
  if (level == null) return 0;
  return switch (language) {
    // EnglishLevel's index: middle school (A2) to beyond.
    'en' => level <= EnglishLevel.middleSchool.index ? 0 : (level < EnglishLevel.toeflIelts.index ? 1 : 2),
    _ => switch (LevelScale.of(language)) {
        LevelScale.hsk => level <= 2 ? 0 : (level <= 4 ? 1 : 2),
        LevelScale.jlpt => level <= 2 ? 0 : (level == 3 ? 1 : 2),
        LevelScale.korean => (level - 1).clamp(0, 2),
        LevelScale.cefr => level <= 2 ? 0 : (level <= 4 ? 1 : 2),
        null => 0,
      },
  };
}

/// The English name of each learning language.
const _englishNames = {
  'en': 'English',
  'zh': 'Chinese',
  'ja': 'Japanese',
  'ko': 'Korean',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
  'ru': 'Russian',
};

/// Searches for graded listening in [language] at [tier]: videos made for
/// learners, many titled in English ("Japanese comprehensible input
/// beginner") while spoken wholly in the language, the names of channels
/// known for them, and the language's own words for easy speech. The
/// channels are only searched for: what they bring still has to be heard
/// in the language and is measured like any other video.
List<String> gradedLevelQueries(String language, int tier) {
  final name = _englishNames[language] ?? language;
  final step = const ['beginner', 'intermediate', 'advanced'][tier.clamp(0, 2)];
  return ['$name comprehensible input $step', ...?_gradedQueries[language]];
}

const _gradedQueries = <String, List<String>>{
  'en': ['VOA Learning English', 'BBC Learning English', 'easy English listening', 'slow English story'],
  'zh': ['Mandarin Corner', 'Lazy Chinese', '慢速中文', '简单中文 故事'],
  'ja': ['Comprehensible Japanese', 'やさしい日本語', 'ゆっくり日本語', 'にほんごのじかん'],
  'ko': ['Comprehensible Korean', '쉬운 한국어', '천천히 한국어 듣기'],
  'es': ['Dreaming Spanish', 'Easy Spanish', 'español fácil', 'español lento para principiantes'],
  'fr': ['Alice Ayel', 'InnerFrench', 'Easy French', 'français facile'],
  'de': ['Easy German', 'Natürlich German', 'einfaches Deutsch', 'langsames Deutsch'],
  'it': ['Easy Italian', 'Italiano Automatico', 'italiano facile', 'italiano lento'],
  'pt': ['Speaking Brazilian', 'Portuguese With Leo', 'português fácil', 'português devagar'],
  'ru': ['Russian with Max', 'Russian From Afar', 'простой русский язык', 'медленный русский'],
};

/// Searches for native videos in [language], written in the language
/// itself as its own speakers title them, so nothing is machine-
/// translated: everyday talk first, then news and talks; an advanced
/// learner the other way round. A search that runs out goes on with the
/// next.
List<List<String>> nativeLevelQueries(String language, int tier) {
  final [everyday, serious] = _nativeQueries[language] ?? _nativeQueries['en']!;
  return tier >= 2 ? [serious, everyday] : [everyday, serious];
}

const _nativeQueries = <String, List<List<String>>>{
  'en': [
    ['podcast conversation', 'daily life vlog', 'street interview'],
    ['documentary', 'news analysis', 'lecture'],
  ],
  'zh': [
    ['播客 聊天', '日常vlog', '街头采访'],
    ['纪录片', '深度解读', '讲座'],
  ],
  'ja': [
    ['雑談 ポッドキャスト', '日常 vlog', '街頭インタビュー'],
    ['ドキュメンタリー', 'ニュース 解説', '講演'],
  ],
  'ko': [
    ['팟캐스트 대화', '일상 브이로그', '길거리 인터뷰'],
    ['다큐멘터리', '뉴스 해설', '강연'],
  ],
  'es': [
    ['podcast conversación', 'vlog de mi día', 'entrevistas en la calle'],
    ['documental', 'análisis de noticias', 'conferencia'],
  ],
  'fr': [
    ['podcast conversation', 'vlog ma journée', 'micro-trottoir'],
    ['documentaire', "analyse de l'actualité", 'conférence'],
  ],
  'de': [
    ['Podcast Gespräch', 'Vlog mein Alltag', 'Straßenumfrage'],
    ['Dokumentation', 'Nachrichten Analyse', 'Vortrag'],
  ],
  'it': [
    ['podcast conversazione', 'vlog la mia giornata', 'interviste per strada'],
    ['documentario', 'analisi delle notizie', 'conferenza'],
  ],
  'pt': [
    ['podcast conversa', 'vlog do meu dia', 'entrevista na rua'],
    ['documentário', 'análise de notícias', 'palestra'],
  ],
  'ru': [
    ['подкаст разговор', 'влог мой день', 'опрос на улице'],
    ['документальный фильм', 'разбор новостей', 'лекция'],
  ],
};

/// The Chinese name of each, for lessons explained in Chinese, which are
/// titled "日语入门" rather than as a translation of English words.
const _chineseNames = {
  'en': '英语',
  'zh': '中文',
  'ja': '日语',
  'ko': '韩语',
  'es': '西班牙语',
  'fr': '法语',
  'de': '德语',
  'it': '意大利语',
  'pt': '葡萄牙语',
  'ru': '俄语',
};

/// What lessons of [language] at [level] call their level: the exam's
/// own name where the language has one (N5, HSK 3, TOPIK I), else CEFR.
String? levelTag(String language, int? level) {
  if (level == null) return null;
  if (language == 'en') return EnglishLevel.values[level.clamp(0, EnglishLevel.gre.index)].cefr.replaceAll('+', '');
  return switch (LevelScale.of(language)) {
    LevelScale.hsk => 'HSK ${level.clamp(1, 7)}',
    LevelScale.jlpt => 'N${6 - level.clamp(1, 5)}',
    LevelScale.korean => level <= 1 ? 'TOPIK I' : 'TOPIK II',
    LevelScale.cefr => const ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'][level.clamp(1, 6) - 1],
    null => null,
  };
}

/// Lesson searches for [language] at [tier] explained in [explainedIn]:
/// English words (Chinese ones for Chinese) that explore's search
/// translation puts into the explanation language, with the level's name
/// ([tag]) added untranslated.
List<LessonQuery> lessonQueries(String language, int tier, ExploreLanguage explainedIn, {String? tag}) {
  if (explainedIn == ExploreLanguage.zh) {
    final name = _chineseNames[language] ?? language;
    final step = const ['入门', '中级', '高级'][tier.clamp(0, 2)];
    return [
      LessonQuery('$name$step 教程', tag: tag, translated: false),
      LessonQuery('$name 语法 讲解', tag: tag, translated: false),
      LessonQuery('$name 发音', translated: false),
    ];
  }
  final name = _englishNames[language] ?? language;
  final step = const ['for beginners', 'intermediate', 'advanced'][tier.clamp(0, 2)];
  return [
    LessonQuery('learn $name $step', tag: tag),
    LessonQuery('$name grammar lesson', tag: tag),
    LessonQuery('$name pronunciation'),
  ];
}

/// One lesson search: [words] to put into the explanation language, and
/// the level's name ([tag]) added untranslated.
@immutable
class LessonQuery {
  const LessonQuery(this.words, {this.tag, this.translated = true});
  final String words;
  final String? tag;

  /// Whether [words] still go into the explanation language.
  final bool translated;

  String withTag(String translatedWords) => tag == null ? translatedWords : '$translatedWords $tag';
}

/// How well a lesson's title matches [tag] (the learner's level): 2 when
/// it names it, 1 when it names no level, 0 when it names only others.
int lessonFit(String title, String? tag) {
  if (tag == null) return 1;
  final named = [for (final m in _levelNames.allMatches(title.toUpperCase())) m[0]!.replaceAll(RegExp(r'\s+'), '')];
  if (named.isEmpty) return 1;
  return named.contains(tag.toUpperCase().replaceAll(' ', '')) ? 2 : 0;
}

final _levelNames = RegExp(r'\b(?:N[1-5]|HSK\s?[1-9]|TOPIK\s?I{1,2}|[ABC][12])\b');

/// How fast people of each language speak at an everyday pace, in the
/// unit that language is best counted in ([speechUnits]): words for
/// languages written with spaces, Chinese characters, Japanese morae,
/// Korean syllables. Starting points from studies of speech rate (2026-11
/// review), to be tuned against the videos learners watch.
const _everydayPace = {'en': 170, 'es': 170, 'it': 165, 'fr': 165, 'pt': 160, 'de': 140, 'ru': 120, 'zh': 260, 'ja': 400, 'ko': 300};

/// Slower than this share of the everyday pace is slow, faster than
/// [_fastPace] fast.
const _slowPace = 0.8;
const _fastPace = 1.2;

enum SpeechPace { slow, moderate, fast }

final _hanRune = RegExp(r'\p{Script=Han}', unicode: true);
final _hangul = RegExp(r'[가-힣]');
final _kana = RegExp(r'[ぁ-ゖァ-ヺー]');
final _smallKana = RegExp(r'[ゃゅょぁぃぅぇぉゎャュョァィゥェォヮ]');

/// How much of the language [token] says, in the unit [_everydayPace]
/// counts: a word, or its Chinese characters, Japanese morae (っ, ん and ー
/// one each, a small ゃ part of the one before) or Korean syllables.
int speechUnits(String language, WordToken token) {
  switch (language) {
    case 'zh':
      return _hanRune.allMatches(token.text).length.clamp(1, 1 << 20);
    case 'ko':
      return _hangul.allMatches(token.text).length.clamp(1, 1 << 20);
    case 'ja':
      final kana = token.reading ?? token.text;
      final morae = _kana.allMatches(kana).length - _smallKana.allMatches(kana).length;
      // Kanji with no reading known: about two morae each.
      final unread = token.reading == null ? _hanRune.allMatches(token.text).length * 2 : 0;
      return (morae + unread).clamp(1, 1 << 20);
    default:
      return 1;
  }
}

/// One video's subtitles, cut into words once and kept, so how much of it
/// the learner knows is worked out again on this device whenever they
/// learn words or change their level, without asking YouTube again.
@immutable
class LevelFeatures {
  const LevelFeatures({
    required this.language,
    required this.automatic,
    required this.words,
    required this.lines,
    required this.starts,
    required this.speech,
    required this.units,
    this.repeated = 0,
    this.rushed = 0,
  });

  final String language;

  /// From YouTube's automatic captions rather than the uploader's: the
  /// share known is an estimate, as recognition misses and mishears.
  final bool automatic;

  /// Each different word once.
  final List<WordToken> words;

  /// Each line's words, as indexes into [words]; a word that may be a
  /// name (capitalised inside a sentence) is written as `-(index + 1)`
  /// and counts only when the learner knows it.
  final List<List<int>> lines;

  /// When each line starts, in milliseconds.
  final List<int> starts;

  /// How long lines are on screen, overlaps counted once, in
  /// milliseconds: about how long people speak. A travel vlog of long
  /// silent views is not slow speech for them.
  final int speech;

  /// What is said, in [speechUnits].
  final int units;

  /// The share of lines that repeat the line before (three times or more
  /// in a row) and of ten-second stretches faster than two and a half
  /// times the everyday pace: signs of captions gone wrong.
  final double repeated;
  final double rushed;

  /// How far the subtitles can be trusted, from 0 to 100: automatic
  /// captions less, and less again when they repeat themselves or race.
  /// Below 60 a video is left out of the order by difficulty.
  int get confidence {
    var c = 100;
    if (automatic) c -= 10;
    if (repeated > 0.25) {
      c -= 35;
    } else if (repeated > 0.10) {
      c -= 15;
    }
    if (rushed > 0.30) {
      c -= 30;
    } else if (rushed > 0.15) {
      c -= 15;
    }
    return c.clamp(0, 100);
  }

  static const version = 2;

  Map<String, Object?> toJson() => {
        'v': version,
        'l': language,
        'a': automatic,
        'w': [for (final t in words) [t.text, t.lookup, t.language]],
        'x': lines,
        's': starts,
        'd': speech,
        'u': units,
        'r': repeated,
        'f': rushed,
      };

  static LevelFeatures? fromJson(Object? raw) {
    if (raw is! Map || raw['v'] != version) return null;
    final language = raw['l'], automatic = raw['a'], words = raw['w'], lines = raw['x'], starts = raw['s'], speech = raw['d'], units = raw['u'];
    if (language is! String || automatic is! bool || words is! List || lines is! List || starts is! List || speech is! int || units is! int) return null;
    if (lines.length != starts.length || words.length > 100000 || lines.length > 100000 || speech < 0 || units < 0) return null;
    double share(Object? v) => v is num && v.isFinite ? v.toDouble().clamp(0, 1) : 0;
    final tokens = <WordToken>[];
    for (final w in words) {
      if (w is! List || w.length != 3 || w[0] is! String || (w[1] != null && w[1] is! String) || (w[2] != null && w[2] is! String)) return null;
      tokens.add(WordToken(w[0] as String, null, isWord: true, lookup: w[1] as String?, language: w[2] as String?));
    }
    final rows = <List<int>>[];
    for (final line in lines) {
      if (line is! List) return null;
      final row = <int>[];
      for (final i in line) {
        if (i is! int || (i >= 0 ? i : -i - 1) >= tokens.length) return null;
        row.add(i);
      }
      rows.add(row);
    }
    return LevelFeatures(
      language: language,
      automatic: automatic,
      words: tokens,
      lines: rows,
      starts: [for (final s in starts) s is int ? s : 0],
      speech: speech,
      units: units,
      repeated: share(raw['r']),
      rushed: share(raw['f']),
    );
  }
}

/// [cues] (start and end in milliseconds, text) cut into words with
/// [learning]'s dictionaries, a few lines at a time so the interface
/// never waits. Null when nothing in them is a word of a dictionary.
Future<LevelFeatures?> levelFeaturesOf(Learning learning, String language, List<(int, int, String)> cues, {required bool automatic}) async {
  final words = <WordToken>[];
  final index = <String, int>{};
  final lines = <List<int>>[];
  final starts = <int>[];
  final lineUnits = <int>[];
  var units = 0;
  for (final (i, (start, _, text)) in cues.indexed) {
    if (i % 40 == 39) await Future<void>.delayed(Duration.zero);
    final tokens = learning.wordsOf(text);
    final row = <int>[];
    var said = 0;
    var first = true;
    for (final t in tokens ?? const <WordToken>[]) {
      if (!t.isWord) {
        if (_sentenceEnd.hasMatch(t.text)) first = true;
        continue;
      }
      final sentenceStart = first;
      first = false;
      if (!KnownWords.counts(t)) continue;
      said += speechUnits(language, t);
      final key = KnownWords.tokenKey(t);
      final at = index.putIfAbsent(key, () {
        words.add(WordToken(t.text, null, isWord: true, lookup: t.lookup, language: t.language));
        return words.length - 1;
      });
      row.add(!sentenceStart && looksLikeName(t) ? -at - 1 : at);
    }
    units += said;
    lineUnits.add(said);
    lines.add(row);
    starts.add(start);
  }
  if (words.isEmpty) return null;
  return LevelFeatures(
    language: language,
    automatic: automatic,
    words: words,
    lines: lines,
    starts: starts,
    speech: speechSpan(cues),
    units: units,
    repeated: repeatedShare([for (final c in cues) c.$3]),
    rushed: rushedShare(language, starts, lineUnits),
  );
}

/// How long [cues] are on screen, overlapping ones counted once.
int speechSpan(List<(int, int, String)> cues) {
  final spans = [for (final (start, end, _) in cues) if (end > start) (start, end)]..sort((a, b) => a.$1.compareTo(b.$1));
  var total = 0;
  int? from, to;
  for (final (start, end) in spans) {
    if (to == null || start > to) {
      if (to != null) total += to - from!;
      from = start;
      to = end;
    } else if (end > to) {
      to = end;
    }
  }
  if (to != null) total += to - from!;
  return total;
}

/// The share of [lines] that say the line before again, when it comes
/// three times or more in a row. Graded listening repeats on purpose, but
/// seldom the same whole line three times running.
double repeatedShare(List<String> lines) {
  if (lines.length < 3) return 0;
  var repeated = 0;
  var run = 1;
  for (var i = 1; i < lines.length; i++) {
    final same = lines[i].trim().isNotEmpty && lines[i].trim() == lines[i - 1].trim();
    run = same ? run + 1 : 1;
    if (run == 3) repeated += 3;
    if (run > 3) repeated++;
  }
  return repeated / lines.length;
}

/// The share of ten-second stretches with speech that say more than two
/// and a half times what [language]'s everyday pace would: captions piled
/// up, repeated or mistimed.
double rushedShare(String language, List<int> starts, List<int> units) {
  final limit = (_everydayPace[language] ?? 170) / 6 * 2.5;
  final windows = <int, int>{};
  for (final (i, start) in starts.indexed) {
    if (units[i] > 0) windows.update(start ~/ 10000, (v) => v + units[i], ifAbsent: () => units[i]);
  }
  if (windows.isEmpty) return 0;
  return windows.values.where((v) => v > limit).length / windows.length;
}

final _sentenceEnd = RegExp(r'[.!?…。！？]');
final _han = RegExp(r'\p{Script=Han}', unicode: true);

/// What a video's [LevelFeatures] say for one learner.
@immutable
class LevelMeasure {
  const LevelMeasure({required this.known, required this.said, required this.newWords, required this.perMinute, required this.newPerMinute, required this.hardestMinute});

  /// The share of what is said known, each word counted every time.
  final double known;
  final int said;

  /// Different words not known.
  final int newWords;

  /// [speechUnits] said a minute of speech, and words not known.
  final double perMinute;
  final double newPerMinute;

  /// The share known in the hardest minutes: the tenth percentile of
  /// minute-long stretches, a half minute apart; null when too few say
  /// enough to tell.
  final double? hardestMinute;
}

/// How much of [features] a learner knows: [knows] says whether they know
/// a word (marked, reviewed until it stays, or at or below their level);
/// [characters] are the Chinese and Japanese characters of words they
/// know elsewhere. As `coverage` in the core counts: a new Chinese or
/// Japanese word made only of known characters counts as half known.
LevelMeasure measureLevel(LevelFeatures features, bool Function(WordToken word) knows, Set<int> characters) {
  final known = [for (final w in features.words) knows(w)];
  final chars = {...characters};
  for (final (i, w) in features.words.indexed) {
    if (known[i]) chars.addAll(w.text.runes);
  }
  final cjk = features.language == 'zh' || features.language == 'ja';
  final half = [
    for (final (i, w) in features.words.indexed)
      cjk && !known[i] && w.text.runes.length >= 2 && w.text.runes.every((c) => _han.hasMatch(String.fromCharCode(c)) && chars.contains(c)),
  ];
  var said = 0;
  var understood = 0.0;
  final unknown = <int>{};
  // Minute-long stretches starting every half minute: a line counts in
  // the two that hold its start.
  final windowSaid = <int, int>{};
  final windowUnderstood = <int, double>{};
  void add(int window, double got) {
    windowSaid.update(window, (v) => v + 1, ifAbsent: () => 1);
    windowUnderstood.update(window, (v) => v + got, ifAbsent: () => got);
  }

  for (final (n, line) in features.lines.indexed) {
    final half30 = features.starts[n] ~/ 30000;
    for (final raw in line) {
      final i = raw >= 0 ? raw : -raw - 1;
      // A name says nothing about what is understood, unless known.
      if (raw < 0 && !known[i]) continue;
      final got = known[i] ? 1.0 : (half[i] ? 0.5 : 0.0);
      said++;
      understood += got;
      if (!known[i]) unknown.add(i);
      add(half30, got);
      if (half30 > 0) add(half30 - 1, got);
    }
  }
  // A stretch of a few words (music, a pause) tells nothing.
  final shares = [
    for (final MapEntry(key: w, value: count) in windowSaid.entries)
      if (count >= 15) windowUnderstood[w]! / count,
  ]..sort();
  // Short clips count as half a minute of speech at least, so a few lines
  // do not read as a torrent of words.
  final minutes = features.speech.clamp(30000, 1 << 31) / 60000;
  return LevelMeasure(
    known: said == 0 ? 0 : understood / said,
    said: said,
    newWords: unknown.length,
    perMinute: features.units / minutes,
    newPerMinute: (said - understood) / minutes,
    hardestMinute: shares.isEmpty ? null : shares[((shares.length - 1) * 0.1).floor()],
  );
}

/// What a video was found to be for the learner, kept so a list shown
/// again needs nothing worked out or fetched.
@immutable
class LevelReading {
  const LevelReading({
    required this.language,
    required this.known,
    required this.automatic,
    required this.newWords,
    required this.perMinute,
    required this.newPerMinute,
    required this.hardestMinute,
    required this.at,
    required this.stamp,
    this.confidence = 100,
  });

  final String language;

  /// The share of what is said the learner knows; null when the video
  /// had no subtitles in [language] that could be read.
  final double? known;
  final bool automatic;
  final int newWords;
  final double perMinute;
  final double newPerMinute;
  final double? hardestMinute;

  /// [LevelFeatures.confidence].
  final int confidence;

  /// When the subtitles were fetched, in seconds since 1970.
  final int at;

  /// What the learner knew when it was worked out ([LevelVideos.stampOf]):
  /// with another, it is worked out again from the kept features.
  final String stamp;

  VideoLevel? get level => known == null ? null : VideoWords.levelFor(known!);

  /// Whether the subtitles look too broken to order the video by.
  bool get unreliable => confidence < 60;

  /// Whether they look doubtful enough to say so.
  bool get doubtful => confidence < 80;

  SpeechPace get pace {
    final everyday = _everydayPace[language] ?? 170;
    final pace = perMinute / everyday;
    return pace < _slowPace ? SpeechPace.slow : (pace > _fastPace ? SpeechPace.fast : SpeechPace.moderate);
  }

  static LevelReading none(String language, int at) =>
      LevelReading(language: language, known: null, automatic: false, newWords: 0, perMinute: 0, newPerMinute: 0, hardestMinute: null, at: at, stamp: '');

  static LevelReading of(LevelFeatures features, LevelMeasure measure, {required int at, required String stamp}) => LevelReading(
        language: features.language,
        known: measure.known,
        automatic: features.automatic,
        newWords: measure.newWords,
        perMinute: measure.perMinute,
        newPerMinute: measure.newPerMinute,
        hardestMinute: measure.hardestMinute,
        confidence: features.confidence,
        at: at,
        stamp: stamp,
      );

  double _round(double v) => (v * 1000).roundToDouble() / 1000;

  Map<String, Object?> toJson() => {
        'l': language,
        if (known != null) 'k': _round(known!),
        if (automatic) 'a': true,
        'n': newWords,
        'p': _round(perMinute),
        'q': _round(newPerMinute),
        if (hardestMinute != null) 'h': _round(hardestMinute!),
        'c': confidence,
        't': at,
        'v': stamp,
      };

  static LevelReading? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final language = raw['l'], known = raw['k'], newWords = raw['n'], per = raw['p'], newPer = raw['q'], hardest = raw['h'], at = raw['t'], stamp = raw['v'], confidence = raw['c'] ?? 100;
    if (language is! String || language.length > 8 || at is! int || newWords is! int || stamp is! String || stamp.length > 400) return null;
    bool share(Object? v) => v == null || (v is num && v.isFinite && v >= 0 && v <= 1);
    bool rate(Object? v) => v is num && v.isFinite && v >= 0 && v < 100000;
    if (!share(known) || !share(hardest) || !rate(per) || !rate(newPer) || confidence is! int || confidence < 0 || confidence > 100) return null;
    return LevelReading(
      language: language,
      known: (known as num?)?.toDouble(),
      automatic: raw['a'] == true,
      newWords: newWords,
      perMinute: (per as num).toDouble(),
      newPerMinute: (newPer as num).toDouble(),
      hardestMinute: (hardest as num?)?.toDouble(),
      confidence: confidence,
      at: at,
      stamp: stamp,
    );
  }
}

/// What a measuring pass went over, for the page and the log: videos
/// asked about, measured, without subtitles, not answered, skipped for
/// their channel; and whether it stopped at its budget of new videos
/// ([LevelVideos.budget]) or because YouTube stopped answering.
typedef LevelCheck = ({int asked, int measured, int noSubtitles, int failed, int skipped, bool budgetSpent, bool refused});

/// Reads videos' subtitles in the language learnt, keeps their
/// [LevelFeatures] (one small file each) and what they told
/// ([LevelReading]), so a video is fetched once: a list shown again, a
/// level changed or words learnt cost YouTube nothing more.
class LevelVideos extends ChangeNotifier {
  LevelVideos(this._client);

  final http.Client _client;
  late final _probe = YoutubePlayerProbe(_client);

  /// Videos whose features are kept; the oldest go first.
  static const limit = 1500;

  /// How long features hold: YouTube may correct subtitles meanwhile.
  static const keptFor = Duration(days: 30);

  /// How long "no subtitles" holds: YouTube may make some by then.
  static const noSubtitlesFor = Duration(days: 7);

  /// Subtitle files are a few hundred kilobytes for an hour.
  static const subtitleLimit = 4 << 20;

  /// Videos read at once. Each may cost a `/player` request, spaced and
  /// held back while a video starts as every lookup for a list is
  /// ([YoutubePlayerProbe.post]), and a subtitle file; phones read fewer.
  static final parallel = Platform.isIOS || Platform.isAndroid ? 2 : 4;

  /// New videos one pass fetches subtitles of at most, before it waits
  /// for the learner to ask for more: a budget of requests, not a limit
  /// YouTube is known to keep.
  static const budget = 40;

  /// Answers missed in a row before a pass stops: YouTube is refusing
  /// (it asks this network to prove it is no bot) and asking on would only
  /// keep it refusing, playback included.
  static const refusalsBeforeStop = 5;

  /// A channel with this many of its videos read, none of them easy
  /// enough to follow, is left out for the language without reading more.
  static const channelGiveUp = 6;

  /// For learners without the pack: native videos measured for them the
  /// first time, then new ones each day. Videos once shown stay shown.
  static const freeFirst = 8;
  static const freeDaily = 3;

  static const _fields = 'playabilityStatus.status,$captionTrackFields';

  File? _file;
  Directory? _folder;
  Future<void>? _opening;
  final _readings = <String, LevelReading>{};
  final _reading = <String, Future<LevelReading?>>{};
  final _waiting = <Completer<void>>[];
  int _running = 0;
  Timer? _saving;

  /// Per `language|channel id`: videos read and how many of them a
  /// learner could follow (known 90 % or more) when read.
  final _channels = <String, (int, int)>{};
  static const _channelsKept = 3000;

  /// Native videos shown to a learner without the pack, and the day (as
  /// yyyy-mm-dd) and count of the newest ones.
  final _granted = <String>{};
  String _grantDay = '';
  int _grantedOnDay = 0;
  static const _grantedKept = 500;

  /// The app that last gave subtitles that could be read: asked first.
  PlayerClient _first = PlayerClient.quick;

  /// The language last looked for, and the lessons' language; null until
  /// picked.
  String? language;
  ExploreLanguage? explainedIn;

  /// Reads what was kept in [file]; features go in [folder].
  Future<void> open(File file, Directory folder) => _opening ??= _open(file, folder);

  Future<void> _open(File file, Directory folder) async {
    _file = file;
    _folder = folder;
    try {
      if (!await file.exists()) return;
      final text = await file.readAsString();
      final json = await (text.length < 64 << 10 ? Future.value(jsonDecode(text)) : Isolate.run(() => jsonDecode(text)));
      if (json is! Map) return;
      if (json['language'] case final String picked when picked.length <= 8) language = picked;
      if (json['explainedIn'] case final String picked) explainedIn = ExploreLanguage.values.where((l) => l.name == picked && l != ExploreLanguage.any).firstOrNull;
      if (json['videos'] case final Map videos) {
        for (final MapEntry(:key, :value) in videos.entries) {
          if (!_id.hasMatch('$key')) continue;
          if (LevelReading.fromJson(value) case final reading?) _readings['$key'] = reading;
        }
      }
      if (json['channels'] case final Map channels) {
        for (final MapEntry(:key, :value) in channels.entries.take(_channelsKept)) {
          if ('$key'.length > 80 || value is! List || value.length != 2) continue;
          if (value case [final int read, final int fit] when read >= 0 && fit >= 0 && fit <= read) _channels['$key'] = (read, fit);
        }
      }
      if (json['granted'] case final List granted) {
        _granted.addAll(granted.whereType<String>().where(_id.hasMatch).take(_grantedKept));
      }
      if (json['grantDay'] case final String day when day.length == 10) _grantDay = day;
      if (json['grantedOnDay'] case final int count when count >= 0) _grantedOnDay = count;
      notifyListeners();
    } catch (e) {
      logWarn('Could not read the level videos: $e');
    }
  }

  static final _id = RegExp(r'^[A-Za-z0-9_-]{11}$');

  LevelReading? readingOf(String id) => _readings[id];

  /// Remembers the language picked and the lessons' language.
  void choose({String? language, ExploreLanguage? explainedIn}) {
    if (language != null) this.language = language;
    if (explainedIn != null) this.explainedIn = explainedIn;
    _changed();
  }

  /// What the learner knows of [language] now, in a few characters: the
  /// levels, how many words were marked, how many reviewed until known.
  static String stampOf(Learning learning, KnownWords known) => '${learning.levelKey}|${known.marked}|${known.review.knownKeys.length}';

  File? _featuresFile(String id) => _folder == null ? null : File('${_folder!.path}${Platform.pathSeparator}$id.json.gz');

  /// The share of a channel's videos read in [language] that a learner
  /// could follow, from 0 to 1; null before any was read.
  double? channelFit(String language, String? channel) {
    if (channel == null) return null;
    final (read, fit) = _channels['$language|$channel'] ?? (0, 0);
    return read == 0 ? null : fit / read;
  }

  bool _channelGivenUp(String language, String? channel) {
    if (channel == null) return false;
    final (read, fit) = _channels['$language|$channel'] ?? (0, 0);
    return read >= channelGiveUp && fit == 0;
  }

  void _countChannel(String language, String? channel, double known) {
    if (channel == null || channel.length > 64) return;
    final key = '$language|$channel';
    final (read, fit) = _channels.remove(key) ?? (0, 0);
    _channels[key] = (read + 1, fit + (known >= 0.90 ? 1 : 0));
    while (_channels.length > _channelsKept) {
      _channels.remove(_channels.keys.first);
    }
  }

  static String get _today => DateTime.now().toIso8601String().substring(0, 10);

  /// New native videos a learner without the pack may still be shown
  /// today.
  int get freeLeft {
    if (_granted.length < freeFirst) return freeFirst - _granted.length;
    return _grantDay == _today ? (freeDaily - _grantedOnDay).clamp(0, freeDaily) : freeDaily;
  }

  /// Whether native video [id] may be shown measured to a learner
  /// without the pack: one shown before always, a new one while
  /// [freeLeft] allows, which it then takes. A video only counts once it
  /// is shown, so a search that finds none takes nothing.
  bool showFree(String id) {
    if (_granted.contains(id)) return true;
    if (freeLeft <= 0) return false;
    final first = _granted.length < freeFirst;
    _granted.add(id);
    while (_granted.length > _grantedKept) {
      _granted.remove(_granted.first);
    }
    if (!first) {
      if (_grantDay != _today) {
        _grantDay = _today;
        _grantedOnDay = 0;
      }
      _grantedOnDay++;
    }
    _changed();
    return true;
  }

  bool wasShownFree(String id) => _granted.contains(id);

  /// Passes on the lines of [lines] whose videos could be measured in
  /// [language], each read once at most ([parallel] at a time), as they are
  /// measured. Videos read before are worked out again on this device
  /// when what the learner knows changed. At most [budget] times [rounds]
  /// new videos are fetched; a pass also stops when YouTube stops
  /// answering. [languages] may hold the subtitle tracks of the language
  /// check's answer, so `/player` is not asked twice. No new video is
  /// fetched once [enough] says so. [done] hears what was gone over.
  Stream<String> measured(
    Stream<String> lines, {
    required String language,
    required Learning learning,
    required KnownWords known,
    VideoLanguages? languages,
    int rounds = 1,
    bool Function()? enough,
    void Function(LevelCheck check)? done,
  }) async* {
    await _opening;
    final pending = <_Pending>[];
    var asked = 0, measured = 0, none = 0, failed = 0, skipped = 0, fetched = 0, missedInRow = 0;
    var spent = false, refused = false;
    final clock = Stopwatch()..start();
    Iterable<String> ready() sync* {
      for (final p in pending.where((p) => p.done).toList()) {
        pending.remove(p);
        if (p.line case final line?) yield line;
      }
    }

    if (languages != null) languages.keepCaptionTracks++;
    try {
      await for (final line in lines) {
        final item = parseListingEntry(line);
        if (item is! VideoItem) continue;
        if (item.isLive || item.isUpcoming || item.membersOnly) continue;
        asked++;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final reading = _readings[item.id];
        if (reading != null && reading.language == language && reading.known == null && now - reading.at < noSubtitlesFor.inSeconds) {
          none++;
          continue;
        }
        final cached = reading != null && reading.language == language && reading.known != null && now - reading.at < keptFor.inSeconds;
        if (!cached) {
          if (enough?.call() ?? false) break;
          if (_channelGivenUp(language, item.channelId)) {
            skipped++;
            continue;
          }
          if (fetched >= budget * rounds) {
            spent = true;
            break;
          }
          if (missedInRow >= refusalsBeforeStop) {
            refused = true;
            break;
          }
          fetched++;
        }
        pending.add(_Pending(_read(item.id, item.channelId, language, learning, known, languages).then((reading) {
          if (reading == null) {
            failed++;
            missedInRow++;
            return null;
          }
          missedInRow = 0;
          if (reading.known == null) {
            none++;
            return null;
          }
          measured++;
          return line;
        })));
        yield* Stream.fromIterable(ready());
        while (pending.length >= parallel * 2) {
          await Future.any([for (final p in pending) p.future]);
          yield* Stream.fromIterable(ready());
        }
      }
      while (pending.isNotEmpty) {
        await Future.any([for (final p in pending) p.future]);
        yield* Stream.fromIterable(ready());
      }
    } finally {
      if (languages != null) languages.keepCaptionTracks--;
      done?.call((asked: asked, measured: measured, noSubtitles: none, failed: failed, skipped: skipped, budgetSpent: spent, refused: refused));
      if (asked > 0) {
        logInfo('Level videos $language: measured $measured of $asked in ${(clock.elapsedMilliseconds / 1000).toStringAsFixed(1)} s, '
            '$fetched fetched, $none without subtitles in $language, $failed not answered, $skipped skipped for their channel'
            '${spent ? '; stopped at the budget' : ''}${refused ? '; stopped as YouTube stopped answering' : ''}');
      }
    }
  }

  Future<LevelReading?> _read(String id, String? channel, String language, Learning learning, KnownWords known, VideoLanguages? languages) =>
      _reading[id] ??= _readOnce(id, channel, language, learning, known, languages).whenComplete(() => _reading.remove(id));

  Future<LevelReading?> _readOnce(String id, String? channel, String language, Learning learning, KnownWords known, VideoLanguages? languages) async {
    final stamp = stampOf(learning, known);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final reading = _readings[id];
    final fresh = reading != null && reading.language == language && reading.known != null && now - reading.at < keptFor.inSeconds;
    if (fresh && reading.stamp == stamp) return reading;
    if (fresh) {
      // What the learner knows changed: worked out again from the kept
      // words, without asking YouTube.
      final features = await _loadFeatures(id);
      if (features != null && features.language == language) {
        final again = LevelReading.of(features, _measure(features, learning, known), at: reading.at, stamp: stamp);
        _keep(id, again);
        return again;
      }
    }
    while (_running >= parallel) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    try {
      final subtitles = await _subtitles(id, language, languages?.captionTracks(id));
      if (subtitles == null) return null;
      final (cues, automatic) = subtitles;
      final features = cues.isEmpty ? null : await levelFeaturesOf(learning, language, cues, automatic: automatic);
      final LevelReading result;
      if (features == null) {
        result = LevelReading.none(language, now);
      } else {
        final measure = _measure(features, learning, known);
        // Too few words to say: a music video, a few lines of speech.
        result = measure.said < 40 ? LevelReading.none(language, now) : LevelReading.of(features, measure, at: now, stamp: stamp);
        if (result.known != null) {
          await _saveFeatures(id, features);
          _countChannel(language, channel, measure.known);
          // Every list's card then says how hard it is too.
          videoDifficulty.remember(id, measure.known);
        }
      }
      _keep(id, result);
      return result;
    } catch (e) {
      logDebug(() => 'Level videos: could not read $id: $e');
      return null;
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  static LevelMeasure _measure(LevelFeatures features, Learning learning, KnownWords known) =>
      measureLevel(features, (w) => known.knows(w) || learning.belowLevel(w), known.characters(features.language));

  Future<LevelFeatures?> _loadFeatures(String id) async {
    final file = _featuresFile(id);
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > subtitleLimit) return null;
      return await Isolate.run(() {
        final text = utf8.decode(gzip.decode(bytes));
        // Written here, but read as outside data all the same.
        if (text.length > 4 * subtitleLimit) return null;
        return LevelFeatures.fromJson(jsonDecode(text));
      });
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveFeatures(String id, LevelFeatures features) async {
    final file = _featuresFile(id);
    if (file == null) return;
    try {
      final json = features.toJson();
      final bytes = await Isolate.run(() => gzip.encode(utf8.encode(jsonEncode(json))));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    } catch (e) {
      logDebug(() => 'Level videos: could not keep the words of $id: $e');
    }
  }

  void _keep(String id, LevelReading reading) {
    _readings.remove(id);
    _readings[id] = reading;
    while (_readings.length > limit) {
      final oldest = _readings.keys.first;
      _readings.remove(oldest);
      final file = _featuresFile(oldest);
      if (file != null) unawaited(file.delete().then((_) {}, onError: (_) {}));
    }
    _changed();
  }

  /// [id]'s own subtitles in [language] as (start ms, end ms, text) cues,
  /// and whether YouTube made them from the audio: the uploader's when
  /// there are some, else YouTube's automatic captions. No cues when it
  /// has neither in [language]; null when YouTube did not answer.
  /// [known] are tracks the language check's answer listed. Otherwise
  /// each of YouTube's apps is asked in turn, as one may give subtitles
  /// another holds back.
  Future<(List<(int, int, String)>, bool)?> _subtitles(String id, String language, List<CaptionTrack>? known) async {
    if (known != null) {
      final track = captionTrackIn(known, language);
      if (track == null && known.isNotEmpty) return (const <(int, int, String)>[], false);
      if (track != null) {
        if (await _fetchCues(id, track, 'the language check') case final cues?) return (cues, track.automatic);
      }
    }
    var answered = false;
    for (final client in [_first, ...PlayerClient.values.where((c) => c != _first)]) {
      final List<int> bytes;
      try {
        bytes = await _probe.fetchAs(client, id, _fields, expect: 'playabilityStatus');
      } catch (e) {
        logDebug(() => 'Level videos: the ${client.name} app gave no answer for $id: $e');
        continue;
      }
      answered = true;
      final tracks = bytes.length < 32 << 10 ? captionTracksOf(bytes) : await Isolate.run(() => captionTracksOf(bytes));
      final track = captionTrackIn(tracks, language);
      if (track == null) {
        // The same in every app's answer where it gives any.
        if (tracks.isNotEmpty) return (const <(int, int, String)>[], false);
        continue;
      }
      if (await _fetchCues(id, track, 'the ${client.name} app') case final cues?) {
        if (client != _first) {
          logInfo('Level videos: the ${client.name} app gives subtitles that can be read; asking it first');
          _first = client;
        }
        return (cues, track.automatic);
      }
    }
    return answered ? (const <(int, int, String)>[], false) : null;
  }

  Future<List<(int, int, String)>?> _fetchCues(String id, CaptionTrack track, String from) async {
    final url = timedTextUrl(track);
    if (url == null) return null;
    try {
      final (status, body) = await getBounded(_client, url, limit: subtitleLimit);
      if (status != 200 || body.isEmpty) {
        logDebug(() => 'Level videos: subtitles of $id from $from answered HTTP $status with ${body.length} bytes');
        return null;
      }
      final vtt = utf8.decode(body, allowMalformed: true);
      final cues = await Isolate.run(() => [
            for (final c in WebVtt.cues(vtt))
              if (cueTimes(c.timing) case (final start, final end)) (start, end, c.text),
          ]);
      return cues.isEmpty ? null : cues;
    } catch (e) {
      logDebug(() => 'Level videos: could not fetch the subtitles of $id: $e');
      return null;
    }
  }

  void _changed() {
    notifyListeners();
    _saving?.cancel();
    _saving = Timer(const Duration(seconds: 2), () => unawaited(_save()));
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await writeFileAtomic(file, jsonEncode({
        'version': 1,
        if (language != null) 'language': language,
        if (explainedIn != null) 'explainedIn': explainedIn!.name,
        'videos': {for (final MapEntry(:key, :value) in _readings.entries) key: value.toJson()},
        'channels': {for (final MapEntry(:key, value: (read, fit)) in _channels.entries) key: [read, fit]},
        'granted': _granted.toList(),
        'grantDay': _grantDay,
        'grantedOnDay': _grantedOnDay,
      }));
    } catch (e) {
      logError('Could not save the level videos', e);
    }
  }

  @visibleForTesting
  void keepForTest(String id, LevelReading reading) => _readings[id] = reading;
}

final _cueTime = RegExp(r'^\s*(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{3})\s+-->\s+(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{3})');

/// A cue's start and end in milliseconds from its WebVTT timing line.
(int, int)? cueTimes(String timing) {
  final m = _cueTime.firstMatch(timing);
  if (m == null) return null;
  int at(int from) => ((int.tryParse(m[from] ?? '0') ?? 0) * 3600 + int.parse(m[from + 1]!) * 60 + int.parse(m[from + 2]!)) * 1000 + int.parse(m[from + 3]!);
  return (at(1), at(5));
}

/// The lengths, in seconds, a learner at [tier] most often keeps
/// watching: shorter for beginners. Only a nudge in the order.
(int, int) preferredSeconds(int tier) => switch (tier) {
      0 => (120, 720),
      1 => (180, 1500),
      _ => (300, 2700),
    };

/// How well a video known to the share [reading] fits [band]: nearest its
/// middle first, with less weight for many new words a minute, speech
/// faster than everyday, hard minutes, and subtitles that look broken;
/// a little more for a length the learner's [tier] suits and a channel
/// whose videos fitted before ([channelFit]). Graded listening ([band]
/// null) is ordered by nearness to 96 % known whatever its band.
double levelVideoScore(VideoLevel? band, LevelReading reading, {int? seconds, int tier = 1, double? channelFit}) {
  final known = reading.known ?? 0;
  final target = switch (band) {
    VideoLevel.easy => 0.985,
    VideoLevel.right || null => 0.965,
    VideoLevel.challenging => 0.925,
    VideoLevel.hard => 0.85,
    VideoLevel.tooHard => 0.75,
  };
  var score = -(known - target).abs();
  if (reading.newPerMinute > 8) score -= 0.002 * (reading.newPerMinute - 8);
  if (reading.pace == SpeechPace.fast) score -= 0.01;
  if (reading.hardestMinute case final hardest? when hardest < known - 0.12) score -= 0.01;
  if (reading.unreliable) score -= 1;
  if (seconds != null) {
    final (from, to) = preferredSeconds(tier);
    if (seconds >= from && seconds <= to) score += 0.004;
  }
  if (channelFit != null) score += 0.005 * channelFit;
  return score;
}

class _Pending {
  _Pending(Future<String?> answer) {
    future = answer.then((line) {
      this.line = line;
      done = true;
    }, onError: (Object _) {
      done = true;
    });
  }

  late final Future<void> future;
  String? line;
  bool done = false;
}

/// Whether the language core is there to read subtitles and count words.
bool get levelVideosAvailable => NativeCore.instance != null;
