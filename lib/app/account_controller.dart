import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_log.dart';
import '../google_auth.dart';
import '../models.dart';
import '../secure_store.dart';
import '../youtube_account.dart';
import 'library_controller.dart';
import '../l10n/l10n.dart';

enum AccountState { signedOut, signingIn, signedIn }

/// The optional Google sign-in: copies the account's YouTube subscriptions
/// and playlists into the local library, and makes the likes, comments,
/// playlist saves and subscriptions the user asks for. Playback never uses
/// it, and without it everything else works the same.
class AccountController extends ChangeNotifier {
  AccountController({
    required this.clientFile,
    required this.credentials,
    required http.Client client,
    required this.library,
    required this.notice,
    Future<void> Function(Uri)? openBrowser,
  })  : _client = client,
        _openBrowser = openBrowser;

  /// The user's own OAuth client, when they entered one in settings.
  final File clientFile;
  /// The refresh token and account name, encrypted for this Windows user.
  final SecureJsonFile credentials;
  final LibraryController library;
  final void Function(String message) notice;
  final http.Client _client;
  final Future<void> Function(Uri)? _openBrowser;

  AccountState state = AccountState.signedOut;
  OAuthClientConfig? customClient;
  String? name;
  DateTime? lastSync;
  bool syncing = false;
  String? error;
  /// The scopes of the sign-in; older sign-ins were read-only.
  String? scope;
  /// The account's "liked videos" playlist.
  String? likesPlaylist;

  String? _refreshToken;
  OAuthTokens? _tokens;
  GoogleAuth? _auth;

  /// The client in use: the user's own, else the one built into this copy.
  OAuthClientConfig? get client => customClient ?? (OAuthClientConfig.builtIn.isValid ? OAuthClientConfig.builtIn : null);

  bool get signedIn => state == AccountState.signedIn;

  /// Signed in with the permission to like, comment, save and subscribe.
  bool get canWrite => signedIn && canWriteWith(scope);

  Future<void> load() async {
    try {
      if (await clientFile.exists()) customClient = OAuthClientConfig.fromJson(jsonDecode(await clientFile.readAsString()));
    } catch (_) {
      customClient = null;
    }
    final saved = await credentials.read();
    final token = saved?['refresh_token'];
    if (token is String && token.isNotEmpty) {
      _refreshToken = token;
      name = saved?['name']?.toString();
      lastSync = DateTime.tryParse(saved?['last_sync']?.toString() ?? '');
      scope = saved?['scope']?.toString();
      likesPlaylist = saved?['likes']?.toString();
      state = AccountState.signedIn;
    }
    notifyListeners();
  }

  /// Uses the user's own Google Cloud client; a different client cannot use
  /// the current sign-in, so it signs out first.
  Future<void> setCustomClient(OAuthClientConfig? config) async {
    if (signedIn) await signOut();
    customClient = config;
    if (config == null) {
      if (await clientFile.exists()) await clientFile.delete();
    } else {
      await clientFile.writeAsString(jsonEncode(config.toJson()));
    }
    notifyListeners();
  }

  Future<void> signIn() async {
    final config = client;
    if (config == null || state == AccountState.signingIn) return;
    final auth = _auth = GoogleAuth(config, _client, openBrowser: _openBrowser);
    state = AccountState.signingIn;
    error = null;
    notifyListeners();
    try {
      final tokens = await auth.signIn();
      if (tokens.refreshToken == null) throw OAuthException(tr('Google 没有返回长期凭据，请重试'));
      _tokens = tokens;
      _refreshToken = tokens.refreshToken;
      scope = tokens.scope ?? youtubeScope;
      final me = await _api.me();
      name = me.name;
      likesPlaylist = me.likes;
      state = AccountState.signedIn;
      await _save();
      notifyListeners();
      notice(tr('已登录 {0}', [me.name]));
      unawaited(sync(likes: me.likes));
    } catch (e) {
      logError('Google 登录失败', e);
      _tokens = null;
      _refreshToken = null;
      state = AccountState.signedOut;
      error = '$e';
      notifyListeners();
    } finally {
      if (_auth == auth) _auth = null;
    }
  }

