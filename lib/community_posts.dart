import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'native_core.dart';
import 'l10n/l10n.dart';
import 'youtube_comments.dart';
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
    this.rating,
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
  /// Liking it, in pages loaded signed in.
  final CommentRating? rating;

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
  CommunityPosts(this._client, {this.signIn});
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

  /// The comments client, whose Google sign-in later pages are loaded with.
  final YoutubeComments? signIn;

  /// The first page of [channel]'s posts.
  Future<PostPage> first(ChannelRef channel) async {
    final response = await _client.get(Uri.parse('${channel.url}/posts?hl=$youtubeHl'), headers: _headers).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
    final (page, apiKey, clientVersion, visitorData) = await _readPageInBackground(response.bodyBytes);
    _apiKey = apiKey;
    _clientVersion = clientVersion;
    _visitorData = visitorData;
    if (page == null) throw FormatException(tr('没有在频道页面里找到帖子数据'));
    return page;
  }

  /// The page after the one that gave [continuation].
  Future<PostPage> next(String continuation) async {
    final signIn = this.signIn;
    if (signIn != null && signIn.signedIn) {
      final answer = await signIn.signIn!.post('browse', {'continuation': continuation});
      if (answer != null && answer.status >= 400 && answer.status < 500) signIn.refuse(answer.status, answer.body);
      if (answer != null && answer.status == 200) {
        final page = await _readInBackground(answer.body);
        if (page != null && page.posts.isNotEmpty) return page;
      }
    }
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
    return await _readInBackground(response.bodyBytes) ?? const PostPage([], null);
  }

  static Future<PostPage?> _readInBackground(List<int> body) => Isolate.run(() => readBytes(body));

  // A channel page runs to a megabyte or two; its client settings are read
  // there too.
  static Future<(PostPage?, String?, String?, String?)> _readPageInBackground(List<int> bytes) => Isolate.run(() {
        final html = utf8.decode(bytes, allowMalformed: true);
        String? find(String name) => RegExp('"$name":"([^"]+)"').firstMatch(html)?.group(1);
        return (read(html), find('INNERTUBE_API_KEY'), find('INNERTUBE_CLIENT_VERSION'), find('VISITOR_DATA'));
      });

  /// Posts and the continuation token of a browse response, or of the
  /// `ytInitialData` in the HTML page [body]; read by the native core. Null
  /// when there is neither, or without the core.
  static PostPage? read(String body) => readBytes(utf8.encode(body));

  static PostPage? readBytes(List<int> body) {
    final core = NativeCore.instance;
    final page = core == null ? null : jsonDecode(core.take(core.withBytes(body, core.youtubePosts)) ?? 'null');
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
        rating: CommentRating.fromJson(p['rating']),
      );
    }

    return PostPage([for (final p in (page['posts'] as List).cast<Map<String, dynamic>>()) post(p)], page['continuation'] as String?);
  }

  @visibleForTesting
  static PostPage parse(Object? data) => read(jsonEncode(data)) ?? const PostPage([], null);
}
