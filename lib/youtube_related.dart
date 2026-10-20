import 'dart:convert';

import 'package:http/http.dart' as http;

import 'l10n/l10n.dart';
import 'models.dart';

/// The videos YouTube suggests next to a video, from the same request the
/// watch page makes. No account is involved.
class YoutubeRelated {
  YoutubeRelated(this._client);
  final http.Client _client;

  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Cookie': 'CONSENT=YES+cb; SOCS=CAI',
    'Content-Type': 'application/json',
  };

  final _cache = <String, List<VideoItem>>{};

  Future<List<VideoItem>> forVideo(String videoId) async {
    final cached = _cache[videoId];
    if (cached != null) return cached;
    final response = await _client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/next?prettyPrint=false'),
          headers: _headers,
          body: jsonEncode({
            'context': {
              'client': {'clientName': 'WEB', 'clientVersion': '2.20251001.00.00', 'hl': 'zh-CN'},
            },
            'videoId': videoId,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
    final items = parse(jsonDecode(utf8.decode(response.bodyBytes))).where((item) => item.id != videoId).toList();
    if (_cache.length > 100) _cache.clear();
    return _cache[videoId] = items;
  }

  /// The videos in a `/next` response, in YouTube's order: the older
  /// `compactVideoRenderer` and the newer `lockupViewModel` shapes.
  static List<VideoItem> parse(Object? data) {
    final items = <VideoItem>[];
    final seen = <String>{};
    void add(VideoItem? item) {
      if (item != null && seen.add(item.id)) items.add(item);
    }

    void walk(Object? node) {
      if (node is Map) {
        final compact = node['compactVideoRenderer'];
        final lockup = node['lockupViewModel'];
        if (compact is Map) {
          add(_compact(compact));
        } else if (lockup is Map) {
          add(_lockup(lockup));
        } else {
          for (final value in node.values) {
            walk(value);
          }
        }
      } else if (node is List) {
        for (final value in node) {
          walk(value);
        }
      }
    }

    walk(data);
    return items;
  }

  static VideoItem? _compact(Map node) {
    final id = node['videoId'];
    if (id is! String || id.length != 11) return null;
    final byline = (node['longBylineText'] ?? node['shortBylineText']) as Object?;
    final live = _text(node['badges']).contains('直播') || _text(node['badges']).toUpperCase().contains('LIVE') || node['viewCountText'] is Map && _text(node['viewCountText']).contains('正在观看');
    return VideoItem(
      id: id,
      title: _text(node['title']),
      channel: _text(byline),
      channelId: _browseId(byline),
      duration: _seconds(_text(node['lengthText'])),
      viewCount: _count(_text(node['viewCountText'])),
      url: 'https://www.youtube.com/watch?v=$id',
      liveStatus: live ? 'is_live' : null,
    );
  }

  static VideoItem? _lockup(Map node) {
    final id = node['contentId'];
    if (id is! String || id.length != 11) return null;
    final type = node['contentType'];
    if (type is String && type != 'LOCKUP_CONTENT_TYPE_VIDEO') return null;
    final metadata = _at(node, ['metadata', 'lockupMetadataViewModel']);
    final title = _text(_at(metadata, ['title']));
    final rows = _at(metadata, ['metadata', 'contentMetadataViewModel', 'metadataRows']);
    final parts = <String>[
      if (rows is List)
        for (final row in rows)
          for (final part in (_at(row, ['metadataParts']) as List?) ?? const []) _text(_at(part, ['text'])),
    ].where((p) => p.isNotEmpty).toList();
    // The first row names the channel; the next holds views and age.
    final channel = parts.isEmpty ? '' : parts.first;
    final views = parts.skip(1).map(_count).whereType<int>().firstOrNull;
    final badges = <String>[];
    void badgesIn(Object? n) {
      if (n is Map) {
        final badge = n['thumbnailBadgeViewModel'];
        if (badge is Map) badges.add(_text(badge['text']));
        n.values.forEach(badgesIn);
      } else if (n is List) {
        n.forEach(badgesIn);
      }
    }

    badgesIn(node['contentImage']);
    final live = badges.any((b) => b.contains('直播') || b.toUpperCase() == 'LIVE');
    return VideoItem(
      id: id,
      title: title,
      channel: channel,
      channelId: _browseId(_at(metadata, ['image'])),
      duration: badges.map(_seconds).whereType<int>().firstOrNull,
      viewCount: views,
      url: 'https://www.youtube.com/watch?v=$id',
      liveStatus: live ? 'is_live' : null,
    );
  }

  static Object? _at(Object? node, List<String> path) {
    var current = node;
    for (final key in path) {
      if (current is! Map) return null;
      current = current[key];
    }
    return current;
  }

  /// Text from YouTube's `simpleText`, `runs` or `content` shapes.
  static String _text(Object? node) {
    if (node is String) return node;
    if (node is Map) {
      final simple = node['simpleText'] ?? node['content'];
      if (simple is String) return simple;
      final runs = node['runs'];
      if (runs is List) return runs.map((r) => r is Map ? '${r['text'] ?? ''}' : '').join();
      final label = _at(node, ['accessibility', 'accessibilityData', 'label']);
      if (label is String) return label;
    }
    if (node is List) return node.map(_text).join(' ');
    return '';
  }

  /// The first `UC…` channel id under [node].
  static String? _browseId(Object? node) {
    if (node is Map) {
      final id = node['browseId'];
      if (id is String && id.startsWith('UC')) return id;
      for (final value in node.values) {
        final found = _browseId(value);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _browseId(value);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// `1:02:03` or `4:05` as seconds.
  static int? _seconds(String text) {
    final match = RegExp(r'^\s*(?:(\d+):)?(\d{1,2}):(\d{2})\s*$').firstMatch(text);
    if (match == null) return null;
    return int.parse(match.group(1) ?? '0') * 3600 + int.parse(match.group(2)!) * 60 + int.parse(match.group(3)!);
  }

  /// View counts such as `1,234 次观看`, `12万次观看`, `3.4亿` or `1.2M views`.
  static int? _count(String text) {
    final match = RegExp(r'([\d.,]+)\s*([万亿KMB]?)', caseSensitive: false).firstMatch(text);
    if (match == null || !RegExp(r'观看|views|次', caseSensitive: false).hasMatch(text)) return null;
    final number = double.tryParse(match.group(1)!.replaceAll(',', ''));
    if (number == null) return null;
    final factor = switch (match.group(2)!.toUpperCase()) {
      '万' => 1e4,
      '亿' => 1e8,
      'K' => 1e3,
      'M' => 1e6,
      'B' => 1e9,
      _ => 1.0,
    };
    return (number * factor).round();
  }
}
