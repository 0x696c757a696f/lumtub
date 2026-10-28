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
import 'youtube_tv_sign_in.dart';
import 'youtube_web.dart';

/// InnerTube requests made as the signed-in YouTube website. [ask] is for
/// something the user did: the system's prompt to open the sign-in comes
/// up again even after it was closed.
abstract interface class WebInnerTube implements SignedInnerTube {
  @override
  Future<SignedAnswer?> post(String endpoint, Map<String, Object?> body, {bool ask = false});
}

/// What keeps the saved cookies shut, as the Rust core reports it.
enum CookieGuard { presence, hardware, keyring, account, file }

/// The cookie sign-in: YouTube's website signed in with the cookies of a
/// browser session, taken from a browser window of its own or from a
/// cookies.txt. It is what liking posts, voting in polls and writing under
/// posts take. The cookies, their encryption and every request made with
/// them live in the Rust core (native/lumtub_core/src/web_account.rs,
/// vault.rs, browser_sign_in.rs); this side never sees them.
class YoutubeWebSignIn extends ChangeNotifier implements WebInnerTube {
  YoutubeWebSignIn({required this.folder, this.base});

  /// Where the sealed cookies are kept.
  final String folder;

  /// Another server than YouTube, for tests.
  final String? base;

  bool _signedIn = false;
  CookieGuard? guard;

  /// Opened since the app started: the system no longer asks.
  bool unlocked = false;

  /// While the browser window is open: its name.
  String? browser;
  bool waiting = false;

  /// The window was closed and the cookies are being read.
  bool reading = false;
  String? error;

