import 'dart:convert';
import 'dart:isolate';

import 'l10n/l10n.dart';
import 'models.dart';
import 'native_core.dart';
import 'youtube_account.dart';
import 'youtube_account_feed.dart';
import 'youtube_web_sign_in.dart';

/// What [YouTubeAccountApi] does with the Google sign-in, done with the
/// browser sign-in as the website does it: no Google Cloud client, no
/// daily quota. Writes are made for something the user did, so the
/// system's prompt to open the cookies may come up.
class WebAccountApi implements AccountApi {
  WebAccountApi(this.signIn) : feed = YoutubeAccountFeed(signIn);

  final WebInnerTube signIn;
  final YoutubeAccountFeed feed;

  /// What the website sends to subscribe and to unsubscribe.
  static const subscribeParams = 'EgIIAhgA';
  static const unsubscribeParams = 'CgIIAhgA';

  @override
  Future<({String name, String? avatar, String? likes})> me() async {
    final answer = await signIn.post('account/accounts_list', const {});
    final data = answer == null || answer.status != 200 ? null : jsonDecode(utf8.decode(answer.body, allowMalformed: true));
    final account = data == null ? null : _find(data, 'accountItem') ?? _find(data, 'activeAccountHeaderRenderer');
    final name = account is Map ? _text(account['accountName']) : null;
    final photo = account is Map ? account['accountPhoto'] : null;
    final pictures = photo is Map ? photo['thumbnails'] : null;
    final picture = pictures is List && pictures.isNotEmpty && pictures.last is Map ? '${(pictures.last as Map)['url'] ?? ''}' : '';
    return (
      name: name ?? tr('YouTube account'),
      avatar: picture.startsWith('https://') ? picture : null,
      likes: YoutubeAccountFeed.likedId,
    );
  }

  @override
  Future<List<ChannelRef>> subscriptions() => feed.subscriptions();

  @override
  Future<List<RemotePlaylist>> playlists() async => [
        for (final list in await feed.accountPlaylists()) RemotePlaylist(list.id, list.title, list.count ?? 0),
      ];

  @override
  Future<List<VideoItem>> playlistItems(String playlistId) =>
      feed.videos('VL$playlistId', limit: YouTubeAccountApi.maxPlaylistItems, pages: 10);

  @override
  Future<VideoRating> rating(String videoId) async {
    final answer = await signIn.post('next', {'videoId': videoId});
    if (answer == null || answer.status != 200) return VideoRating.none;
    final facts = await viewerOf(answer.body);
    return VideoRating.values.where((r) => r.name == facts?['rating']).firstOrNull ?? VideoRating.none;
  }

  @override
  Future<void> rate(String videoId, VideoRating rating) => _send(
        switch (rating) {
          VideoRating.like => 'like/like',
          VideoRating.dislike => 'like/dislike',
          VideoRating.none => 'like/removelike',
        },
        {'target': {'videoId': videoId}},
        'a rating');

  @override
  Future<void> addToPlaylist(String playlistId, String videoId) => _send(
        'browse/edit_playlist',
        {
          'playlistId': playlistId,
          'actions': [
            {'action': 'ACTION_ADD_VIDEO', 'addedVideoId': videoId},
          ],
        },
        'a playlist change');

  @override
  Future<RemotePlaylist> createPlaylist(String title) async {
    final data = await _send('playlist/create', {'title': title, 'privacyStatus': 'PRIVATE'}, 'a new playlist');
    final id = data is Map ? data['playlistId'] : null;
    if (id is! String || id.isEmpty) throw StateError(tr('YouTube did not make the playlist'));
    return RemotePlaylist(id, title, 0);
  }

  @override
  Future<void> subscribe(String channelId) =>
      _send('subscription/subscribe', {'channelIds': [channelId], 'params': subscribeParams}, 'a subscription');

  @override
  Future<void> unsubscribe(String channelId) =>
      _send('subscription/unsubscribe', {'channelIds': [channelId], 'params': unsubscribeParams}, 'an unsubscription');

  /// Writes [text] in the comment box [params] names: a video's, from its
  /// comments page, or a comment's reply box.
  Future<void> comment(String params, String text, {bool reply = false}) => reply
      ? _send('comment/create_comment_reply', {'replyText': text, 'createReplyParams': params}, 'a reply')
      : _send('comment/create_comment', {'commentText': text, 'createCommentParams': params}, 'a comment');

  Future<Object?> _send(String endpoint, Map<String, Object?> body, String what) async {
    final answer = await signIn.post(endpoint, body, ask: true);
    if (answer == null) throw StateError(tr('Sign in with a browser (cookies) in Settings › YouTube account first'));
    final text = utf8.decode(answer.body, allowMalformed: true);
    if (answer.status != 200) {
      throw StateError(answer.status >= 400 && answer.status < 500
          ? tr('YouTube does not accept this action from the current sign-in')
          : tr('YouTube returned {0}', [answer.status]));
    }
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// The viewer's own state in a `/next` answer read by the core: its
  /// `rating` ("like", "dislike", "none") and `subscribed`.
  static Future<Map<String, Object?>?> viewerOf(List<int> body) => Isolate.run(() {
        final core = NativeCore.instance;
        if (core == null) return null;
        final answer = jsonDecode(core.take(core.withBytes(body, core.youtubeNext)) ?? 'null');
        final facts = answer is Map ? answer['facts'] : null;
        return facts is Map<String, Object?> ? facts : null;
      });

  static Object? _find(Object? node, String key) {
    if (node is Map) {
      if (node[key] case final Object found) return found;
      for (final value in node.values) {
        if (_find(value, key) case final Object found) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        if (_find(value, key) case final Object found) return found;
      }
    }
    return null;
  }

  static String? _text(Object? node) {
    if (node is! Map) return null;
    if (node['simpleText'] case final String text when text.isNotEmpty) return text;
    final runs = node['runs'];
    if (runs is! List) return null;
    final text = runs.map((r) => r is Map ? '${r['text'] ?? ''}' : '').join();
    return text.isEmpty ? null : text;
  }
}
