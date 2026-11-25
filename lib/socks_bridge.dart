import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'native_core.dart';
import 'app_log.dart';

/// A local HTTP proxy that forwards through a SOCKS proxy. libmpv and
/// dart:io can only use HTTP proxies, so a SOCKS setting reaches them as
/// `http://127.0.0.1:port`. It accepts `CONNECT host:port` (https) and
/// plain absolute-URI requests (http), listens on loopback only, and when
/// the SOCKS proxy fails the request fails: nothing connects directly.
abstract interface class SocksBridge {
  /// Listens on a random loopback port and forwards through [proxyUrl]
  /// (`socks5://[user:pass@]host:port`, also `socks5h`, `socks4`, `socks4a`):
  /// lumtub_core's bridge, whose connections never pass through Dart, or
  /// the Dart one when the core cannot start it. [native] false is the
  /// Dart one alone.
  static Future<SocksBridge> start(String proxyUrl, {bool native = true}) async {
    if (NativeCore.instance case final core? when native) {
      final handle = core.withText(proxyUrl, core.socksStart);
      if (handle != nullptr) return _NativeBridge(core, handle);
    }
    final bridge = DartSocksBridge._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), Uri.parse(proxyUrl));
    bridge._server.listen(bridge._handle);
    return bridge;
  }

  /// The user name a client gives with [token] as its password.
  static const user = 'lumtub';

  int get port;

  /// The password the bridge asks every client for, so other programs on
  /// this PC cannot use the user's proxy through it.
  String get token;

  /// `lumtub:token@127.0.0.1:port`, for dart:io's `PROXY` rule and, after
  /// `http://`, for libmpv and the relay.
  String get hostPort;

  /// Stops listening and drops the connections still open.
  Future<void> close();
}

class _NativeBridge implements SocksBridge {
  _NativeBridge(this._core, this._handle) : port = _core.socksPort(_handle), token = _core.take(_core.socksToken(_handle)) ?? '';

  final NativeCore _core;
  Pointer<Void> _handle;

  @override
  final int port;
  @override
  final String token;
  @override
  String get hostPort => '${SocksBridge.user}:$token@127.0.0.1:$port';

  @override
  Future<void> close() async {
    if (_handle == nullptr) return;
    _core.socksClose(_handle);
    _handle = nullptr;
  }
}

/// The bridge in Dart, used when lumtub_core cannot start one.
class DartSocksBridge implements SocksBridge {
  DartSocksBridge._(this._server, this._proxy) : token = _newToken() {
    _login = 'Basic ${base64.encode(utf8.encode('${SocksBridge.user}:$token'))}';
  }

  final ServerSocket _server;
  final Uri _proxy;
  final _open = <Socket>{};
  late final String _login;

