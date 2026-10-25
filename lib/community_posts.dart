import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'native_core.dart';
import 'l10n/l10n.dart';
import 'youtube_web.dart';

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

  static Map<String, String> get _headers => {
    'User-Agent': YoutubeWeb.userAgent,
    'Accept-Language': youtubeAcceptLanguage,
    // Skips the EU consent page.
    'Cookie': 'CONSENT=YES+cb; SOCS=CAI',
  };

  String? _apiKey;
  String? _clientVersion;
  String? _visitorData;

  /// The first page of [channel]'s posts.
  Future<PostPage> first(ChannelRef channel) async {
    final response = await _client.get(Uri.parse('${channel.url}/posts?hl=$youtubeHl'), headers: _headers).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    _apiKey = RegExp(r'"INNERTUBE_API_KEY":"([^"]+)"').firstMatch(html)?.group(1);
    _clientVersion = RegExp(r'"INNERTUBE_CLIENT_VERSION":"([^"]+)"').firstMatch(html)?.group(1);
    _visitorData = RegExp(r'"VISITOR_DATA":"([^"]+)"').firstMatch(html)?.group(1);
    final page = await _readInBackground(html);
    if (page == null) throw FormatException(tr('没有在频道页面里找到帖子数据'));
    return page;
  }

  /// The page after the one that gave [continuation].
  Future<PostPage> next(String continuation) async {
    final key = _apiKey;
    final query = key == null ? '?prettyPrint=false' : '?key=$key&prettyPrint=false';
    final response = await _client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/browse$query'),
          headers: YoutubeWeb.apiHeaders(clientVersion: _clientVersion, acceptLanguage: youtubeAcceptLanguage),
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB',
                'clientVersion': _clientVersion ?? YoutubeWeb.clientVersion,
                'hl': youtubeHl,
                if (_visitorData != null) 'visitorData': _visitorData,
              },
            },
            'continuation': continuation,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
    return await _readInBackground(utf8.decode(response.bodyBytes)) ?? const PostPage([], null);
  }

  // A channel page runs to a megabyte or two.
  static Future<PostPage?> _readInBackground(String body) => Isolate.run(() => read(body));

  /// Posts and the continuation token of a browse response, or of the
  /// `ytInitialData` in the HTML page [body]; read by the native core. Null
  /// when there is neither, or without the core.
  static PostPage? read(String body) {
    final core = NativeCore.instance;
    final page = core == null ? null : jsonDecode(core.take(core.withText(body, core.youtubePosts)) ?? 'null');
    if (page is! Map<String, dynamic>) return null;
    CommunityPost post(Map<String, dynamic> p) {
      final video = p['video'] as Map<String, dynamic>?;
      final id = video?['id'] as String?;
      return CommunityPost(
        id: p['id'] as String,
        text: p['text'] as String,
        published: p['published'] as String,
        likes: p['likes'] as String,
        comments: p['comments'] as String,
        images: (p['images'] as List).cast<String>(),
        video: id == null ? null : VideoItem(id: id, title: video!['title'] as String, channel: video['channel'] as String, duration: (video['duration'] as num?)?.toInt(), url: 'https://www.youtube.com/watch?v=$id'),
        poll: (p['poll'] as List).cast<String>(),
      );
    }

    return PostPage([for (final p in (page['posts'] as List).cast<Map<String, dynamic>>()) post(p)], page['continuation'] as String?);
  }

  @visibleForTesting
  static PostPage parse(Object? data) => read(jsonEncode(data)) ?? const PostPage([], null);
}
