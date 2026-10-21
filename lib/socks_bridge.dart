import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A local HTTP proxy that forwards through a SOCKS proxy. libmpv and
/// dart:io can only use HTTP proxies, so a SOCKS setting reaches them as
/// `http://127.0.0.1:port`. It accepts `CONNECT host:port` (https) and
/// plain absolute-URI requests (http), listens on loopback only, and when
/// the SOCKS proxy fails the request fails: nothing connects directly.
class SocksBridge {
  SocksBridge._(this._server, this._proxy);

  /// Listens on a random loopback port and forwards through [proxyUrl]
  /// (`socks5://[user:pass@]host:port`, also `socks5h`, `socks4`, `socks4a`).
  static Future<SocksBridge> start(String proxyUrl) async {
    final bridge = SocksBridge._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), Uri.parse(proxyUrl));
    bridge._server.listen(bridge._handle);
    return bridge;
  }

  final ServerSocket _server;
  final Uri _proxy;
  final _open = <Socket>{};

  int get port => _server.port;
  String get hostPort => '127.0.0.1:$port';

  /// Stops listening and drops the connections still open.
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
        forward = [...latin1.encode('${line[0]} $target ${line[2]}'), ...head.sublist(end)];
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
        client.add(latin1.encode('HTTP/1.1 ${e.status} ${e.status == 502 ? 'Bad Gateway' : 'Bad Request'}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n'));
        await client.flush();
      } catch (_) {}
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
    while (true) {
      for (var i = 0; i + 3 < _buffer.length; i++) {
        if (_buffer[i] == 13 && _buffer[i + 1] == 10 && _buffer[i + 2] == 13 && _buffer[i + 3] == 10) return take(i + 4);
      }
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