  /// Counts the sign-ins made in this run.
  int signIns = 0;

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
      logInfo('The cookie sign-in is not in this core: $e');
      return null;
    }
  }

  /// Whether this build can sign in with cookies.
  static bool get available => _native != null;

  @override
  bool get signedIn => _signedIn;

  /// What the system's prompt says when it asks to open the cookies.
  static String get reason => tr('Lumtub 要使用你保存的 YouTube 登录');

  void load() {
    final native = _native;
    if (native == null) return;
    _read(_take(_withText(jsonEncode({'folder': folder, 'reason': reason, if (base != null) 'base': base}), native.open)));
  }

  void _read(String? status) {
    final data = status == null ? null : jsonDecode(status);
    if (data is! Map) return;
    _signedIn = data['signedIn'] == true;
    unlocked = data['unlocked'] == true;
    guard = CookieGuard.values.where((g) => g.name == data['guard']).firstOrNull;
    _notify();
  }

  void _refresh() {
    final native = _native;
    if (native != null) _read(_take(native.status()));
  }

  /// Opens a browser window of its own at Google's sign-in and keeps the
  /// cookies once the user has signed in and closed it. [presence] asks for Windows
  /// Hello, Touch ID or the password to open them later.
  void signInWithBrowser({bool presence = true}) {
    final native = _native;
    if (native == null || waiting) return;
    _start((port) => _withText(jsonEncode({'hello': presence}), (p, n) => native.browserSignIn(port.sendPort.nativePort, p, n)));
  }

  /// Keeps the cookies of the cookies.txt at [path]; wipes and deletes the
  /// file after when [delete].
  void importFile(String path, {bool presence = true, bool delete = false}) {
    final native = _native;
    if (native == null || waiting) return;
    _start((port) => _withText(jsonEncode({'path': path, 'hello': presence, 'delete': delete}), (p, n) => native.import(port.sendPort.nativePort, p, n)));
  }

  void _start(bool Function(ReceivePort port) begin) {
    _waiting?.close();
    final port = _waiting = ReceivePort('lumtub cookie sign-in');
    error = null;
    browser = null;
    reading = false;
    waiting = true;
    _notify();
    port.listen((message) {
      if (message is! List || message.isEmpty || !identical(port, _waiting)) return;
      switch (message[0]) {
        case 1:
          browser = message[1] as String;
        case 2:
          reading = true;
        case 0:
          logInfo('Signed in with cookies (${message[1]}, kept by ${message[2]})');
          signIns++;
          _finish(port);
          _refresh();
        case -4:
          _finish(port);
        case -2:
          logInfo('Cookie sign-in failed: ${message[1]}');
          error = _why(message[1] as String);
          _finish(port);
      }
      _notify();
    });
    if (!begin(port)) {
      error = tr('Cookie 登录没有启动');
      _finish(port);
      _notify();
    }
  }

  void _finish(ReceivePort port) {
    port.close();
    if (identical(_waiting, port)) _waiting = null;
    waiting = false;
    reading = false;
    browser = null;
  }

  static String _why(String code) => switch (code) {
        'no browser' => tr('没有找到 Edge、Chrome 或其他 Chromium 内核的浏览器，请改用导入 cookies.txt'),
        'not signed in' => tr('这些 Cookie 没有登录 YouTube'),
        'closed before signing in' => tr('浏览器窗口关闭时还没有登录 YouTube，请登录完成后再关闭'),
        'no youtube.com cookies' => tr('文件里没有 youtube.com 的 Cookie'),
        _ => tr('Cookie 登录失败（{0}）', [code]),
      };

  /// Closes the browser window of a sign-in that is waiting.
  void cancel() {
    if (!waiting) return;
    _native?.browserCancel();
  }

  void signOut() {
    _native?.signOut();
    _waiting?.close();
    _waiting = null;
    waiting = false;
    error = null;
    _refresh();
  }

  /// [body] posted to `youtubei/v1/[endpoint]` as the signed-in website;
  /// null when signed out, or when the user closed the system's prompt to
  /// open the cookies. [ask] is for something the user did: the prompt
  /// comes up again even after it was closed.
  @override
  Future<SignedAnswer?> post(String endpoint, Map<String, Object?> body, {bool ask = false}) async {
    final native = _native;
    if (native == null || !signedIn) return null;
    final port = ReceivePort('lumtub web innertube');
    final request = jsonEncode({'endpoint': endpoint, 'body': body, 'hl': youtubeHl, 'language': youtubeAcceptLanguage, 'clientVersion': YoutubeWeb.clientVersion, 'ask': ask});
    if (!_withText(request, (p, n) => native.innertube(port.sendPort.nativePort, p, n))) {
      port.close();
      return null;
    }
    final message = await port.first as List;
    port.close();
    final status = message[0] as int;
    if (!unlocked) _refresh();
    if (status == -1 || status == -4) return null;
    if (status == -3) throw StateError(message[1] as String);
    return (status: status, body: message[1] as Uint8List);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    _waiting?.close();
    super.dispose();
  }

  static String? _take(Pointer<Utf8> value) => NativeCore.instance?.take(value);

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
      : open = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_web_open'),
        status = library.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('lumtub_web_status'),
        import = library.lookupFunction<Bool Function(Int64, Pointer<Uint8>, Size), bool Function(int, Pointer<Uint8>, int)>('lumtub_web_import'),
        browserSignIn = library.lookupFunction<Bool Function(Int64, Pointer<Uint8>, Size), bool Function(int, Pointer<Uint8>, int)>('lumtub_web_browser_sign_in'),
        browserCancel = library.lookupFunction<Void Function(), void Function()>('lumtub_web_browser_cancel'),
        signOut = library.lookupFunction<Void Function(), void Function()>('lumtub_web_sign_out'),
        innertube = library.lookupFunction<Bool Function(Int64, Pointer<Uint8>, Size), bool Function(int, Pointer<Uint8>, int)>('lumtub_web_innertube');

  final Pointer<Utf8> Function(Pointer<Uint8>, int) open;
  final Pointer<Utf8> Function() status;
  final bool Function(int port, Pointer<Uint8>, int) import;
  final bool Function(int port, Pointer<Uint8>, int) browserSignIn;
  final void Function() browserCancel;
  final void Function() signOut;
  final bool Function(int port, Pointer<Uint8>, int) innertube;
}
