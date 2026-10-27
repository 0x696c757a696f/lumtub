import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'l10n/l10n.dart';
import 'native_core.dart';
import 'youtube_web.dart';

/// Liking a comment or a post: its state and the actions of its buttons,
/// present only in pages loaded signed in.
class CommentRating {
  const CommentRating({this.state = '', this.like, this.unlike, this.dislike, this.undislike});

  static CommentRating? fromJson(Object? json) => json is! Map<String, dynamic>
      ? null
      : CommentRating(
          state: json['state'] as String? ?? '',
          like: json['like'] as String?,
          unlike: json['unlike'] as String?,
          dislike: json['dislike'] as String?,
          undislike: json['undislike'] as String?,
        );

  /// `like`, `dislike` or empty.
  final String state;
  final String? like;
  final String? unlike;
  final String? dislike;
  final String? undislike;

  /// The action that turns [current] into [want] pressed (`like` or
  /// `dislike`); pressing the one already on takes it back.
  String? actionFor(String current, String want) => switch ((want, current == want)) {
        ('like', true) => unlike,
        ('like', false) => like,
        (_, true) => undislike,
        _ => dislike,
      };
}

/// One comment or reply.
class YoutubeComment {
  const YoutubeComment({
    required this.id,
    required this.author,
    required this.text,
    this.avatar,
    this.channelId,
    this.published = '',
    this.likes = '',
    this.replyCount = 0,
    this.repliesToken,
    this.pinned = false,
    this.hearted = false,
    this.byUploader = false,
    this.emojis = const {},
    this.rating,
  });

  final String id;
  final String author;
  final String text;
  final String? avatar;
  final String? channelId;
  /// YouTube's own relative time, such as "3天前".
  final String published;
  final String likes;
  final int replyCount;
  /// Loads the replies through [YoutubeComments.more].
  final String? repliesToken;
  final bool pinned;
  /// The uploader liked it.
  final bool hearted;
  final bool byUploader;
  /// Custom emoji in [text]: shortcut to picture address.
  final Map<String, String> emojis;
  final CommentRating? rating;
}

/// One page of comments, the token for the next, and from the first page
/// the comment count and the tokens for each sort order.
class CommentPage {
  const CommentPage(this.comments, this.continuation, {this.count = '', this.topToken, this.newestToken});
  final List<YoutubeComment> comments;
  final String? continuation;
  final String count;
  final String? topToken;
  final String? newestToken;
}

/// Reads the comments under a video or a community post the way the YouTube
/// website loads them: a continuation token for the comment section, then
/// pages of comments from InnerTube. Both of YouTube's comment formats are
/// read: the older `commentRenderer`, and `commentViewModel` whose content
/// comes in `frameworkUpdates` entity payloads (the paths follow yt-dlp's
/// extractor/youtube/_video.py).
class YoutubeComments {
  YoutubeComments(this._client);
  final http.Client _client;

  static Map<String, String> get _headers => {
    'User-Agent': YoutubeWeb.userAgent,
    'Accept-Language': youtubeAcceptLanguage,
    'Cookie': 'CONSENT=YES+cb; SOCS=CAI',
  };

  String? _apiKey;
  String? _clientVersion;
  String? _visitorData;

  /// The Google sign-in's access token, so pages come with the like and
  /// dislike buttons of the signed-in user; null when signed out.
  Future<String?> Function()? token;

  /// YouTube did not take the sign-in's token; comments load signed out
  /// for the rest of the run.
  bool refused = false;

  Future<Map<String, String>> signedInHeaders() async {
    if (refused) return const {};
    try {
      final value = await token?.call();
      return value == null ? const {} : {'Authorization': 'Bearer $value'};
    } catch (_) {
      return const {};
    }
  }

  /// The first page of comments under [videoId], top comments first unless
  /// [newest].
  Future<CommentPage> video(String videoId, {bool newest = false}) async {
    final header = await _request('next', videoSectionToken(videoId));
    return _sorted(header, 'next', newest);
  }

  /// The first page of comments under community post [postId].
  Future<CommentPage> post(String postId, {bool newest = false}) async {
    final response = await _client.get(Uri.parse('https://www.youtube.com/post/$postId?hl=$youtubeHl'), headers: _headers).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
    final (token, apiKey, clientVersion, visitorData) = await _readPostInBackground(response.bodyBytes);
    _apiKey = apiKey ?? _apiKey;
    _clientVersion = clientVersion ?? _clientVersion;
    _visitorData = visitorData ?? _visitorData;
    if (token == null) throw FormatException(tr('这个帖子没有评论区，或评论已关闭'));
    final header = await _request('browse', token);
    return _sorted(header, 'browse', newest);
  }

  /// The next page after [token], or the replies a comment's
  /// [YoutubeComment.repliesToken] names. [post] says whether the token came
  /// from a community post.
  Future<CommentPage> more(String token, {bool post = false}) => _request(post ? 'browse' : 'next', token);

