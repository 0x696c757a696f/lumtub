import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'l10n/l10n.dart';
import 'app_log.dart';
import 'secure_store.dart';

/// Where [YoutubeTvSignIn] stands.
enum TvSignInState { signedOut, waiting, signedIn }

/// Signs in the way YouTube's TV app does: the user types a short code at
/// youtube.com/activate. YouTube's own pages take only this kind of sign-in,
/// so comments and posts can be liked and disliked with it. Kept apart from
/// the Google sign-in, which works with the YouTube Data API instead.
class YoutubeTvSignIn extends ChangeNotifier {
  YoutubeTvSignIn({required this.credentials, required http.Client client, Duration? pollFloor})
      : _client = client,
        _pollFloor = pollFloor ?? const Duration(seconds: 5);

  final SecureJsonFile credentials;
  final http.Client _client;
  final Duration _pollFloor;

  /// The YouTube TV app's own client, as every TV-code sign-in uses it.
  static const clientId = '861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com';
  static const clientSecret = 'SboVhoG9s0rNafixCSGGKXAT';
  static const scope = 'http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content';
  static final codeEndpoint = Uri.parse('https://www.youtube.com/o/oauth2/device/code');
  static final tokenEndpoint = Uri.parse('https://www.youtube.com/o/oauth2/token');

  TvSignInState state = TvSignInState.signedOut;
  String? error;

  /// While [TvSignInState.waiting]: the code to type, and where.
  String? code;
  String address = 'https://www.youtube.com/activate';

  String? _refreshToken;
  String? _accessToken;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);
  int _attempt = 0;

  bool get signedIn => state == TvSignInState.signedIn;

  Future<void> load() async {
    final token = (await credentials.read())?['refresh_token'];
    if (token is String && token.isNotEmpty) {
      _refreshToken = token;
      state = TvSignInState.signedIn;
      notifyListeners();
    }
  }

  /// Asks YouTube for a code, shows it, and waits until the user has typed it
  /// in, the code runs out, or [cancel].
  Future<void> signIn() async {
    if (state == TvSignInState.waiting) return;
    final attempt = ++_attempt;
    error = null;
    state = TvSignInState.waiting;
    code = null;
    notifyListeners();
    try {
      final device = _json(await _client.post(codeEndpoint, body: {
        'client_id': clientId,
        'scope': scope,
        'device_id': _deviceId(),
        'device_model': 'ytlr::',
      }).timeout(const Duration(seconds: 20)));
      final deviceCode = device['device_code'] as String?;
      if (deviceCode == null) throw StateError(tr('YouTube 没有给出电视码'));
      code = device['user_code'] as String?;
      address = device['verification_url'] as String? ?? address;
      notifyListeners();
      var wait = Duration(seconds: (device['interval'] as num?)?.toInt() ?? 5);
      if (wait < _pollFloor) wait = _pollFloor;
      final until = DateTime.now().add(Duration(seconds: (device['expires_in'] as num?)?.toInt() ?? 1800));
      while (attempt == _attempt) {
        await Future<void>.delayed(wait);
        if (attempt != _attempt) return;
        if (DateTime.now().isAfter(until)) throw StateError(tr('电视码已过期，请重新获取'));
        final answer = _json(await _client.post(tokenEndpoint, body: {
          'client_id': clientId,
          'client_secret': clientSecret,
          'code': deviceCode,
          'grant_type': 'http://oauth.net/grant_type/device/1.0',
        }).timeout(const Duration(seconds: 20)), allowError: true);
        switch (answer['error']) {
          case 'authorization_pending':
            continue;
          case 'slow_down':
            wait += const Duration(seconds: 5);
            continue;
          case 'access_denied':
            throw StateError(tr('已在 YouTube 拒绝授权'));
          case 'expired_token':
            throw StateError(tr('电视码已过期，请重新获取'));
          case final String other:
            throw StateError(tr('YouTube 授权失败（{0}）', [other]));
        }
        final refresh = answer['refresh_token'] as String?;
        if (refresh == null) throw StateError(tr('YouTube 没有返回长期凭据，请重试'));
        _take(answer);
        _refreshToken = refresh;
        await credentials.write({'refresh_token': refresh});
        code = null;
        state = TvSignInState.signedIn;
        logInfo('Signed in with a TV code');
        notifyListeners();
        return;
      }
    } catch (e) {
      if (attempt != _attempt) return;
      logInfo('TV code sign-in failed: $e');
      code = null;
      state = TvSignInState.signedOut;
      error = '$e';
      notifyListeners();
    }
  }

  void cancel() {
    if (state != TvSignInState.waiting) return;
    _attempt++;
    code = null;
    state = TvSignInState.signedOut;
    notifyListeners();
  }

  Future<void> signOut() async {
    _attempt++;
    _refreshToken = null;
    _accessToken = null;
    code = null;
    error = null;
    state = TvSignInState.signedOut;
    notifyListeners();
    await credentials.delete();
  }

  /// A current access token, or null when not signed in. A sign-in YouTube no
  /// longer takes signs out, saying so.
  Future<String?> accessToken() async {
    final refresh = _refreshToken;
    if (refresh == null) return null;
    final current = _accessToken;
    if (current != null && DateTime.now().isBefore(_expires)) return current;
    final answer = _json(await _client.post(tokenEndpoint, body: {
      'client_id': clientId,
      'client_secret': clientSecret,
      'refresh_token': refresh,
      'grant_type': 'refresh_token',
    }).timeout(const Duration(seconds: 20)), allowError: true);
    if (answer['error'] == 'invalid_grant') {
      if (_refreshToken == refresh) {
        await signOut();
        error = tr('电视码登录已失效，请重新登录');
        notifyListeners();
      }
      return null;
    }
    if (answer['error'] != null) throw StateError(tr('YouTube 授权失败（{0}）', [answer['error']]));
    _take(answer);
    return _accessToken;
  }

  void _take(Map<String, dynamic> answer) {
    _accessToken = answer['access_token'] as String?;
    final seconds = (answer['expires_in'] as num?)?.toInt() ?? 3600;
    _expires = DateTime.now().add(Duration(seconds: seconds - 60));
  }

  static Map<String, dynamic> _json(http.Response response, {bool allowError = false}) {
    Object? data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {}
    if (data is Map<String, dynamic> && (response.statusCode == 200 || (allowError && data['error'] != null))) return data;
    throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
  }

  static String _deviceId() {
    final random = Random.secure();
    final bytes = [for (var i = 0; i < 16; i++) random.nextInt(256)];
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
