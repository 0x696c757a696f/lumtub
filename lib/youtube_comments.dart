import 'dart:convert';

import 'package:http/http.dart' as http;

import 'community_posts.dart';
import 'l10n/l10n.dart';

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

  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Cookie': 'CONSENT=YES+cb; SOCS=CAI',
  };

  String? _apiKey;
  String? _clientVersion;
  String? _visitorData;

  /// The first page of comments under [videoId], top comments first unless
  /// [newest].
  Future<CommentPage> video(String videoId, {bool newest = false}) async {
    final header = await _request('next', videoSectionToken(videoId));
    return _sorted(header, 'next', newest);
  }

  /// The first page of comments under community post [postId].
  Future<CommentPage> post(String postId, {bool newest = false}) async {
    final response = await _client.get(Uri.parse('https://www.youtube.com/post/$postId?hl=zh-CN'), headers: _headers).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    _apiKey = RegExp(r'"INNERTUBE_API_KEY":"([^"]+)"').firstMatch(html)?.group(1) ?? _apiKey;
    _clientVersion = RegExp(r'"INNERTUBE_CLIENT_VERSION":"([^"]+)"').firstMatch(html)?.group(1) ?? _clientVersion;
    _visitorData = RegExp(r'"VISITOR_DATA":"([^"]+)"').firstMatch(html)?.group(1) ?? _visitorData;
    final token = sectionToken(CommunityPosts.initialData(html));
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
    final key = _apiKey;
    final response = await _client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/$endpoint?${key == null ? '' : 'key=$key&'}prettyPrint=false'),
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
            'continuation': token,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
    return parse(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  /// The token of a video's comment section, built as yt-dlp's
  /// `_generate_comment_continuation` does, so the watch page need not be
  /// downloaded first.
  static String videoSectionToken(String videoId) =>
      base64.encode(utf8.encode('\x12\r\x12\x0b$videoId\x18\x062\'"\x11"\x0b${videoId}0\x00x\x020\x00B\x10comments-section'));

  /// The comment section's continuation token in a page's `ytInitialData`.
  static String? sectionToken(Object? data) {
    String? found;
    void walk(Object? node) {
      if (found != null) return;
      if (node is List) {
        for (final child in node) {
          walk(child);
        }
      } else if (node is Map) {
        final section = node['itemSectionRenderer'];
        if (section is Map && section['sectionIdentifier'] == 'comment-item-section') {
          found = _token(section['contents']);
          return;
        }
        for (final value in node.values) {
          if (value is Map || value is List) walk(value);
        }
      }
    }

    walk(data);
    return found;
  }

  /// The first `continuationCommand` token anywhere under [node].
  static String? _token(Object? node) {
    if (node is List) {
      for (final child in node) {
        final token = _token(child);
        if (token != null) return token;
      }
    } else if (node is Map) {
      final token = _path(node, ['continuationCommand', 'token']);
      if (token is String) return token;
      for (final value in node.values) {
        if (value is Map || value is List) {
          final token = _token(value);
          if (token != null) return token;
        }
      }
    }
    return null;
  }

  /// A `/next` or `/browse` response with comment section items.
  static CommentPage parse(Object? response) {
    final entities = <String, Map>{};
    final mutations = _path(response, ['frameworkUpdates', 'entityBatchUpdate', 'mutations']);
    if (mutations is List) {
      for (final mutation in mutations.whereType<Map>()) {
        final key = mutation['entityKey'];
        final payload = mutation['payload'];
        if (key is String && payload is Map) entities[key] = payload;
      }
    }
    final items = <Object?>[];
    final endpoints = _path(response, ['onResponseReceivedEndpoints']);
    if (endpoints is List) {
      for (final endpoint in endpoints.whereType<Map>()) {
        final command = endpoint['reloadContinuationItemsCommand'] ?? endpoint['appendContinuationItemsAction'];
        final list = _path(command, ['continuationItems']);
        if (list is List) items.addAll(list);
      }
    }
    final comments = <YoutubeComment>[];
    final seen = <String>{};
    String? continuation;
    var count = '';
    String? top;
    String? newest;
    for (final item in items.whereType<Map>()) {
      final header = item['commentsHeaderRenderer'];
      if (header is Map) {
        count = CommunityPosts.text(header['countText']).isNotEmpty ? CommunityPosts.text(header['countText']) : CommunityPosts.text(header['commentsCount']);
        final sorts = _path(header, ['sortMenu', 'sortFilterSubMenuRenderer', 'subMenuItems']);
        if (sorts is List) {
          top = sorts.isNotEmpty ? _token(sorts[0]) : null;
          newest = sorts.length > 1 ? _token(sorts[1]) : null;
        }
        continue;
      }
      final thread = item['commentThreadRenderer'];
      final comment = _comment(thread is Map ? thread : item, entities, thread is Map ? _path(thread, ['replies', 'commentRepliesRenderer']) : null);
      if (comment != null) {
        if (seen.add(comment.id)) comments.add(comment);
        continue;
      }
      if (item['continuationItemRenderer'] != null) continuation = _token(item['continuationItemRenderer']) ?? continuation;
    }
    return CommentPage(comments, continuation, count: count, topToken: top, newestToken: newest);
  }

  static YoutubeComment? _comment(Map node, Map<String, Map> entities, Object? replies) {
    final repliesToken = replies == null ? null : _token(replies);
    final model = _path(node, ['commentViewModel', 'commentViewModel']) ?? node['commentViewModel'];
    if (model is Map) {
      final payload = _path(entities[model['commentKey']], ['commentEntityPayload']);
      final id = _path(payload, ['properties', 'commentId']);
      if (id is! String) return null;
      final toolbar = _path(entities[model['toolbarStateKey']], ['engagementToolbarStateEntityPayload']);
      final author = _path(payload, ['author']);
      return YoutubeComment(
        id: id,
        author: '${_path(author, ['displayName']) ?? ''}',
        text: '${_path(payload, ['properties', 'content', 'content']) ?? ''}',
        avatar: _https(_path(author, ['avatarThumbnailUrl'])),
        channelId: _path(author, ['channelId']) as String?,
        published: '${_path(payload, ['properties', 'publishedTime']) ?? ''}',
        likes: '${_path(payload, ['toolbar', 'likeCountNotliked']) ?? ''}'.trim(),
        replyCount: int.tryParse('${_path(payload, ['toolbar', 'replyCount']) ?? ''}'.replaceAll(RegExp(r'\D'), '')) ?? 0,
        repliesToken: repliesToken,
        pinned: model['pinnedText'] != null,
        hearted: _path(toolbar, ['heartState']) == 'TOOLBAR_HEART_STATE_HEARTED',
        byUploader: _path(author, ['isCreator']) == true,
      );
    }
    final renderer = _path(node, ['comment', 'commentRenderer']) ?? node['commentRenderer'];
    if (renderer is! Map || renderer['commentId'] is! String) return null;
    final thumbnails = _path(renderer, ['authorThumbnail', 'thumbnails']);
    return YoutubeComment(
      id: renderer['commentId'] as String,
      author: CommunityPosts.text(renderer['authorText']),
      text: CommunityPosts.text(renderer['contentText']),
      avatar: thumbnails is List && thumbnails.isNotEmpty ? _https(_path(thumbnails.last, ['url'])) : null,
      channelId: _path(renderer, ['authorEndpoint', 'browseEndpoint', 'browseId']) as String?,
      published: CommunityPosts.text(renderer['publishedTimeText']),
      likes: CommunityPosts.text(renderer['voteCount']),
      replyCount: renderer['replyCount'] is int ? renderer['replyCount'] as int : 0,
      repliesToken: repliesToken,
      pinned: renderer['pinnedCommentBadge'] != null,
      hearted: _path(renderer, ['actionButtons', 'commentActionButtonsRenderer', 'creatorHeart']) != null,
      byUploader: renderer['authorIsChannelOwner'] == true,
    );
  }

  static String? _https(Object? url) {
    final text = '${url ?? ''}';
    final full = text.startsWith('//') ? 'https:$text' : text;
    return full.startsWith('https://') ? full : null;
  }

  static Object? _path(Object? node, List<String> keys) {
    var current = node;
    for (final key in keys) {
      if (current is! Map) return null;
      current = current[key];
    }
    return current;
  }
}
