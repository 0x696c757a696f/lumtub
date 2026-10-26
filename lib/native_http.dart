import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;

import 'encrypted_dns.dart';
import 'native_core.dart';
import 'network_proxy.dart';

/// The app's HTTP client: requests go to the Rust core's pooled client
/// (HTTP/2, compressed bodies, the system's TLS, the app's proxy) and the
/// answers stream back on a port. Without the core, or where something
/// other than the app has replaced dart:io's clients (as widget tests do),
/// it is dart:io's client.
http.Client appHttpClient() {
  final overrides = HttpOverrides.current;
  final own = overrides == null || identical(overrides, appHttpOverrides);
  return own && NativeHttp.available ? NativeHttpClient() : http.Client();
}

/// [url] for the Rust client, which reaches a SOCKS proxy itself. Names are
/// looked up by the proxy, as the bridge does, so blocked DNS does not matter.
String? nativeProxy(String? url) {
  if (url == null) return null;
  if (url.startsWith('socks5://')) return 'socks5h://${url.substring(9)}';
  if (url.startsWith('socks4://')) return 'socks4a://${url.substring(9)}';
  return url;
}

/// The Rust side of [NativeHttpClient], shared by every client.
abstract final class NativeHttp {
  static _Bindings? _bindings;
  static bool _tried = false;

  static _Bindings? get _native {
    if (_tried) return _bindings;
    _tried = true;
    final core = NativeCore.instance;
    if (core == null) return null;
    try {
      final b = _Bindings(core.library);
      b.init(NativeApi.postCObject);
      return _bindings = b;
    } catch (_) {
      return null;
    }
  }

  static bool get available => _native != null;

  /// Routes new connections through [proxy] (`http://…` or `socks5://…`);
  /// with none, through the system's proxy when [system], else directly.
  /// [dns] looks names up for direct connections instead of the system.
  static void configure({String? proxy, bool system = false, DnsServer? dns}) {
    final native = _native;
    if (native == null) return;
    final bytes = utf8.encode(jsonEncode({'proxy': proxy, 'system': system, 'dns': dns?.toJson() ?? const {}}));
    _withBytes(bytes, (p, n) => native.configure(p, n));
  }

  static int _nextId = 1;
  static ReceivePort? _port;
  static final _open = <int, _Pending>{};

  static SendPort get _sendPort {
    final port = _port ??= ReceivePort('lumtub http')..listen(_receive);
    return port.sendPort;
  }

  static void _receive(Object? message) {
    if (message is! List || message.length < 2) return;
    final pending = _open[message[0]];
    if (pending == null) return;
    switch (message[1]) {
      case 0:
        pending.head(message[2] as int, message[3] as String, message[4] as int?, message.length > 5 ? message[5] as String? : null);
      case 1:
        pending.body.add(message[2] as Uint8List);
      case 2:
        _open.remove(message[0]);
        unawaited(pending.body.close());
      case 3:
        _open.remove(message[0]);
        pending.fail(message[2] as String);
    }
  }

  static T _withBytes<T>(List<int> bytes, T Function(Pointer<Uint8>, int) call) {
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
      : init = library.lookupFunction<Void Function(Pointer<NativeFunction<Int8 Function(Int64, Pointer<Dart_CObject>)>>), void Function(Pointer<NativeFunction<Int8 Function(Int64, Pointer<Dart_CObject>)>>)>('lumtub_http_init'),
        configure = library.lookupFunction<Void Function(Pointer<Uint8>, Size), void Function(Pointer<Uint8>, int)>('lumtub_http_configure'),
        send = library.lookupFunction<Bool Function(Int64, Int64, Pointer<Uint8>, Size, Pointer<Uint8>, Size), bool Function(int, int, Pointer<Uint8>, int, Pointer<Uint8>, int)>('lumtub_http_send'),
        cancel = library.lookupFunction<Void Function(Int64), void Function(int)>('lumtub_http_cancel');

  final void Function(Pointer<NativeFunction<Int8 Function(Int64, Pointer<Dart_CObject>)>>) init;
  final void Function(Pointer<Uint8>, int) configure;
  final bool Function(int id, int port, Pointer<Uint8> json, int length, Pointer<Uint8> body, int bodyLength) send;
  final void Function(int id) cancel;
}

/// A request waiting for its head, then streaming its body.
class _Pending {
  _Pending(this.id, this.request) {
    body = StreamController<List<int>>(onCancel: () {
      if (NativeHttp._open.remove(id) != null) NativeHttp._native?.cancel(id);
    });
  }
  final int id;
  final http.BaseRequest request;
  final response = Completer<http.StreamedResponse>();
  late final StreamController<List<int>> body;

  void head(int status, String headersJson, int? length, String? url) {
    final headers = <String, String>{};
    for (final pair in jsonDecode(headersJson) as List) {
      final name = (pair[0] as String).toLowerCase();
      final value = pair[1] as String;
      // As dart:io joins repeated headers.
      headers[name] = headers.containsKey(name) ? '${headers[name]},$value' : value;
    }
    response.complete(http.StreamedResponse(
      body.stream,
      status,
      // Null for a body the core decompresses.
      contentLength: length,
      request: request,
      headers: headers,
      isRedirect: false,
      reasonPhrase: null,
    ));
  }

  void fail(String message) {
    final error = http.ClientException(message, request.url);
    if (!response.isCompleted) {
      response.completeError(error);
      unawaited(body.close());
    } else {
      body.addError(error);
      unawaited(body.close());
    }
  }
}

/// An [http.Client] whose requests the Rust core makes.
class NativeHttpClient extends http.BaseClient {
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Client is closed', request.url);
    final native = NativeHttp._native;
    if (native == null) throw http.ClientException('The native HTTP client is missing', request.url);
    final bytes = await request.finalize().toBytes();
    final headers = [
      for (final MapEntry(:key, :value) in request.headers.entries) [key, value],
    ];
    final meta = utf8.encode(jsonEncode({'method': request.method, 'url': request.url.toString(), 'headers': headers}));
    final id = NativeHttp._nextId++;
    final pending = _Pending(id, request);
    NativeHttp._open[id] = pending;
    final port = NativeHttp._sendPort.nativePort;
    final started = NativeHttp._withBytes(meta, (m, ml) => NativeHttp._withBytes(bytes, (b, bl) => native.send(id, port, m, ml, b, bl)));
    if (!started) {
      NativeHttp._open.remove(id);
      throw http.ClientException('Could not start the request', request.url);
    }
    return pending.response.future;
  }

  @override
  void close() => _closed = true;
}
