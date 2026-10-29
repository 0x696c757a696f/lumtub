import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'l10n/l10n.dart';
import 'native_core.dart';
import 'youtube_tv_sign_in.dart';
import 'youtube_web.dart';
import 'youtube_web_sign_in.dart';

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

  /// The same buttons for comment [to], made from these of comment [from]
  /// on the same video by the native core; null when they cannot be.
  CommentRating? forComment(String from, String to) {
    String? swap(String? action) {
      if (action == null) return null;
      final core = NativeCore.instance;
      final made = _actionFor;
      if (core == null || made == null) return null;
      return jsonDecode(core.take(core.withText(jsonEncode({'action': action, 'from': from, 'to': to}), made)) ?? 'null') as String?;
    }

    final rating = CommentRating(like: swap(like), unlike: swap(unlike), dislike: swap(dislike), undislike: swap(undislike));
    return rating.like == null && rating.dislike == null ? null : rating;
  }

  static Pointer<Utf8> Function(Pointer<Uint8>, int)? _actionForBinding;
  static bool _triedActionFor = false;
  static Pointer<Utf8> Function(Pointer<Uint8>, int)? get _actionFor {
    if (_triedActionFor) return _actionForBinding;
    _triedActionFor = true;
    try {
      return _actionForBinding = NativeCore.instance?.library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_comment_action_for');
    } catch (_) {
      return null;
    }
  }

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
    this.detailToken,
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
  /// The TV app's page for this one comment, which has its like buttons
  /// when the list it came in does not; read through [YoutubeComments.more].
  final String? detailToken;
}

/// One page of comments, the token for the next, and from the first page
/// the comment count and the tokens for each sort order.
class CommentPage {
  const CommentPage(this.comments, this.continuation, {this.count = '', this.topToken, this.newestToken, this.createParams});
  final List<YoutubeComment> comments;
  final String? continuation;
  final String count;
  final String? topToken;
  final String? newestToken;
  /// The website's comment box, in pages loaded with the cookie sign-in.
  final String? createParams;
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

  /// The TV-code sign-in, so pages come with the like and dislike buttons
  /// of the signed-in user.
  SignedInnerTube? signIn;

  /// YouTube did not take the sign-in; comments load signed out for the
  /// rest of the run.
  bool refused = false;

  bool get signedIn => !refused && (signIn?.signedIn ?? false);

  /// The cookie sign-in, which posts and their comments are loaded with,
  /// so they come with the buttons, the poll and the comment box.
  WebInnerTube? web;

  /// YouTube did not take the cookies; posts load without them for the
  /// rest of the run.
  bool webRefused = false;

  bool get webSignedIn => !webRefused && (web?.signedIn ?? false);

  /// The sign-in requests for a video ([post] false) or a post go with.
  SignedInnerTube? _via(bool post) => post && webSignedIn ? web : signedIn ? signIn : null;

  /// The first page of comments under [videoId], top comments first unless
  /// [newest].
  Future<CommentPage> video(String videoId, {bool newest = false}) async {
    // Signed in, the TV app's own watch page names its comment section, as
    // SmartTube reads it; the website's section token is built here.
    final header = !signedIn
        ? await _request('next', {'continuation': videoSectionToken(videoId)})
        : await _request('next', {'videoId': videoId}, fallback: {'continuation': videoSectionToken(videoId)});
    return _sorted(header, 'next', newest);
  }

  /// The first page of comments under community post [postId].
  Future<CommentPage> post(String postId, {bool newest = false}) async {
    final response = await _client.get(Uri.parse('https://www.youtube.com/post/$postId?hl=$youtubeHl'), headers: _headers).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
    final (token, apiKey, clientVersion, visitorData, detail) = await _readPostInBackground(response.bodyBytes);
    _apiKey = apiKey ?? _apiKey;
    _clientVersion = clientVersion ?? _clientVersion;
    _visitorData = visitorData ?? _visitorData;
    // With the cookie sign-in the post's own page, as the website loads
    // it, comes with the like buttons and the comment box.
    if (webSignedIn && detail != null) {
      try {
        final answer = await web!.post('browse', {'browseId': 'FEpost_detail', 'params': detail});
        if (answer != null) {
          if (answer.status >= 400 && answer.status < 500) refuseWeb(answer.status, answer.body);
          final page = answer.status == 200 ? await _readInBackground(answer.body) : const CommentPage([], null);
          logDebug(() => 'Post $postId signed in: ${answer.status}, sort ${page.topToken != null}, comment box ${page.createParams != null}');
          if (page.topToken != null || page.comments.isNotEmpty) return await _sorted(page, 'browse', newest, post: true);
        }
      } catch (e) {
        logWarn('Post $postId signed in failed: $e');
      }
    }
    if (token == null) throw FormatException(tr('这个帖子没有评论区，或评论已关闭'));
    final header = await _request('browse', {'continuation': token}, post: true);
    return _sorted(header, 'browse', newest, post: true);
  }

  /// The next page after [token], or the replies a comment's
  /// [YoutubeComment.repliesToken] names. [post] says whether the token came
  /// from a community post.
  Future<CommentPage> more(String token, {bool post = false}) => _request(post ? 'browse' : 'next', {'continuation': token}, post: post);

  /// The first page is only the header; the sort order's token loads the
  /// comments themselves.
  Future<CommentPage> _sorted(CommentPage header, String endpoint, bool newest, {bool post = false}) async {
    final token = newest ? header.newestToken ?? header.topToken : header.topToken;
    if (token == null) return header;
    final page = await _request(endpoint, {'continuation': token}, post: post);
    return CommentPage(page.comments, page.continuation,
        count: header.count, topToken: header.topToken, newestToken: header.newestToken, createParams: header.createParams ?? page.createParams);
  }