  static String _newToken() {
    final random = Random.secure();
    return [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }

  @override
  int get port => _server.port;
  @override
  final String token;
  @override
  String get hostPort => '${SocksBridge.user}:$token@127.0.0.1:$port';

  @override
  Future<void> close() async {
    await _server.close();
    for (final socket in _open.toList()) {
      socket.destroy();
    }
  }

  Future<void> _handle(Socket client) async {
    _open.add(client);
    _Reader? upstream;
    try {
      final reader = _Reader(client);
      final head = await reader.head().timeout(_timeout, onTimeout: () => throw const _Bad());
      final end = head.indexOf(13); // end of the request line
      // The other header lines, without the login: it is not sent on.
      final fields = <String>[];
      var allowed = false;
      for (final field in latin1.decode(head.sublist(end + 2)).split('\r\n')) {
        if (field.toLowerCase().startsWith('proxy-authorization:')) {
          allowed |= _same(field.substring(20).trim(), _login);
        } else {
          fields.add(field);
        }
      }
      if (!allowed) throw const _Bad(407);
      final line = latin1.decode(head.sublist(0, end)).split(' ');
      if (line.length != 3) throw const _Bad();
      final String host;
      final int port;
      var forward = <int>[];
      if (line[0].toUpperCase() == 'CONNECT') {
        final colon = line[1].lastIndexOf(':');
        if (colon < 0) throw const _Bad();
        host = line[1].substring(0, colon).replaceAll(RegExp(r'^\[|\]$'), '');
        port = int.tryParse(line[1].substring(colon + 1)) ?? 0;
      } else {
        final uri = Uri.tryParse(line[1]);
        if (uri == null || uri.scheme != 'http' || uri.host.isEmpty) throw const _Bad();
        host = uri.host;
        port = uri.hasPort ? uri.port : 80;
        final target = '${uri.path.isEmpty ? '/' : uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
        forward = latin1.encode('${line[0]} $target ${line[2]}\r\n${fields.join('\r\n')}');
      }
      if (port <= 0 || port > 65535) throw const _Bad();
      try {
        upstream = await _connectViaSocks(_proxy, host, port);
      } catch (_) {
        throw const _Bad(502);
      }
      _open.add(upstream.socket);
      if (forward.isEmpty) {
        client.add(latin1.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
      } else {
        upstream.socket.add(forward);
      }
      await Future.wait([_pump(reader, upstream.socket), _pump(upstream, client)]);
    } on _Bad catch (e) {
      try {
        final status = switch (e.status) {
          502 => '502 Bad Gateway',
          407 => '407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm="lumtub"',
          _ => '400 Bad Request',
        };
        client.add(latin1.encode('HTTP/1.1 $status\r\nConnection: close\r\nContent-Length: 0\r\n\r\n'));
        await client.flush();
      } catch (e) {
        logDebug(() => 'Could not send the proxy error answer: $e');
      }
    } catch (_) {
      // The client went away.
    } finally {
      client.destroy();
      upstream?.socket.destroy();
      _open.remove(client);
      _open.remove(upstream?.socket);
    }
  }

  /// Copies [from] to [to], then closes [to]'s writing side; an error ends both.
  Future<void> _pump(_Reader from, Socket to) async {
    try {
      await for (final chunk in from.rest()) {
        to.add(chunk);
        await to.flush();
      }
      await to.close();
    } catch (_) {
      from.socket.destroy();
      to.destroy();
    }
  }
}

const _timeout = Duration(seconds: 15);

/// Whether [a] and [b] are equal, compared in time that does not depend on
/// where they differ.
bool _same(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

class _Bad implements Exception {
  const _Bad([this.status = 400]);
  final int status;
}

/// A socket with the bytes read from it but not yet used.
class _Reader {
  _Reader(this.socket) : _chunks = StreamIterator(socket);
  final Socket socket;
  final StreamIterator<List<int>> _chunks;
  final _buffer = <int>[];

  Future<void> _more() async {
    if (!await _chunks.moveNext()) throw const SocketException.closed();
    _buffer.addAll(_chunks.current);
  }

  Future<List<int>> take(int count) async {
    while (_buffer.length < count) {
      await _more();
    }
    final out = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return out;
  }

  /// An HTTP request head, up to and including the blank line.
  Future<List<int>> head() async {
    // Each byte is looked at once, not again with every chunk.
    var from = 0;
    while (true) {
      for (var i = from; i + 3 < _buffer.length; i++) {
        if (_buffer[i] == 13 && _buffer[i + 1] == 10 && _buffer[i + 2] == 13 && _buffer[i + 3] == 10) return take(i + 4);
      }
      from = max(0, _buffer.length - 3);
      if (_buffer.length > 64 * 1024) throw const _Bad();
      await _more();
    }
  }

  /// Everything still to come, buffered bytes first.
  Stream<List<int>> rest() async* {
    if (_buffer.isNotEmpty) {
      yield List.of(_buffer);
      _buffer.clear();
    }
    while (await _chunks.moveNext()) {
      yield _chunks.current;
    }
  }
}

/// Opens a tunnel to [host]:[port] through the SOCKS proxy [proxy]. socks5h
/// and socks4a send the name to the proxy; socks5 and socks4 resolve it here.
Future<_Reader> _connectViaSocks(Uri proxy, String host, int port) async {
  // This PC (the app's own relay) is reached directly: through the proxy,
  // 127.0.0.1 would be the proxy server's own machine.
  if (host.toLowerCase() == 'localhost' || (InternetAddress.tryParse(host)?.isLoopback ?? false)) {
    return _Reader(await Socket.connect(host, port, timeout: _timeout));
  }
  final socket = await Socket.connect(proxy.host, proxy.port, timeout: _timeout);
  final reader = _Reader(socket);
  try {
    final parts = proxy.userInfo.split(':');
    final user = utf8.encode(Uri.decodeComponent(parts.first));
    final pass = utf8.encode(Uri.decodeComponent(parts.skip(1).join(':')));
    if (proxy.scheme.startsWith('socks4')) {
      await _socks4(socket, reader, host, port, user, remoteDns: proxy.scheme == 'socks4a');
    } else {
      await _socks5(socket, reader, host, port, user, pass, remoteDns: proxy.scheme == 'socks5h');
    }
    return reader;
  } catch (_) {
    socket.destroy();
    rethrow;
  }
}

List<int> _portBytes(int port) => [port >> 8, port & 255];

/// RFC 1928, with the username/password step of RFC 1929.
Future<void> _socks5(Socket socket, _Reader reader, String host, int port, List<int> user, List<int> pass, {required bool remoteDns}) async {
  final login = user.isNotEmpty;
  socket.add([5, login ? 2 : 1, 0, if (login) 2]);
  final choice = await reader.take(2).timeout(_timeout);
  if (choice[0] != 5) throw const SocketException('not a SOCKS5 server');
  if (choice[1] == 2 && login) {
    socket.add([1, user.length, ...user, pass.length, ...pass]);
    if ((await reader.take(2).timeout(_timeout))[1] != 0) throw const SocketException('SOCKS5 login refused');
  } else if (choice[1] != 0) {
    throw const SocketException('SOCKS5 method refused');
  }
  var ip = InternetAddress.tryParse(host);
  if (ip == null && !remoteDns) ip = (await InternetAddress.lookup(host)).first;
  final name = utf8.encode(host);
  socket.add([
    5, 1, 0,
    if (ip != null) ...[ip.type == InternetAddressType.IPv4 ? 1 : 4, ...ip.rawAddress] else ...[3, name.length, ...name],
    ..._portBytes(port),
  ]);
  final reply = await reader.take(4).timeout(_timeout);
  if (reply[1] != 0) throw SocketException('SOCKS5 connect failed (${reply[1]})');
  final skip = switch (reply[3]) { 1 => 4, 4 => 16, _ => (await reader.take(1))[0] };
  await reader.take(skip + 2).timeout(_timeout);
}

Future<void> _socks4(Socket socket, _Reader reader, String host, int port, List<int> user, {required bool remoteDns}) async {
  var ip = InternetAddress.tryParse(host);
  if (ip == null && !remoteDns) ip = (await InternetAddress.lookup(host, type: InternetAddressType.IPv4)).first;
  if (ip != null && ip.type != InternetAddressType.IPv4) throw const SocketException('SOCKS4 has no IPv6');
  socket.add([
    4, 1, ..._portBytes(port),
    if (ip != null) ...ip.rawAddress else ...[0, 0, 0, 1],
    ...user, 0,
    if (ip == null) ...[...utf8.encode(host), 0],
  ]);
  final reply = await reader.take(8).timeout(_timeout);
  if (reply[1] != 90) throw SocketException('SOCKS4 connect failed (${reply[1]})');
}
