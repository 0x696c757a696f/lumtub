import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'translation.dart';

/// Translations kept on this computer for [maxAge], so the same comment,
/// title or subtitle line is not sent again. Only text the person already
/// chose to translate is kept, in the cache folder; 清除缓存 removes it.
class TranslationCache {
  TranslationCache({this.file, this.maxEntries = 3000, this.maxAge = const Duration(days: 7), DateTime Function()? now}) : _now = now ?? DateTime.now;
  final File? file;
  final int maxEntries;
  final Duration maxAge;
  final DateTime Function() _now;

  /// Insertion order is recency: a hit moves the entry to the end.
  final _entries = <String, (String, int)>{};
  Timer? _saveTimer;
  Future<void>? _loading;
  /// Saves and deletions run one after another, so a save that started
  /// before [clear] cannot write the cleared translations back.
  Future<void> _writes = Future.value();
  /// Raised by [clear], so a load still reading drops what it read.
  int _generation = 0;

  /// Off in 无痕模式: translations made meanwhile are used but never written.
  bool persist = true;
  final _private = <String>{};

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final file = this.file;
    if (file == null) return;
    final generation = _generation;
    try {
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map || generation != _generation) return;
      final oldest = _now().subtract(maxAge).millisecondsSinceEpoch;
      for (final MapEntry(:key, :value) in data.entries) {
        if (key is String && value is List && value.length == 2 && value[0] is String && value[1] is int && (value[1] as int) >= oldest) {
          _entries.putIfAbsent(key, () => (value[0] as String, value[1] as int));
        }
      }
      _trim();
    } catch (_) {
      // A damaged file only costs the translations it held.
    }
  }

  static String keyOf(String scope, String target, String text) => '$scope\u0000$target\u0000$text';

  String? get(String scope, String target, String text) {
    final key = keyOf(scope, target, text);
    final hit = _entries.remove(key);
    if (hit == null) return null;
    if (_now().difference(DateTime.fromMillisecondsSinceEpoch(hit.$2)) > maxAge) {
      _scheduleSave();
      return null;
    }
    _entries[key] = hit;
    return hit.$1;
  }

  void put(String scope, String target, String text, String translation) {
    final key = keyOf(scope, target, text);
    _entries.remove(key);
    _entries[key] = (translation, _now().millisecondsSinceEpoch);
    if (persist) {
      _private.remove(key);
    } else {
      _private.add(key);
    }
    _trim();
    if (persist) _scheduleSave();
  }

  int get length => _entries.length;

  /// Forgets every translation and deletes the file once any save already
  /// under way has finished.
  Future<void> clear() {
    _generation++;
    _entries.clear();
    _private.clear();
    _saveTimer?.cancel();
    final file = this.file;
    if (file == null) return Future.value();
    return _write(() async {
      for (final f in [file, File('${file.path}.tmp')]) {
        try {
          await f.delete();
        } on FileSystemException {
          // Not there.
        }
      }
    });
  }

  Future<void> _write(Future<void> Function() step) {
    final next = _writes.then((_) => step()).catchError((Object _) {});
    _writes = next;
    return next;
  }

  void _trim() {
    while (_entries.length > maxEntries) {
      _private.remove(_entries.keys.first);
      _entries.remove(_entries.keys.first);
    }
  }

  void _scheduleSave() {
    if (file == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), () => unawaited(save()));
  }

  Future<void> save() {
    final file = this.file;
    if (file == null) return Future.value();
    _saveTimer?.cancel();
    final generation = _generation;
    final json = jsonEncode({for (final MapEntry(:key, :value) in _entries.entries) if (!_private.contains(key)) key: [value.$1, value.$2]});
    return _write(() async {
      // A clear since this save was asked for wins.
      if (generation != _generation) return;
      try {
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(json);
        if (generation != _generation) {
          await temp.delete();
          return;
        }
        await temp.rename(file.path);
      } catch (_) {
        // The cache is only a saving; translating again still works.
      }
    });
  }
}

/// [inner] with answers kept in [cache] under [scope], which names the
/// service and its settings so another one translates afresh.
class CachingTranslator implements Translator {
  CachingTranslator(this.inner, this.cache, this.scope);
  final Translator inner;
  final TranslationCache cache;
  final String scope;

  @override
  Future<String> translate(String text, String target) async {
    if (text.trim().isEmpty) return text;
    await cache.load();
    final hit = cache.get(scope, target, text);
    if (hit != null) return hit;
    final result = await inner.translate(text, target);
    cache.put(scope, target, text, result);
    return result;
  }
}
