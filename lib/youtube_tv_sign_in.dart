import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'app_log.dart';
import 'l10n/l10n.dart';
import 'native_core.dart';
import 'native_http.dart';

/// An InnerTube answer made with the TV-code sign-in.
typedef SignedAnswer = ({int status, Uint8List body});

/// InnerTube requests made signed in, as YouTube's TV app.
abstract interface class SignedInnerTube {
  bool get signedIn;

  /// [body] posted to `youtubei/v1/[endpoint]`; null when signed out.
  Future<SignedAnswer?> post(String endpoint, Map<String, Object?> body);
}

/// Where [YoutubeTvSignIn] stands.
enum TvSignInState { signedOut, waiting, signedIn }

/// Signs in the way YouTube's TV app does: the user types a short code at
/// youtube.com/activate. The sign-in, its credential and every request made
/// with it live in the Rust core (native/lumtub_core/src/tv_account.rs);
/// this side only shows where it stands. Kept apart from the Google sign-in,
/// which works with the YouTube Data API instead.
class YoutubeTvSignIn extends ChangeNotifier implements SignedInnerTube {
  YoutubeTvSignIn({required this.folder, this.base});

  /// Where the encrypted credential is kept.
  final String folder;

  /// Another server than YouTube, for tests.
  final String? base;

  TvSignInState state = TvSignInState.signedOut;
  String? error;

  /// The signed-in account's name, once read.
  String? name;

  /// While [TvSignInState.waiting]: the code to type, and where.
  String? code;
  String address = 'https://www.youtube.com/activate';

  ReceivePort? _waiting;
  bool _disposed = false;

  static _Bindings? _bindings;
  static bool _tried = false;

  static _Bindings? get _native {
    if (_tried) return _bindings;
    _tried = true;
    final core = NativeCore.instance;
    if (core == null || !NativeHttp.available) return null;
    try {
      return _bindings = _Bindings(core.library);
    } catch (e) {
      logInfo('The TV-code sign-in is not in this core: $e');
      return null;
    }
  }

  /// Whether this build can sign in with a TV code.
  static bool get available => _native != null;

  @override
  bool get signedIn => state == TvSignInState.signedIn;

  bool _opened = false;

  void load() {
    final native = _native;
    if (native == null) return;
    _opened = true;
    final open = _withText(jsonEncode({'folder': folder, if (base != null) 'base': base}), native.open);
    if (open) {
      state = TvSignInState.signedIn;
      _notify();
      unawaited(_readName());
    }
  }

  /// Asks YouTube for a code, shows it, and waits until the user has typed it
  /// in, the code runs out, or [cancel].
  void signIn() {
    final native = _native;
    if (native == null || state == TvSignInState.waiting) return;
    if (!_opened) load();
    _waiting?.close();
    final port = _waiting = ReceivePort('lumtub tv sign-in');
    error = null;
    code = null;
    state = TvSignInState.waiting;
    _notify();
    port.listen((message) {
      if (message is! List || message.isEmpty || !identical(port, _waiting)) return;
      switch (message[0]) {
        case 0:
          code = message[1] as String;
          address = message[2] as String;
        case 1:
          logInfo('Signed in with a TV code');
          _finish(port, TvSignInState.signedIn);
          unawaited(_readName());
        case 2:
          logInfo('TV code sign-in failed: ${message[1]}');
          error = _why(message[1] as String);
          _finish(port, TvSignInState.signedOut);
        case 3:
          _finish(port, TvSignInState.signedOut);
      }
      _notify();
    });
    native.signIn(port.sendPort.nativePort);
  }

  void _finish(ReceivePort port, TvSignInState next) {
    port.close();
    if (identical(_waiting, port)) _waiting = null;
    code = null;
    state = next;
  }

  static String _why(String code) => switch (code) {
        'access_denied' => tr('已在 YouTube 拒绝授权'),
        'expired_token' => tr('电视码已过期，请重新获取'),
        'invalid_grant' => tr('电视码登录已失效，请重新登录'),
        _ => tr('YouTube 授权失败（{0}）', [code]),
      };

  void cancel() {
    if (state != TvSignInState.waiting) return;
    _native?.cancel();
    _waiting?.close();
    _waiting = null;
    code = null;
    state = TvSignInState.signedOut;
    _notify();
  }