  Future<void> cancelSignIn() async => _auth?.cancel();

  /// Revokes the grant at Google when reachable and deletes the local
  /// credentials. Imported channels and playlists stay in the library.
  Future<void> signOut() async {
    final token = _refreshToken;
    _refreshToken = null;
    _tokens = null;
    name = null;
    lastSync = null;
    scope = null;
    likesPlaylist = null;
    error = null;
    state = AccountState.signedOut;
    notifyListeners();
    await credentials.delete();
    final config = client;
    if (token != null && config != null) await GoogleAuth(config, _client).revoke(token);
  }

  /// Follows every subscribed channel and mirrors the account's playlists,
  /// including liked videos, into the local library.
  Future<void> sync({String? likes}) async {
    if (!signedIn || syncing) return;
    syncing = true;
    error = null;
    notifyListeners();
    try {
      final api = _api;
      final channels = await api.subscriptions();
      final added = library.followAll(channels);
      final likesId = likes ?? (await api.me()).likes;
      likesPlaylist = likesId;
      final remote = await api.playlists();
      final mirrored = <String, ({String name, List<VideoItem> items})>{};
      if (likesId != null) mirrored[likesId] = (name: tr('喜欢的视频'), items: await api.playlistItems(likesId));
      for (final playlist in remote) {
        mirrored[playlist.id] = (name: playlist.title, items: playlist.count == 0 ? const [] : await api.playlistItems(playlist.id));
      }
      library.mirrorRemotePlaylists(mirrored);
      lastSync = DateTime.now();
      await _save();
      logInfo('YouTube 同步完成：${channels.length} 个订阅，${mirrored.length} 个播放列表');
      notice(tr('同步完成：{0} 个订阅（新增 {1} 个），{2} 个播放列表', [channels.length, added, mirrored.length]));
    } catch (e) {
      logError('YouTube 同步失败', e);
      error = '$e';
      if (e is OAuthException && e.revoked) await signOut();
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// The liked videos copied from YouTube, for recommendations.
  List<VideoItem> get likedVideos {
    final id = likesPlaylist;
    if (id == null) return const [];
    return library.playlists.where((p) => p.id == '${LibraryController.remotePrefix}$id').firstOrNull?.items ?? const [];
  }

  final _ratings = <String, VideoRating>{};

  /// How the account rated [videoId], once [loadRating] has asked.
  VideoRating? ratingOf(String videoId) => _ratings[videoId];

  Future<void> loadRating(String videoId) async {
    if (!canWrite || _ratings.containsKey(videoId)) return;
    try {
      _ratings[videoId] = await _api.rating(videoId);
      notifyListeners();
    } catch (e) {
      logInfo('读取点赞状态失败：$e');
    }
  }

  /// Likes or dislikes [item], or takes the rating back when it is already
  /// [rating].
  Future<void> rate(VideoItem item, VideoRating rating) async {
    if (!_writable()) return;
    final previous = _ratings[item.id] ?? VideoRating.none;
    final next = previous == rating ? VideoRating.none : rating;
    _ratings[item.id] = next;
    notifyListeners();
    try {
      await _api.rate(item.id, next);
      _mirrorLike(item, next == VideoRating.like);
      notice(switch (next) {
        VideoRating.like => tr('已点赞'),
        VideoRating.dislike => tr('已点踩，YouTube 会减少类似推荐'),
        VideoRating.none => tr('已取消'),
      });
    } catch (e) {
      _ratings[item.id] = previous;
      _failed(tr('操作失败'), e);
    }
  }

  /// Keeps the local copy of 喜欢的视频 in step with a like.
  void _mirrorLike(VideoItem item, bool liked) {
    final id = likesPlaylist;
    if (id == null) return;
    final playlist = library.playlists.where((p) => p.id == '${LibraryController.remotePrefix}$id').firstOrNull;
    if (playlist == null) return;
    final others = playlist.items.where((v) => v.id != item.id).toList();
    library.mirrorRemotePlaylist(id, playlist.name, liked ? [item, ...others] : others);
  }

  /// Posts [text] under [videoId], or as a reply to [parentId]. Returns
  /// whether it was posted.
  Future<bool> postComment({required String videoId, String? parentId, required String text}) async {
    if (!_writable() || text.trim().isEmpty) return false;
    try {
      if (parentId == null) {
        await _api.comment(videoId, text.trim());
      } else {
        await _api.reply(parentId, text.trim());
      }
      notice(parentId == null ? tr('评论已发布') : tr('回复已发布'));
      return true;
    } catch (e) {
      _failed(tr('发布失败'), e);
      return false;
    }
  }

  /// The account's own playlists, for 保存到 YouTube 播放列表.
  Future<List<RemotePlaylist>> remotePlaylists() async {
    if (!_writable()) return const [];
    try {
      return await _api.playlists();
    } catch (e) {
      _failed(tr('无法读取 YouTube 播放列表'), e);
      return const [];
    }
  }

  /// Adds [item] to the account's [playlist], creating the playlist first
  /// when only [newTitle] is given.
  Future<void> saveToPlaylist(VideoItem item, {RemotePlaylist? playlist, String? newTitle}) async {
    if (!_writable()) return;
    try {
      final target = playlist ?? await _api.createPlaylist(newTitle!.trim());
      await _api.addToPlaylist(target.id, item.id);
      final local = library.playlists.where((p) => p.id == '${LibraryController.remotePrefix}${target.id}').firstOrNull;
      library.mirrorRemotePlaylist(target.id, target.title, [...?local?.items.where((v) => v.id != item.id), item]);
      notice(tr('已保存到 YouTube 播放列表“{0}”', [target.title]));
    } catch (e) {
      _failed(tr('保存失败'), e);
    }
  }

  /// Subscribes to or unsubscribes from [channel] on YouTube.
  Future<void> setSubscribed(ChannelRef channel, bool subscribed) async {
    if (!canWrite) return;
    try {
      if (subscribed) {
        await _api.subscribe(channel.id);
      } else {
        await _api.unsubscribe(channel.id);
      }
    } catch (e) {
      _failed(subscribed ? tr('YouTube 订阅失败') : tr('取消 YouTube 订阅失败'), e);
    }
  }

  bool _writable() {
    if (canWrite) return true;
    notice(signedIn ? tr('需要重新登录 Google 账号，授予点赞、评论等权限') : tr('请先在设置里登录 Google 账号'));
    return false;
  }

  void _failed(String what, Object e) {
    logError(what, e);
    notice('$what：$e');
    notifyListeners();
    if (e is OAuthException && e.revoked) unawaited(signOut());
  }

  YouTubeAccountApi get _api => YouTubeAccountApi(_client, _accessToken);

  Future<String> _accessToken() async {
    final tokens = _tokens;
    if (tokens != null && !tokens.expired) return tokens.accessToken;
    final refreshToken = _refreshToken;
    final config = client;
    if (refreshToken == null || config == null) throw OAuthException(tr('请先登录 Google 账号'));
    final fresh = await GoogleAuth(config, _client).refresh(refreshToken);
    _tokens = fresh;
    return fresh.accessToken;
  }

  Future<void> _save() async {
    final token = _refreshToken;
    if (token == null) return;
    try {
      await credentials.write({
        'refresh_token': token,
        'name': name,
        if (lastSync != null) 'last_sync': lastSync!.toIso8601String(),
        if (scope != null) 'scope': scope,
        if (likesPlaylist != null) 'likes': likesPlaylist,
      });
    } on FileSystemException catch (e) {
      error = tr('无法保存登录凭据：{0}', [e.message]);
    }
  }

  @override
  void dispose() {
    unawaited(_auth?.cancel());
    super.dispose();
  }
}
