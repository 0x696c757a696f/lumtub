import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_directories.dart' show writeFileAtomic;
import '../app_log.dart';

/// A word kept in the vocabulary book, with the line it was heard in and
/// where in which video.
@immutable
class VocabularyWord {
  const VocabularyWord({
    required this.word,
    required this.language,
    this.reading = '',
    this.meaning = '',
    this.sentence = '',
    this.translation = '',
    this.videoId = '',
    this.videoTitle = '',
    this.at = Duration.zero,
    required this.added,
  });

  final String word;
  final String language;
  final String reading;
  final String meaning;
  final String sentence;
  final String translation;
  final String videoId;
  final String videoTitle;
  final Duration at;
  final DateTime added;

  String get key => '$language:$word';

  /// The video at the moment the line was spoken, a little before it.
  String get link {
    if (videoId.isEmpty) return '';
    final seconds = at.inSeconds > 1 ? at.inSeconds - 1 : 0;
    return 'https://www.youtube.com/watch?v=$videoId&t=${seconds}s';
  }

  Map<String, Object?> toJson() => {
        'word': word,
        'language': language,
        if (reading.isNotEmpty) 'reading': reading,
        if (meaning.isNotEmpty) 'meaning': meaning,
        if (sentence.isNotEmpty) 'sentence': sentence,
        if (translation.isNotEmpty) 'translation': translation,
        if (videoId.isNotEmpty) 'video': videoId,
        if (videoTitle.isNotEmpty) 'title': videoTitle,
        'ms': at.inMilliseconds,
        'added': added.toUtc().toIso8601String(),
      };

  static VocabularyWord? fromJson(Object? json) {
    if (json is! Map) return null;
    final word = json['word'];
    if (word is! String || word.isEmpty) return null;
    String text(String name) => json[name] is String ? json[name] as String : '';
    return VocabularyWord(
      word: word,
      language: text('language').isEmpty ? 'zh' : text('language'),
      reading: text('reading'),
      meaning: text('meaning'),
      sentence: text('sentence'),
      translation: text('translation'),
      videoId: text('video'),
      videoTitle: text('title'),
      at: Duration(milliseconds: json['ms'] is int ? json['ms'] as int : 0),
      added: DateTime.tryParse(text('added')) ?? DateTime.now(),
    );
  }
}

/// The vocabulary book, newest first, kept in `vocabulary.json` in the
/// data folder. One entry per word: adding a word again keeps the newer
/// line and moves it to the top.
class VocabularyBook extends ChangeNotifier {
  VocabularyBook(this.file);

  final File file;
  final List<VocabularyWord> _words = [];
  bool _loaded = false;

  List<VocabularyWord> get words => List.unmodifiable(_words);

  bool contains(String language, String word) => _words.any((w) => w.language == language && w.word == word);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      final list = json is Map ? json['words'] : null;
      if (list is List) _words.addAll(list.map(VocabularyWord.fromJson).whereType<VocabularyWord>());
      notifyListeners();
    } catch (e) {
      logWarn('Could not read the vocabulary book: $e');
    }
  }

  Future<void> add(VocabularyWord word) async {
    await load();
    _words.removeWhere((w) => w.key == word.key);
    _words.insert(0, word);
    notifyListeners();
    await _save();
  }

  Future<void> remove(VocabularyWord word) async {
    _words.removeWhere((w) => w.key == word.key);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      await writeFileAtomic(file, jsonEncode({'version': 1, 'words': [for (final w in _words) w.toJson()]}));
    } catch (e) {
      logError('Could not save the vocabulary book', e);
    }
  }
}

/// [words] as CSV with a header row, for spreadsheets. Starts with a byte
/// order mark, so spreadsheet programs read it as UTF-8.
String vocabularyCsv(List<VocabularyWord> words) {
  String field(String text) {
    final clean = text.replaceAll('\r\n', '\n');
    return RegExp(r'[",\n\r]').hasMatch(clean) || clean != clean.trim() ? '"${clean.replaceAll('"', '""')}"' : clean;
  }

  final out = StringBuffer('﻿word,reading,meaning,sentence,translation,video,time,link\r\n');
  for (final w in words) {
    out.write([w.word, w.reading, w.meaning, w.sentence, w.translation, w.videoTitle, clockOf(w.at), w.link].map(field).join(','));
    out.write('\r\n');
  }
  return out.toString();
}

/// [words] as a file Anki imports (File › Import): the word on the front;
/// the reading, meaning, the line with the word in bold, its translation
/// and a link back to that moment of the video on the back.
String vocabularyAnki(List<VocabularyWord> words) {
  String html(String text) => const HtmlEscape(HtmlEscapeMode.element).convert(text).replaceAll('\t', ' ').replaceAll(RegExp(r'\r?\n'), '<br>');
  final out = StringBuffer('#separator:tab\n#html:true\n#columns:Front\tBack\tTags\n#tags column:3\n');
  for (final w in words) {
    final sentence = html(w.sentence).replaceAll(html(w.word), '<b>${html(w.word)}</b>');
    final back = [
      if (w.reading.isNotEmpty) html(w.reading),
      if (w.meaning.isNotEmpty) html(w.meaning),
      if (w.sentence.isNotEmpty) '<br>$sentence',
      if (w.translation.isNotEmpty) '<i>${html(w.translation)}</i>',
      if (w.link.isNotEmpty) '<a href="${html(w.link)}">${html(w.videoTitle.isEmpty ? w.link : '${w.videoTitle} ${clockOf(w.at)}')}</a>',
    ].join('<br>');
    out.write('${html(w.word)}\t$back\tlumtub lumtub::${w.language}\n');
  }
  return out.toString();
}

String clockOf(Duration d) {
  final s = d.inSeconds;
  final clock = '${(s ~/ 60) % 60}:${(s % 60).toString().padLeft(2, '0')}';
  return s >= 3600 ? '${s ~/ 3600}:${clock.padLeft(5, '0')}' : clock;
}
