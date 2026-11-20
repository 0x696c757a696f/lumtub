import 'dart:convert';

import '../local_db.dart' show callCoreJson;

/// A dictionary line found for a key, and whether the key is one of its
/// word's forms rather than the word itself.
typedef FoundLine = ({String line, bool form});

/// Where a dictionary's lines come from: the core's SQLite file
/// ([CoreLexicon]), or the word list in memory (tests, and the packs not
/// moved to SQLite yet).
abstract class LineSource {
  /// The lines for [key] as written, or else in lower case; words first,
  /// then the words [key] is a form of.
  List<FoundLine> find(String key);

  int get size;
}

/// A dictionary in the core (lexicon.rs): looked up on disk, so it takes
/// no memory to speak of however many languages are installed.
class CoreLexicon implements LineSource {
  CoreLexicon._(this.language, this.size);

  final String language;

  @override
  final int size;

  final _cache = <String, List<FoundLine>>{};

  /// Opens [path] as [language]'s dictionary; throws when the core cannot.
  static CoreLexicon open(String language, String path) {
    final answer = callCoreJson('lumtub_lexicon_open', jsonEncode({'language': language, 'path': path}));
    if (answer['error'] != null) throw StateError('${answer['error']}');
    return CoreLexicon._(language, (answer['words'] as num?)?.toInt() ?? 0);
  }

  static void close(String language) => callCoreJson('lumtub_lexicon_close', jsonEncode({'language': language}));

  @override
  List<FoundLine> find(String key) {
    final cached = _cache[key];
    if (cached != null) return cached;
    final answer = callCoreJson('lumtub_lexicon_find', jsonEncode({'language': language, 'keys': [key]}));
    final lists = answer['found'];
    final found = <FoundLine>[
      if (lists is List && lists.isNotEmpty && lists.first is List)
        for (final row in lists.first as List)
          if (row is Map && row['line'] is String) (line: row['line'] as String, form: row['form'] == true),
    ];
    // Subtitles repeat words; a few thousand cached keep lookups cheap.
    if (_cache.length > 4000) _cache.clear();
    return _cache[key] = found;
  }
}

/// A word list in memory, indexed like the core's SQLite file: each
/// word as written and in lower case, and each form [formsOf] gives.
class MemoryLines implements LineSource {
  MemoryLines(Iterable<String> lines, {Iterable<String> Function(String line)? formsOf}) {
    for (final line in lines) {
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      final word = line.substring(0, tab);
      final at = _lines.length;
      _lines.add(line);
      for (final key in {word, word.toLowerCase()}) {
        (_words[key] ??= []).add(at);
      }
      for (final form in formsOf?.call(line) ?? const <String>[]) {
        if (form.isEmpty || form == word) continue;
        for (final key in {form, form.toLowerCase()}) {
          final list = _forms[key] ??= [];
          if (!list.contains(at)) list.add(at);
        }
      }
    }
  }

  final _lines = <String>[];
  final _words = <String, List<int>>{};
  final _forms = <String, List<int>>{};

  @override
  int get size => _lines.length;

  List<FoundLine> _exact(String key) {
    final words = _words[key] ?? const <int>[];
    return [
      for (final at in words) (line: _lines[at], form: false),
      for (final at in _forms[key] ?? const <int>[])
        if (!words.contains(at)) (line: _lines[at], form: true),
    ];
  }

  @override
  List<FoundLine> find(String key) {
    final found = _exact(key);
    if (found.isNotEmpty) return found;
    final lower = key.toLowerCase();
    return lower == key ? found : _exact(lower);
  }
}
