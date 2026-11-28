import 'dart:convert';
import 'dart:io';

import 'app_log.dart';
import 'translation.dart';

/// Explore's search phrases in other languages, kept on disk: the zones'
/// phrases are the same every time, so each is asked of a translator once
/// per language, and a page whose zones were translated before searches in
/// its language even while the translators refuse (user log, 0.2.53: every
/// one of 42 searches put into Spanish was refused, so all were searched
/// in English and the filter kept 5 of 400 videos).
///
/// The built-in zones' phrases come translated with the app
/// (assets/search_phrases.json, made by .github/scripts/search_phrases.py):
/// [bundled] reads them, and only other phrases are asked.
class SearchPhrases {
  SearchPhrases(this._translator, {File? file, Future<String> Function()? bundled})
      : _file = file,
        _bundledText = bundled;
  final Translator _translator;
  final File? _file;
  final Future<String> Function()? _bundledText;
  Future<Map<String, Map<String, String>>>? _bundled;

  Future<Map<String, Map<String, String>>> _readBundled() async {
    final read = _bundledText;
    if (read == null) return const {};
    try {
      // The phrase list once, then each language's translations in its
      // order ('' for none).
      final data = jsonDecode(await read());
      if (data is! Map || data['phrases'] is! List) return _mapsOf(data);
      final phrases = (data['phrases'] as List).whereType<String>().toList();
      return {
        for (final MapEntry(:key, :value) in data.entries)
          if (key is String && key != 'phrases' && value is List && value.length == phrases.length)
            key: {
              for (final (i, t) in value.indexed)
                if (t is String && t.isNotEmpty) phrases[i]: t
            },
      };
    } catch (e) {
      logWarn('Could not read the bundled explore search phrases: $e');
      return const {};
    }
  }

  static Map<String, Map<String, String>> _mapsOf(Object? data) => {
        if (data is Map)
          for (final MapEntry(:key, :value) in data.entries)
            if (key is String && value is Map)
              key: {
                for (final e in value.entries)
                  if (e.key is String && e.value is String) e.key as String: e.value as String
              },
      };

  /// Lines asked in one request.
  static const linesPerRequest = 30;

  Map<String, Map<String, String>>? _known;

  Map<String, Map<String, String>> _load() {
    if (_known case final known?) return known;
    var known = <String, Map<String, String>>{};
    try {
      known = _mapsOf(jsonDecode(_file?.readAsStringSync() ?? '{}'));
    } catch (_) {}
    return _known = known;
  }

  void _save() {
    final file = _file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      final next = File('${file.path}.tmp')..writeAsStringSync(jsonEncode(_known), flush: true);
      next.renameSync(file.path);
    } catch (e) {
      logWarn('Could not keep the explore search phrases: $e');
    }
  }

  /// [phrases] in [target], those known at once and the rest asked together,
  /// [linesPerRequest] at a time. A phrase the translator refused is left
  /// out of the answer; [failure] is told why, once.
  Future<Map<String, String>> translate(Iterable<String> phrases, String target,
      {void Function(Object error)? failure}) async {
    final bundled = (await (_bundled ??= _readBundled()))[target] ?? const <String, String>{};
    final known = _load().putIfAbsent(target, () => {});
    final missing = {
      for (final p in phrases)
        if (p.trim().isNotEmpty && !bundled.containsKey(p) && !known.containsKey(p)) p
    }.toList();
    var added = false;
    for (var i = 0; i < missing.length; i += linesPerRequest) {
      final asked = missing.sublist(i, (i + linesPerRequest).clamp(0, missing.length));
      try {
        final lines = (await _translator
                .translate(asked.join('\n'), target)
                .timeout(const Duration(seconds: 15)))
            .split('\n');
        if (lines.length != asked.length) {
          throw StateError('${lines.length} lines for ${asked.length} phrases');
        }
        for (final (j, phrase) in asked.indexed) {
          final line = lines[j].trim();
          if (line.isNotEmpty) {
            known[phrase] = line;
            added = true;
          }
        }
      } catch (e) {
        failure?.call(e);
        break;
      }
    }
    if (added) _save();
    return {
      for (final p in phrases)
        if (bundled[p] ?? known[p] case final t?) p: t
    };
  }
}
