import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lumtub/native_http.dart';

void main() {
  test('SOCKS proxies let the proxy look up names', () {
    expect(nativeProxy('socks5://u:p@127.0.0.1:1080'), 'socks5h://u:p@127.0.0.1:1080');
    expect(nativeProxy('socks4://127.0.0.1:1080'), 'socks4a://127.0.0.1:1080');
    expect(nativeProxy('http://127.0.0.1:8080'), 'http://127.0.0.1:8080');
    expect(nativeProxy(null), isNull);
  });

  group('native client', () {
    late HttpServer server;
    late Uri base;
    final hold = Completer<void>();

    setUpAll(() async {
      NativeHttp.configure();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('http://127.0.0.1:${server.port}');
      server.listen((request) async {
        final response = request.response;
        switch (request.uri.path) {
          case '/echo':
            final body = await utf8.decodeStream(request);
            response.headers.set('x-method', request.method);
            response.headers.add('set-cookie', 'a=1');
            response.headers.add('set-cookie', 'b=2');
            response.write(jsonEncode({'body': body, 'agent': request.headers.value('user-agent'), 'type': request.headers.contentType?.mimeType}));
          case '/gzip':
            response.headers.set('content-encoding', 'gzip');
            response.add(gzip.encode(utf8.encode('压缩的内容' * 1000)));
          case '/big':
            for (var i = 0; i < 40; i++) {
              response.add(List.filled(32 * 1024, i));
              await response.flush();
            }
          case '/redirect':
            response.redirect(base.replace(path: '/echo'));
            return;
          case '/missing':
            response.statusCode = 404;
            response.write('nope');
        }
        await response.close();
      });
    });

    tearDownAll(() async {
      hold.complete();
      await server.close(force: true);
    });

    test('is the app client when the core is there', () {
      expect(NativeHttp.available, isTrue);
      expect(appHttpClient(), isA<NativeHttpClient>());
    }, skip: NativeHttp.available ? false : 'needs LUMTUB_CORE_DLL');

    test('sends a body and headers and reads the answer', () async {
      final client = NativeHttpClient();
      final response = await client.post(base.replace(path: '/echo'), headers: {'user-agent': 'Lumtub test', 'content-type': 'application/json'}, body: '{"字":1}');
      expect(response.statusCode, 200);
      expect(response.headers['x-method'], 'POST');
      expect(response.headers['set-cookie'], 'a=1,b=2');
      expect(jsonDecode(response.body), {'body': '{"字":1}', 'agent': 'Lumtub test', 'type': 'application/json'});
    }, skip: NativeHttp.available ? false : 'needs LUMTUB_CORE_DLL');

    test('decompresses, streams big bodies and follows redirects', () async {
      final client = NativeHttpClient();
      expect((await client.get(base.replace(path: '/gzip'))).body, '压缩的内容' * 1000);
      final big = await client.get(base.replace(path: '/big'));
      expect(big.bodyBytes.length, 40 * 32 * 1024);
      expect(big.bodyBytes[32 * 1024 * 39], 39);
      final moved = await client.get(base.replace(path: '/redirect'));
      expect(moved.statusCode, 200);
      expect(jsonDecode(moved.body)['body'], '');
      expect((await client.get(base.replace(path: '/missing'))).statusCode, 404);
    }, skip: NativeHttp.available ? false : 'needs LUMTUB_CORE_DLL');

    test('fails as dart:io does and can be cancelled', () async {
      final client = NativeHttpClient();
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      await expectLater(client.get(Uri.parse('http://127.0.0.1:$port/')), throwsA(isA<http.ClientException>()));
      // A raw socket, as HttpServer holds small writes back.
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      raw.listen((socket) {
        socket.write('HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\ntransfer-encoding: chunked\r\n\r\n5\r\nstart\r\n');
        unawaited(hold.future.then((_) => socket.destroy()));
      });
      final streamed = await client.send(http.Request('GET', Uri.parse('http://127.0.0.1:${raw.port}/')));
      final first = await streamed.stream.first.timeout(const Duration(seconds: 5));
      expect(utf8.decode(first), 'start');
      await raw.close();
      // Reading again still works after a cancelled request.
      expect((await client.get(base.replace(path: '/missing'))).statusCode, 404);
    }, skip: NativeHttp.available ? false : 'needs LUMTUB_CORE_DLL');
  });
}