  /// The first page is only the header; the sort order's token loads the
  /// comments themselves.
  Future<CommentPage> _sorted(CommentPage header, String endpoint, bool newest) async {
    final token = newest ? header.newestToken ?? header.topToken : header.topToken;
    if (token == null) return header;
    final page = await _request(endpoint, token);
    return CommentPage(page.comments, page.continuation, count: header.count, topToken: header.topToken, newestToken: header.newestToken);
  }

  Future<CommentPage> _request(String endpoint, String token) async {
    final signedIn = await signedInHeaders();
    final response = await _post(endpoint, {'continuation': token}, signedIn);
    if (signedIn.isNotEmpty && (response.statusCode == 401 || response.statusCode == 403)) {
      _refuse(response.statusCode);
      return _request(endpoint, token);
    }
    if (response.statusCode != 200) throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
    return _readInBackground(response.bodyBytes);
  }

  void _refuse(int status) {
    refused = true;
    logInfo('YouTube answered $status to the Google sign-in on InnerTube; comments load signed out');
  }

  /// Likes, dislikes or takes back either, by the [action] of a
  /// [CommentRating], for a comment or a post alike.
  Future<void> rate(String action) async {
    final signedIn = await signedInHeaders();
    if (signedIn.isEmpty) throw StateError(tr('需要先登录 Google 账号'));
    final response = await _post('comment/perform_comment_action', {'actions': [action]}, signedIn);
    if (response.statusCode == 401 || response.statusCode == 403) {
      _refuse(response.statusCode);
      throw StateError(tr('YouTube 不接受当前 Google 授权的这项操作'));
    }
    if (response.statusCode != 200) throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
  }

  Future<http.Response> _post(String endpoint, Map<String, Object?> body, Map<String, String> signedIn) {
    final key = _apiKey;
    return _client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/$endpoint?${key == null || signedIn.isNotEmpty ? '' : 'key=$key&'}prettyPrint=false'),
          headers: {...YoutubeWeb.apiHeaders(clientVersion: _clientVersion, acceptLanguage: youtubeAcceptLanguage), ...signedIn},
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB',
                'clientVersion': _clientVersion ?? YoutubeWeb.clientVersion,
                'hl': youtubeHl,
                if (_visitorData != null) 'visitorData': _visitorData,
              },
            },
            ...body,
          }),
        )
        .timeout(const Duration(seconds: 20));
  }

  static Future<CommentPage> _readInBackground(List<int> bytes) => Isolate.run(() => readBytes(bytes));

  // A post page runs to a megabyte: its comments token and client settings
  // are read away from the UI isolate.
  static Future<(String?, String?, String?, String?)> _readPostInBackground(List<int> bytes) => Isolate.run(() {
        final html = utf8.decode(bytes, allowMalformed: true);
        String? find(String name) => RegExp('"$name":"([^"]+)"').firstMatch(html)?.group(1);
        final core = NativeCore.instance;
        final token = core == null ? null : jsonDecode(core.take(core.withText(html, core.youtubePostComments)) ?? 'null') as String?;
        return (token, find('INNERTUBE_API_KEY'), find('INNERTUBE_CLIENT_VERSION'), find('VISITOR_DATA'));
      });

  /// The token of a video's comment section, built as yt-dlp's
  /// `_generate_comment_continuation` does, so the watch page need not be
  /// downloaded first.
  static String videoSectionToken(String videoId) =>
      base64.encode(utf8.encode('\x12\r\x12\x0b$videoId\x18\x062\'"\x11"\x0b${videoId}0\x00x\x020\x00B\x10comments-section'));

  /// A `/next` or `/browse` response [body] with comment section items,
  /// read by the native core; empty without it.
  static CommentPage read(String body) => readBytes(utf8.encode(body));

  static CommentPage readBytes(List<int> body) {
    final core = NativeCore.instance;
    final page = core == null ? null : jsonDecode(core.take(core.withBytes(body, core.youtubeComments)) ?? 'null');
    if (page is! Map<String, dynamic>) return const CommentPage([], null);
    return CommentPage(
      [
        for (final c in (page['comments'] as List).cast<Map<String, dynamic>>())
          YoutubeComment(
            id: c['id'] as String,
            author: c['author'] as String,
            text: c['text'] as String,
            avatar: c['avatar'] as String?,
            channelId: c['channelId'] as String?,
            published: c['published'] as String,
            likes: c['likes'] as String,
            replyCount: (c['replyCount'] as num).toInt(),
            repliesToken: c['repliesToken'] as String?,
            pinned: c['pinned'] as bool,
            hearted: c['hearted'] as bool,
            byUploader: c['byUploader'] as bool,
            emojis: (c['emojis'] as Map<String, dynamic>?)?.cast<String, String>() ?? const {},
            rating: CommentRating.fromJson(c['rating']),
          ),
      ],
      page['continuation'] as String?,
      count: page['count'] as String,
      topToken: page['topToken'] as String?,
      newestToken: page['newestToken'] as String?,
    );
  }

  @visibleForTesting
  static CommentPage parse(Object? response) => read(jsonEncode(response));
}
