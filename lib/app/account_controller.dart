import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../google_auth.dart';
import '../models.dart';
import '../secure_store.dart';
import '../youtube_account.dart';
import 'library_controller.dart';

enum AccountState { signedOut, signingIn, signedIn }

/// The optional Google sign-in, used only to copy the account's YouTube
/// subscriptions and playlists into the local library. Playback never uses
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

  String? _refreshToken;
  OAuthTokens? _tokens;
  GoogleAuth? _auth;

  /// The client in use: the user's own, else the one built into this copy.
  OAuthClientConfig? get client => customClient ?? (OAuthClientConfig.builtIn.isValid ? OAuthClientConfig.builtIn : null);

  bool get signedIn => state == AccountState.signedIn;

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
      if (tokens.refreshToken == null) throw const OAuthException('Google 没有返回长期凭据，请重试');
      _tokens = tokens;
      _refreshToken = tokens.refreshToken;
      final me = await _api.me();
      name = me.name;
      state = AccountState.signedIn;
      await _save();
      notifyListeners();
      notice('已登录 ${me.name}');
      unawaited(sync(likes: me.likes));
    } catch (e) {
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
      final remote = await api.playlists();
      final mirrored = <String, ({String name, List<VideoItem> items})>{};
      if (likesId != null) mirrored[likesId] = (name: '喜欢的视频', items: await api.playlistItems(likesId));
      for (final playlist in remote) {
        mirrored[playlist.id] = (name: playlist.title, items: playlist.count == 0 ? const [] : await api.playlistItems(playlist.id));
      }
      library.mirrorRemotePlaylists(mirrored);
      lastSync = DateTime.now();
      await _save();
      notice('同步完成：${channels.length} 个订阅（新增 $added 个），${mirrored.length} 个播放列表');
    } catch (e) {
      error = '$e';
      if (e is OAuthException && e.revoked) await signOut();
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  YouTubeAccountApi get _api => YouTubeAccountApi(_client, _accessToken);

  Future<String> _accessToken() async {
    final tokens = _tokens;
    if (tokens != null && !tokens.expired) return tokens.accessToken;
    final refreshToken = _refreshToken;
    final config = client;
    if (refreshToken == null || config == null) throw const OAuthException('请先登录 Google 账号');
    final fresh = await GoogleAuth(config, _client).refresh(refreshToken);
    _tokens = fresh;
    return fresh.accessToken;
  }

  Future<void> _save() async {
    final token = _refreshToken;
    if (token == null) return;
    try {
      await credentials.write({'refresh_token': token, 'name': name, if (lastSync != null) 'last_sync': lastSync!.toIso8601String()});
    } on FileSystemException catch (e) {
      error = '无法保存登录凭据：${e.message}';
    }
  }

  @override
  void dispose() {
    unawaited(_auth?.cancel());
    super.dispose();
  }
}
