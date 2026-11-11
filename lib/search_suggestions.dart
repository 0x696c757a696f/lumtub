import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'app_directories.dart';
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
  final _cache = <String, List<String>>{};

  Future<List<String>> forQuery(String query) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    final cached = _cache[text];
    if (cached != null) return cached;
    try {
      final uri = Uri.https('suggestqueries-clients6.youtube.com', '/complete/search', {'client': 'firefox', 'ds': 'yt', 'hl': youtubeHl, 'ie': 'utf-8', 'oe': 'utf-8', 'q': text});
      final response = await _client.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return const [];
      final list = parse(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (_cache.length > 200) _cache.clear();
      return _cache[text] = list;
    } catch (_) {
      return const [];
    }
  }

  /// `["query", ["suggestion", …], …]`.
  static List<String> parse(String body) {
    try {
      final data = jsonDecode(body);
      if (data is List && data.length > 1 && data[1] is List) return [for (final s in data[1] as List) if (s is String) s];
    } catch (e) {
      logDebug(() => 'The suggestion answer could not be read: $e');
    }
    return const [];
  }
}
