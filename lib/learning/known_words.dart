import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_directories.dart' show writeFileAtomic;
import '../app_log.dart';
import 'learning.dart';
import 'review.dart';
import 'vocabulary.dart';
import 'word_token.dart';

/// Words the learner knows: marked as known on a word card, or reviewed
/// until they stay for weeks. Known words lose their reading above the
/// subtitles, so the line gets quieter as the learner gets better; kept
/// in `known.json` beside the vocabulary book.
class KnownWords extends ChangeNotifier {
  KnownWords(this.file, this.book, this.review) {
    review.addListener(_changed);
  }

  /// Goes up with every change, for caches of what depends on it.
  int revision = 0;

  void _changed() {
    revision++;
    notifyListeners();
  }

  final File file;
  final VocabularyBook book;
  final ReviewStore review;
  final Set<String> _keys = {};
  bool _loaded = false;

  static String keyOf(String language, String word) => '$language:${word.toLowerCase()}';
  static String tokenKey(WordToken token) => keyOf(Learning.languageOf(token), token.key);

  int get marked => _keys.length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await review.load();
    try {
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        final words = json is Map ? json['words'] : null;
        if (words is List) _keys.addAll(words.whereType<String>());
      }
    } catch (e) {
      logWarn('Could not read the known words: $e');
    }
    notifyListeners();
  }

  /// Marked as known, or a vocabulary word reviewed until it stays.
  bool knows(WordToken token) {
    if (!token.isWord) return true;
    final language = Learning.languageOf(token);
    if (_keys.contains(keyOf(language, token.key))) return true;
    final state = review.of('$language:${token.key}') ?? review.of('$language:${token.key.toLowerCase()}');
    return state?.known ?? false;
  }

  /// In the vocabulary book and not yet known: a word being learnt.
  bool learning(WordToken token) {
    if (!token.isWord || knows(token)) return false;
    final language = Learning.languageOf(token);
    return book.contains(language, token.key) || book.contains(language, token.key.toLowerCase());
  }

  bool marks(WordToken token) => _keys.contains(tokenKey(token));

  Future<void> mark(WordToken token, bool known) async {
    final key = tokenKey(token);
    if (known ? !_keys.add(key) : !_keys.remove(key)) return;
    _changed();
    try {
      await writeFileAtomic(file, jsonEncode({'version': 1, 'words': _keys.toList()..sort()}));
    } catch (e) {
      logError('Could not save the known words', e);
    }
  }

  /// The words of [tokens] the learner does not know yet, each once.
  Set<String> unknownIn(List<WordToken> tokens) => {for (final t in tokens) if (t.isWord && counts(t) && !knows(t)) tokenKey(t)};

  /// Numbers, names in Latin letters inside other scripts and single
  /// letters say nothing about what is understood.
  static bool counts(WordToken token) {
    if (!_letter.hasMatch(token.text)) return false;
    final language = Learning.languageOf(token);
    return token.text.runes.length > (language == 'zh' || language == 'ja' ? 0 : 1);
  }

  static final _letter = RegExp(r'\p{L}', unicode: true);

  /// A line with exactly one unknown word among at least three: the
  /// easiest line to learn something from.
  bool oneNew(List<WordToken> tokens) {
    final words = tokens.where((t) => t.isWord && counts(t)).length;
    return words >= 3 && unknownIn(tokens).length == 1;
  }
}

final _known = <String, KnownWords>{};

/// The known words kept beside [book].
KnownWords knownWordsOf(VocabularyBook book) => _known.putIfAbsent(
      book.file.path,
      () => KnownWords(File('${book.file.parent.path}${Platform.pathSeparator}known.json'), book, reviewStoreOf(book))..load(),
    );
