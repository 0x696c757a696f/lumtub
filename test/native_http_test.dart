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
    var sentEndless = 0;

    setUpAll(() async {
      NativeHttp.configure();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('http://127.0.0.1:${server.port}');
      server.listen((request) async {
        final response = request.response;
        switch (request.uri.path) {
          case '/count':
            var count = 0;
            var sum = 0;
            await for (final piece in request) {
              count += piece.length;
              for (final b in piece) {
                sum = (sum + b) % 1000003;
              }
            }
            response.write('$count $sum');
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
          case '/endless':
            for (var i = 0; i < 512; i++) {
              response.add(List.filled(64 * 1024, i % 256));
              await response.flush();
              sentEndless += 64 * 1024;
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

    test('a paused reader holds the download back instead of filling memory', () async {
      final client = NativeHttpClient();
      final response = await client.send(http.Request('GET', base.replace(path: '/endless')));
      var read = 0;
      var paused = false;
      final done = Completer<void>();
      late StreamSubscription<List<int>> reading;
      reading = response.stream.listen((piece) {
        read += piece.length;
        if (read >= 64 * 1024 && !paused) {
          paused = true;
          reading.pause();
        }
      }, onDone: done.complete);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(reading.isPaused, isTrue);
      // 32 MiB would be through a loopback socket in this time; with the
      // reader paused only the core's window and the sockets' buffers are.
      expect(sentEndless, lessThan(16 * 1024 * 1024));
      reading.resume();
      await done.future;
      expect(read, 512 * 64 * 1024);
      client.close();
    });

    test('a request whose body is still being read when the client closes never starts', () async {
      for (final size in [100, 1 << 20]) {
        final client = NativeHttpClient();
        final request = http.StreamedRequest('POST', base.replace(path: '/count'))..contentLength = size;
        final refused = expectLater(client.send(request), throwsA(isA<http.ClientException>()));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        client.close();
        request.sink.add(List.filled(size, 1));
        unawaited(request.sink.close());
        await refused;
      }
    }, skip: NativeHttp.available ? false : 'needs LUMTUB_CORE_DLL');

    test('closing the client stops its requests still running', () async {
      final client = NativeHttpClient();
      final response = await client.send(http.Request('GET', base.replace(path: '/big')));
      final failed = Completer<Object>();
      response.stream.listen((_) {}, onError: (Object e) {
        if (!failed.isCompleted) failed.complete(e);
      }, onDone: () {
        if (!failed.isCompleted) failed.complete('done');
      });
      client.close();
      final outcome = await failed.future.timeout(const Duration(seconds: 5));
      expect(outcome, isA<http.ClientException>());
      expect(() => client.send(http.Request('GET', base)), throwsA(isA<http.ClientException>()));
    }, skip: NativeHttp.available ? false : 'needs LUMTUB_CORE_DLL');

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

    test('a large file body reaches the server whole', () async {
      final dir = await Directory.systemTemp.createTemp('lumtub_http');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/audio.bin')..writeAsBytesSync(List.generate(3 << 20, (i) => i * 7 % 251));
      final whole = file.readAsBytesSync();
      var sum = 0;
      for (final b in whole) {
        sum = (sum + b) % 1000003;
      }
      final sent = http.StreamedRequest('POST', base.replace(path: '/count'))..contentLength = whole.length;
      unawaited(file.openRead().pipe(sent.sink));
      final response = await http.Response.fromStream(await NativeHttpClient().send(sent));
      expect(response.statusCode, 200);
      expect(response.body, '${whole.length} $sum');
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
        // Answers once the request is in, or the client takes the reply
        // for a message it never asked for.
        var answered = false;
        socket.listen((_) {
          if (answered) return;
          answered = true;
          socket.write('HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\ntransfer-encoding: chunked\r\n\r\n5\r\nstart\r\n');
        }, onError: (Object _) {});
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
