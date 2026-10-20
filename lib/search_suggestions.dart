import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'l10n/l10n.dart';

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
      return _items = [if (data is List) for (final item in data) if (item is String && item.trim().isNotEmpty) item];
    } catch (_) {
      return _items = [];
    }
  }

  Future<void> add(String query) async {
    final text = query.trim();
    if (text.isEmpty) return;
    final list = [text, ...(await items()).where((q) => q != text)].take(limit).toList();
    await _save(list);
  }

  Future<void> remove(String query) async => _save((await items()).where((q) => q != query).toList());

  Future<void> clear() => _save(const []);

  Future<void> _save(List<String> list) async {
    _items = list;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(list));
    } catch (_) {}
  }
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
    } catch (_) {}
    return const [];
  }
}
