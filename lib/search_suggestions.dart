import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'app_directories.dart';
import 'bounded_get.dart';
import 'native_core.dart';
import 'l10n/l10n.dart';
import 'app_log.dart';

/// Searches typed before, kept on this computer only, newest first.
class SearchHistory {
  SearchHistory(this.file);
  final File file;
  static const limit = 50;

  List<String>? _items;

  Future<List<String>> items() async {
    final cached = _items;
    if (cached != null) return cached;
    try {
      final data = jsonDecode(await file.readAsString());
      return _items ??= [if (data is List) for (final item in data) if (item is String && item.trim().isNotEmpty) item];
    } catch (_) {
      return _items ??= [];
    }
  }

  final _writes = WriteQueue();

  Future<void> add(String query) async {
    final text = query.trim();
    if (text.isEmpty) return;
    final epoch = _cleared;
    await items();
    if (epoch != _cleared) return;
    await _save([text, ...(_items ?? const []).where((q) => q != text)].take(limit).toList());
  }

  Future<void> remove(String query) async {
    final epoch = _cleared;
    await items();
    if (epoch != _cleared) return;
    await _save((_items ?? const []).where((q) => q != query).toList());
  }

  /// Counts clears, so an add or remove that was waiting for the file does not bring old entries back.
  int _cleared = 0;

  Future<void> clear() {
    _cleared++;
    _items = [];
    return _persist();
  }

  /// Updates memory at once, then writes in order.
  Future<void> _save(List<String> list) {
    _items = list;
    return _persist();
  }

  Future<void> _persist() => _writes.run(() async {
        try {
          await file.parent.create(recursive: true);
          await file.writeAsString(jsonEncode(_items ?? const []), flush: true);
        } catch (e) {
          logWarn('Could not save the search suggestions: $e');
        }
      });
}

/// YouTube's search suggestions for what has been typed so far, from the
/// same completion service the YouTube website uses.
class SearchSuggestions {
  SearchSuggestions(this._client);
  final http.Client _client;

  /// The answers to the latest [cacheSize] texts, the least recently asked
  /// first.
  final _cache = <String, List<String>>{};
  static const cacheSize = 200;

  /// The most an answer may be: a real one is well under 2 KB.
  static const maxAnswer = 64 << 10;

  /// How many suggestions are kept, and how long each may be.
  static const maxSuggestions = 20;
  static const maxLength = 200;

  Future<List<String>> forQuery(String query) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    final cached = _cache.remove(text);
    if (cached != null) return _cache[text] = cached;
    try {
      final uri = Uri.https('suggestqueries-clients6.youtube.com', '/complete/search', {'client': 'firefox', 'ds': 'yt', 'hl': youtubeHl, 'ie': 'utf-8', 'oe': 'utf-8', 'q': text});
      final (status, body) = await getBounded(_client, uri, limit: maxAnswer).timeout(const Duration(seconds: 4));
      if (status != 200) return const [];
      final list = parseBytes(body);
      _cache[text] = list;
      while (_cache.length > cacheSize) {
        _cache.remove(_cache.keys.first);
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// The suggestions in the answer [body], read by the core when there is
  /// one.
  static List<String> parseBytes(List<int> body) {
    if (NativeCore.instance?.searchSuggestions(body) case final json?) return (jsonDecode(json) as List).cast<String>();
    return parse(utf8.decode(body, allowMalformed: true));
  }

  /// `["query", ["suggestion", …], …]`.
  static List<String> parse(String body) {
    try {
      final data = jsonDecode(body);
      if (data is List && data.length > 1 && data[1] is List) {
        return [for (final s in data[1] as List) if (s is String && s.runes.length <= maxLength) s].take(maxSuggestions).toList();
      }
    } catch (e) {
      logDebug(() => 'The suggestion answer could not be read: $e');
    }
    return const [];
  }
}