  /// Posts [body] to [endpoint], signed in when there is a sign-in YouTube
  /// takes; when it does not, posts [fallback] (or [body]) signed out.
  Future<CommentPage> _request(String endpoint, Map<String, Object?> body, {Map<String, Object?>? fallback, bool signedOut = false, bool post = false}) async {
    final SignedInnerTube? via = signedOut ? null : _via(post);
    if (via != null) {
      final answer = await via.post(endpoint, body);
      if (answer != null) {
        if (answer.status >= 400 && answer.status < 500) {
          identical(via, web) ? refuseWeb(answer.status, answer.body) : refuse(answer.status, answer.body);
          return _request(endpoint, fallback ?? body, signedOut: true, post: post);
        }
        if (answer.status != 200) throw StateError(tr('YouTube 返回 {0}', [answer.status]));
        final page = await _readInBackground(answer.body);
        if (page.comments.isNotEmpty || page.continuation != null || page.topToken != null || page.count.isNotEmpty) return page;
        logWarn('The TV app was answered no comments; trying signed out · ${_start(answer.body)}');
      }
    }
    final response = await _post(endpoint, via == null ? fallback ?? body : body);
    if (response.statusCode != 200) throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
    return _readInBackground(response.bodyBytes);
  }

  static String _start(List<int> body) {
    final start = utf8.decode(body.take(600).toList(), allowMalformed: true).replaceAll(RegExp(r'\s+'), ' ');
    return start.length > 300 ? start.substring(0, 300) : start;
  }

  /// Stops sending the sign-in after YouTube answered [status] to it.
  void refuse(int status, [List<int> body = const []]) {
    refused = true;
    logWarn('YouTube answered $status to the TV-code sign-in on InnerTube; comments load signed out · ${_start(body)}');
  }

  /// Stops sending the cookies after YouTube answered [status] to them.
  void refuseWeb(int status, [List<int> body = const []]) {
    webRefused = true;
    logWarn('YouTube answered $status to the cookie sign-in; posts load signed out · ${_start(body)}');
  }

  /// Likes, dislikes or takes back either, by the [action] of a
  /// [CommentRating], for a comment or a post alike; votes in a poll the
  /// same way. [post] is for posts and their comments, which take the
  /// cookie sign-in.
  Future<void> rate(String action, {bool post = false}) async {
    final via = _via(post);
    final answer = via == null
        ? null
        : identical(via, web)
            ? await web!.post('comment/perform_comment_action', {'actions': [action]}, ask: true)
            : await via.post('comment/perform_comment_action', {'actions': [action]});
    if (answer == null) {
      throw StateError(post ? tr('需要先在设置 › YouTube 账号里用浏览器登录（Cookie）') : tr('需要先在设置 › YouTube 账号里用电视码登录'));
    }
    _check(answer, 'a comment action');
  }

  /// Writes [text] under the post whose comment box is [params], as the
  /// cookie sign-in.
  Future<void> create(String params, String text) async {
    final answer = webSignedIn ? await web!.post('comment/create_comment', {'commentText': text, 'createCommentParams': params}, ask: true) : null;
    if (answer == null) throw StateError(tr('需要先在设置 › YouTube 账号里用浏览器登录（Cookie）'));
    _check(answer, 'a new comment');
  }

  static void _check(SignedAnswer answer, String what) {
    if (answer.status >= 400 && answer.status < 500) {
      logWarn('YouTube answered ${answer.status} to $what · ${_start(answer.body)}');
      throw StateError(tr('YouTube 不接受当前登录的这项操作'));
    }
    if (answer.status != 200) throw StateError(tr('YouTube 返回 {0}', [answer.status]));
  }

  Future<http.Response> _post(String endpoint, Map<String, Object?> body) {
    final key = _apiKey;
    return _client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/$endpoint?${key == null ? '' : 'key=$key&'}prettyPrint=false'),
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
            ...body,
          }),
        )
        .timeout(const Duration(seconds: 20));
  }

  static Future<CommentPage> _readInBackground(List<int> bytes) => Isolate.run(() => readBytes(bytes));

  // A post page runs to a megabyte: its comments token and client settings
  // are read away from the UI isolate.
  static Future<(String?, String?, String?, String?, String?)> _readPostInBackground(List<int> bytes) => Isolate.run(() {
        final html = utf8.decode(bytes, allowMalformed: true);
        String? find(String name) => RegExp('"$name":"([^"]+)"').firstMatch(html)?.group(1);
        final core = NativeCore.instance;
        final token = core == null ? null : jsonDecode(core.take(core.withText(html, core.youtubePostComments)) ?? 'null') as String?;
        final detail = RegExp(r'"browseId":"FEpost_detail","params":"([^"]+)"').firstMatch(html)?.group(1);
        return (token, find('INNERTUBE_API_KEY'), find('INNERTUBE_CLIENT_VERSION'), find('VISITOR_DATA'), detail);
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
            detailToken: c['detailToken'] as String?,
          ),
      ],
      page['continuation'] as String?,
      count: page['count'] as String,
      topToken: page['topToken'] as String?,
      newestToken: page['newestToken'] as String?,
      createParams: page['createParams'] as String?,
    );
  }

  @visibleForTesting
  static CommentPage parse(Object? response) => read(jsonEncode(response));
}
