import 'dart:convert';

/// The follow list read from an exported file.
class SubscriptionImport {
  const SubscriptionImport(this.channels, {this.skipped = 0, this.format});

  /// Channel id and name, each channel once, in file order.
  final List<(String id, String name)> channels;

  /// Entries that could not be used: another service, a handle with no
  /// channel id, or a damaged row.
  final int skipped;

  /// What the file was taken for, or null when it was none of the formats.
  final SubscriptionFormat? format;
}

enum SubscriptionFormat { newPipe, freeTube, youtubeJson, csv, opml }

final _channelId = RegExp(r'^UC[\w-]{22}$');
final _inUrl = RegExp(r'(?:/channel/|[?&]channel_id=)(UC[\w-]{22})');

/// Reads a NewPipe, FreeTube or YouTube JSON export, a Google Takeout or
/// FreeTube CSV, or an OPML file, deciding by the content. Never throws:
/// unreadable input gives an empty list.
SubscriptionImport parseSubscriptions(List<int> bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  text = text.trim();
  if (text.isEmpty) return const SubscriptionImport([]);
  final first = text[0];
  if (first == '{' || first == '[') return _json(text);
  if (first == '<') return _opml(text);
  return _csv(text);
}

String? _idFrom(Object? value) {
  if (value is! String) return null;
  final v = value.trim();
  if (_channelId.hasMatch(v)) return v;
  return _inUrl.firstMatch(v)?.group(1);
}

class _Collector {
  final seen = <String, int>{};
  final channels = <(String, String)>[];
  int skipped = 0;

  void add(String id, String name) {
    final at = seen[id];
    if (at == null) {
      seen[id] = channels.length;
      channels.add((id, name));
    } else if (channels[at].$2.isEmpty && name.isNotEmpty) {
      channels[at] = (id, name);
    }
  }
}

SubscriptionImport _json(String text) {
  final documents = <Object?>[];
  try {
    documents.add(jsonDecode(text));
  } catch (_) {
    // FreeTube's profiles.db holds one JSON object per line.
    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        documents.add(jsonDecode(trimmed));
      } catch (_) {
        documents.add(null);
      }
    }
  }
  final out = _Collector();
  SubscriptionFormat? format;
  var bad = 0;

  void entry(Object? raw, SubscriptionFormat kind) {
    if (raw is! Map) {
      out.skipped++;
      return;
    }
    final service = raw['service_id'];
    if (service != null && service != 0 && service != '0') {
      out.skipped++;
      return;
    }
    final snippet = raw['snippet'];
    final resource = snippet is Map ? snippet['resourceId'] : null;
    final id = _idFrom(raw['id']) ?? _idFrom(raw['channelId']) ?? _idFrom(raw['url']) ?? _idFrom(raw['channelUrl']) ?? (resource is Map ? _idFrom(resource['channelId']) : null);
    if (id == null) {
      out.skipped++;
      return;
    }
    final name = raw['name'] ?? raw['title'] ?? (snippet is Map ? snippet['title'] : null);
    format ??= kind;
    out.add(id, name is String ? name.trim() : '');
  }

  void list(Object? subscriptions, SubscriptionFormat kind) {
    if (subscriptions is! List) return;
    for (final item in subscriptions) {
      entry(item, kind);
    }
  }

  for (final doc in documents) {
    if (doc is Map) {
      final subscriptions = doc['subscriptions'];
      if (subscriptions is List) {
        final newPipe = doc.containsKey('app_version') || (subscriptions.isNotEmpty && subscriptions.first is Map && (subscriptions.first as Map).containsKey('service_id'));
        list(subscriptions, newPipe ? SubscriptionFormat.newPipe : SubscriptionFormat.freeTube);
      } else if (doc['items'] is List) {
        list(doc['items'], SubscriptionFormat.youtubeJson);
      } else {
        bad++;
      }
    } else if (doc is List) {
      list(doc, SubscriptionFormat.youtubeJson);
    } else {
      bad++;
    }
  }
  final usable = out.channels.isNotEmpty || out.skipped > 0;
  return SubscriptionImport(out.channels, skipped: out.skipped + (out.channels.isEmpty ? 0 : bad), format: usable ? (format ?? SubscriptionFormat.freeTube) : null);
}

SubscriptionImport _opml(String text) {
  final out = _Collector();
  var found = false;
  final attribute = RegExp('([\\w:.-]+)\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')');
  for (final tag in RegExp(r'<outline\b([^>]*?)/?>', caseSensitive: false, dotAll: true).allMatches(text)) {
    final attributes = <String, String>{};
    for (final a in attribute.allMatches(tag.group(1)!)) {
      attributes[a.group(1)!.toLowerCase()] = _unescape(a.group(2) ?? a.group(3) ?? '');
    }
    final feed = attributes['xmlurl'];
    if (feed == null || feed.isEmpty) continue;
    found = true;
    final id = _idFrom(feed);
    if (id == null) {
      out.skipped++;
      continue;
    }
    out.add(id, (attributes['title'] ?? attributes['text'] ?? '').trim());
  }
  return SubscriptionImport(out.channels, skipped: out.skipped, format: found ? SubscriptionFormat.opml : null);
}

String _unescape(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);'), (m) {
      final e = m.group(1)!;
      switch (e) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      final code = e[1] == 'x' ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
      return code == null || code > 0x10FFFF ? m.group(0)! : String.fromCharCode(code);
    });

SubscriptionImport _csv(String text) {
  final rows = _csvRows(text);
  final out = _Collector();
  var found = false;
  for (final (i, row) in rows.indexed) {
    if (row.every((c) => c.trim().isEmpty)) continue;
    String? id;
    for (final cell in row) {
      id = _idFrom(cell);
      if (id != null) break;
    }
    if (id == null) {
      // The header line, in whatever language, is not a channel.
      if (i > 0) out.skipped++;
      continue;
    }
    found = true;
    // Takeout and FreeTube both put the title in the third column.
    var name = row.length > 2 ? row[2].trim() : '';
    if (name.isEmpty || _idFrom(name) != null) name = row.length > 1 && _idFrom(row[1]) == null ? row[1].trim() : '';
    out.add(id, name);
  }
  return SubscriptionImport(out.channels, skipped: found ? out.skipped : 0, format: found ? SubscriptionFormat.csv : null);
}

List<List<String>> _csvRows(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  row.add(cell.toString());
  rows.add(row);
  return rows;
}
