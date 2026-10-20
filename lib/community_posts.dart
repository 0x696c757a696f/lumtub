import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'l10n/l10n.dart';

/// A post on a channel's 社区 (posts) tab.
class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.text,
    this.published = '',
    this.likes = '',
    this.comments = '',
    this.images = const [],
    this.video,
    this.poll = const [],
  });

  final String id;
  final String text;
  /// YouTube's own relative time, such as "3天前".
  final String published;
  final String likes;
  final String comments;
  final List<String> images;
  /// A video attached to the post.
  final VideoItem? video;
  /// The choices of an attached poll.
  final List<String> poll;

  String get url => 'https://www.youtube.com/post/$id';
}

/// One page of posts and the token for the next.
class PostPage {
  const PostPage(this.posts, this.continuation);
  final List<CommunityPost> posts;
  final String? continuation;
}

/// Reads a channel's posts from YouTube's web pages. yt-dlp lists only the
/// videos attached to posts, so the posts tab is read the way the YouTube
/// website loads it: the first page from the tab's HTML, later pages from
/// its browse endpoint with the continuation token.
class CommunityPosts {
  CommunityPosts(this._client);
  final http.Client _client;

  static const _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
  static const _headers = {
    'User-Agent': _userAgent,
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    // Skips the EU consent page.
    'Cookie': 'CONSENT=YES+cb; SOCS=CAI',
  };

  String? _apiKey;
  String? _clientVersion;
  String? _visitorData;

  /// The first page of [channel]'s posts.
  Future<PostPage> first(ChannelRef channel) async {
    final response = await _client.get(Uri.parse('${channel.url}/posts?hl=zh-CN'), headers: _headers).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    _apiKey = RegExp(r'"INNERTUBE_API_KEY":"([^"]+)"').firstMatch(html)?.group(1);
    _clientVersion = RegExp(r'"INNERTUBE_CLIENT_VERSION":"([^"]+)"').firstMatch(html)?.group(1);
    _visitorData = RegExp(r'"VISITOR_DATA":"([^"]+)"').firstMatch(html)?.group(1);
    final data = initialData(html);
    if (data == null) throw FormatException(tr('没有在频道页面里找到帖子数据'));
    return parse(data);
  }

  /// The page after the one that gave [continuation].
  Future<PostPage> next(String continuation) async {
    final key = _apiKey;
    final query = key == null ? '?prettyPrint=false' : '?key=$key&prettyPrint=false';
    final response = await _client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/browse$query'),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB',
                'clientVersion': _clientVersion ?? '2.20251001.00.00',
                'hl': 'zh-CN',
                if (_visitorData != null) 'visitorData': _visitorData,
              },
            },
            'continuation': continuation,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
    return parse(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  /// The `ytInitialData` object embedded in a YouTube page.
  static Object? initialData(String html) {
    final marker = RegExp(r'(?:var ytInitialData|window\["ytInitialData"\])\s*=\s*').firstMatch(html);
    if (marker == null) return null;
    final start = html.indexOf('{', marker.end);
    if (start < 0) return null;
    // Find the matching brace, skipping braces inside strings.
    var depth = 0;
    var inString = false;
    for (var i = start; i < html.length; i++) {
      final c = html.codeUnitAt(i);
      if (inString) {
        if (c == 0x5C) {
          i++;
        } else if (c == 0x22) {
          inString = false;
        }
      } else if (c == 0x22) {
        inString = true;
      } else if (c == 0x7B) {
        depth++;
      } else if (c == 0x7D && --depth == 0) {
        try {
          return jsonDecode(html.substring(start, i + 1));
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  /// Posts and the continuation token anywhere in a browse response. The
  /// tree is walked instead of followed by path, so layout changes around
  /// the posts do not break reading them.
  static PostPage parse(Object? data) {
    final posts = <CommunityPost>[];
    final seen = <String>{};
    String? continuation;
    void walk(Object? node) {
      if (node is List) {
        for (final child in node) {
          walk(child);
        }
        return;
      }
      if (node is! Map) return;
      final post = node['backstagePostRenderer'] ?? node['postRenderer'];
      if (post is Map) {
        final parsed = _post(post);
        if (parsed != null && seen.add(parsed.id)) posts.add(parsed);
        return;
      }
      final token = _path(node, ['continuationItemRenderer', 'continuationEndpoint', 'continuationCommand', 'token']);
      if (token is String) continuation = token;
      for (final value in node.values) {
        if (value is Map || value is List) walk(value);
      }
    }

    walk(data);
    return PostPage(posts, continuation);
  }

  static Object? _path(Object? node, List<Object> keys) {
    var current = node;
    for (final key in keys) {
      if (key is String && current is Map) {
        current = current[key];
      } else if (key is int && current is List && key < current.length) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  /// The text of a YouTube "runs" or "simpleText" object.
  static String text(Object? node) {
    if (node is! Map) return '';
    final simple = node['simpleText'];
    if (simple is String) return simple;
    final runs = node['runs'];
    if (runs is List) return runs.whereType<Map>().map((r) => r['text']?.toString() ?? '').join();
    final content = node['content'];
    return content is String ? content : '';
  }

  static String? _image(Object? renderer) {
    final thumbnails = _path(renderer, ['image', 'thumbnails']);
    if (thumbnails is! List || thumbnails.isEmpty) return null;
    final url = (thumbnails.last as Map)['url']?.toString() ?? '';
    final full = url.startsWith('//') ? 'https:$url' : url;
    return full.startsWith('https://') ? full : null;
  }

  static CommunityPost? _post(Map post) {
    final id = post['postId']?.toString() ?? '';
    if (id.isEmpty) return null;
    final attachment = post['backstageAttachment'];
    final images = <String>[];
    final single = _image(_path(attachment, ['backstageImageRenderer']));
    if (single != null) images.add(single);
    final multi = _path(attachment, ['postMultiImageRenderer', 'images']);
    if (multi is List) {
      for (final item in multi) {
        final url = _image(_path(item, ['backstageImageRenderer']));
        if (url != null) images.add(url);
      }
    }
    VideoItem? video;
    final videoRenderer = _path(attachment, ['videoRenderer']);
    if (videoRenderer is Map && videoRenderer['videoId'] is String) {
      final videoId = videoRenderer['videoId'] as String;
      if (RegExp(r'^[\w-]{11}$').hasMatch(videoId)) {
        final length = text(videoRenderer['lengthText']).split(':').map(int.tryParse).toList();
        int? seconds;
        if (length.isNotEmpty && length.every((n) => n != null)) seconds = length.fold<int>(0, (total, n) => total * 60 + n!);
        video = VideoItem(
          id: videoId,
          title: text(videoRenderer['title']),
          channel: text(videoRenderer['ownerText']),
          duration: seconds,
          url: 'https://www.youtube.com/watch?v=$videoId',
        );
      }
    }
    final choices = _path(attachment, ['pollRenderer', 'choices']);
    return CommunityPost(
      id: id,
      text: text(post['contentText']),
      published: text(post['publishedTimeText']),
      likes: text(post['voteCount']),
      comments: text(_path(post, ['actionButtons', 'commentActionButtonsRenderer', 'replyButton', 'buttonRenderer', 'text'])),
      images: images,
      video: video,
      poll: choices is List ? [for (final c in choices) text(_path(c, ['text']))].where((t) => t.isNotEmpty).toList() : const [],
    );
  }
}