  /// Reads [name] from the account list, as SmartTube does.
  Future<void> _readName() async {
    try {
      final answer = await post('account/accounts_list', {
        'accountReadMask': {'returnOwner': true, 'returnBrandAccounts': true, 'returnPersonaAccounts': false},
      });
      if (answer == null || answer.status != 200) return;
      name = accountName(jsonDecode(utf8.decode(answer.body)));
      _notify();
    } catch (e) {
      logInfo('Could not read the TV-code account: $e');
    }
  }

  /// The selected account's name in an `account/accounts_list` answer, or
  /// the first one's.
  static String? accountName(Object? data) {
    final items = <Map>[];
    void walk(Object? node) {
      if (node is Map) {
        if (node['accountName'] != null) items.add(node);
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(data);
    final item = items.where((i) => i['isSelected'] == true).firstOrNull ?? items.firstOrNull;
    final text = item?['accountName'];
    if (text is! Map) return null;
    final simple = text['simpleText'];
    if (simple is String) return simple;
    final runs = text['runs'];
    return runs is List ? runs.map((r) => r is Map ? '${r['text'] ?? ''}' : '').join() : null;
  }

  void signOut() {
    name = null;
    _native?.signOut();
    _waiting?.close();
    _waiting = null;
    code = null;
    error = null;
    state = TvSignInState.signedOut;
    _notify();
  }

  @override
  Future<SignedAnswer?> post(String endpoint, Map<String, Object?> body) async {
    final native = _native;
    if (native == null || !signedIn) return null;
    final port = ReceivePort('lumtub tv innertube');
    final request = jsonEncode({'endpoint': endpoint, 'body': body, 'hl': youtubeHl, 'language': youtubeAcceptLanguage});
    if (!_withText(request, (p, n) => native.innertube(port.sendPort.nativePort, p, n))) {
      port.close();
      return null;
    }
    final message = await port.first as List;
    port.close();
    final status = message[0] as int;
    if (status == -1) return null;
    if (status == -2) {
      logInfo('The TV-code sign-in expired or was revoked');
      state = TvSignInState.signedOut;
      error = tr('电视码登录已失效，请重新登录');
      _notify();
      return null;
    }
    if (status == -3) throw StateError(message[1] as String);
    return (status: status, body: message[1] as Uint8List);
  }

  /// Adds [videoId], watched from [from] to [to] seconds of [length], to
  /// the account's YouTube history; the reason it could not, or null.
  Future<String?> reportWatched(String videoId, {required double from, required double to, double length = 0}) async {
    final native = _native;
    final watched = native?.watched;
    if (native == null || watched == null || !signedIn) return 'signed out';
    final port = ReceivePort('lumtub tv history');
    final request = jsonEncode({'video_id': videoId, 'from': from, 'to': to, 'length': length, 'hl': youtubeHl});
    if (!_withText(request, (p, n) => watched(port.sendPort.nativePort, p, n))) {
      port.close();
      return 'bad request';
    }
    final message = await port.first as List;
    port.close();
    return message[0] == 1 ? null : '${message.length > 1 ? message[1] : 'failed'}';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }

  static T _withText<T>(String text, T Function(Pointer<Uint8>, int) call) {
    final bytes = utf8.encode(text);
    final buffer = malloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      return call(buffer, bytes.length);
    } finally {
      malloc.free(buffer);
    }
  }
}

class _Bindings {
  _Bindings(DynamicLibrary library)
      : open = library.lookupFunction<Bool Function(Pointer<Uint8>, Size), bool Function(Pointer<Uint8>, int)>('lumtub_tv_open'),
        signIn = library.lookupFunction<Void Function(Int64), void Function(int)>('lumtub_tv_sign_in'),
        cancel = library.lookupFunction<Void Function(), void Function()>('lumtub_tv_cancel'),
        signOut = library.lookupFunction<Void Function(), void Function()>('lumtub_tv_sign_out'),
        innertube = library.lookupFunction<Bool Function(Int64, Pointer<Uint8>, Size), bool Function(int, Pointer<Uint8>, int)>('lumtub_tv_innertube'),
        watched = _optional(library, 'lumtub_tv_watched');

  static bool Function(int, Pointer<Uint8>, int)? _optional(DynamicLibrary library, String name) {
    try {
      return library.lookupFunction<Bool Function(Int64, Pointer<Uint8>, Size), bool Function(int, Pointer<Uint8>, int)>(name);
    } catch (_) {
      return null;
    }
  }

  final bool Function(Pointer<Uint8>, int) open;
  final void Function(int port) signIn;
  final void Function() cancel;
  final void Function() signOut;
  final bool Function(int port, Pointer<Uint8>, int) innertube;
  final bool Function(int port, Pointer<Uint8>, int)? watched;
}
