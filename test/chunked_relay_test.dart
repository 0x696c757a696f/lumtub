import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/chunked_relay.dart';
import 'package:lumtub/native_core.dart';

void main() {
  for (final native in [false, true]) {
    group(native ? 'lumtub_core relay' : 'Dart relay', () => _tests(native));
  }

  test('tells a refused relay from other refusals', () {
    expect(loopbackRefused('tcp: Connection to tcp://127.0.0.1:49620 failed: Connection refused'),
        isTrue);
    expect(loopbackRefused('Failed to open http://localhost:4000/abc: Connection refused'), isTrue);
    expect(
        loopbackRefused(
            'tcp: Connection to tcp://rr3---sn.googlevideo.com:443 failed: Connection refused'),
        isFalse);
    expect(loopbackRefused('Failed to open http://127.0.0.1:49620/abc: HTTP 404'), isFalse);
  });

  test('a working relay keeps its addresses after a check', () async {
    final relay = ChunkedRelay();
    await relay.start();
    final before = relay.register('https://example.invalid/v?clen=10', size: 10)!;
    await relay.revive();
    final after = relay.register('https://example.invalid/v?clen=10', size: 10)!;
    expect(Uri.parse(after).port, Uri.parse(before).port);
    await relay.close();
  });
}

void _tests(bool native) {
  late HttpServer upstream;
  late StreamRelay relay;
  final data = Uint8List.fromList(List.generate(1000, (i) => i % 251));
  final ranges = <String>[];
  var fail403 = false;
  var cutOnce = 0;

  setUp(() async {
    ranges.clear();
    fail403 = false;
    cutOnce = 0;
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      final range = request.uri.queryParameters['range']!;
      ranges.add(range);
      if (fail403) {
        request.response.statusCode = 403;
        await request.response.close();
        return;
      }
      final [from, to] = range.split('-').map(int.parse).toList();
      // As googlevideo labels media; the relay refuses text pages.
      request.response.headers.contentType = ContentType('video', 'mp4');
      if (cutOnce > 0) {
        // Promises the whole piece, then drops the connection partway.
        final cut = cutOnce;
        cutOnce = 0;
        request.response.contentLength = to - from + 1;
        final socket = await request.response.detachSocket();
        socket.add(data.sublist(from, from + cut));
        await socket.flush();
        socket.destroy();
        return;
      }
      request.response.add(data.sublist(from, to + 1));
      await request.response.close();
    });
    relay =
        native ? NativeRelay(NativeCore.instance!, chunkSize: 300) : ChunkedRelay(chunkSize: 300);
    await relay.start();
  });

  tearDown(() async {
    await relay.close();
    await upstream.close(force: true);
  });

  Future<(int, List<int>, HttpHeaders)> get(String url, {String? range}) async {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    final bytes = await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    client.close();
    return (response.statusCode, bytes, response.headers);
  }

  String source() =>
      'http://127.0.0.1:${upstream.port}/videoplayback?itag=137&clen=${data.length}&mime=video%2Fmp4&sig=a%2Bb';

  test('serves a whole stream in small upstream pieces', () async {
    final address = relay.register(source())!;
    final (status, bytes, headers) = await get(address);
    expect(status, 200);
    expect(bytes, data);
    expect(headers.contentType?.mimeType, 'video/mp4');
    expect(ranges, ['0-299', '300-599', '600-899', '900-999']);
  });

  test('answers range requests for seeking', () async {
    final address = relay.register(source())!;
    final (status, bytes, headers) = await get(address, range: 'bytes=550-');
    expect(status, 206);
    expect(headers.value(HttpHeaders.contentRangeHeader), 'bytes 550-999/1000');
    expect(bytes, data.sublist(550));
    expect(ranges, ['550-849', '850-999']);
    final (tail, end, _) = await get(address, range: 'bytes=-10');
    expect(tail, 206);
    expect(end, data.sublist(990));
    final (beyond, _, _) = await get(address, range: 'bytes=5000-');
    expect(beyond, 416);
  });

  test('serves only registered addresses and needs a known size', () async {
    expect(relay.register('http://127.0.0.1:1/videoplayback?itag=1'), isNull);
    final address = relay.register(source())!;
    final (status, _, _) = await get('$address-other');
    expect(status, 404);
  });

  test('stops at an expired address instead of retrying', () async {
    fail403 = true;
    final address = relay.register(source())!;
    var received = 0;
    try {
      received = (await get(address)).$2.length;
    } catch (_) {
      // The relay drops the connection mid-stream.
    }
    expect(received, lessThan(data.length));
    expect(ranges, ['0-299']);
  });

  test('continues a reply YouTube cuts short from the next missing byte', () async {
    cutOnce = 120;
    final address = relay.register(source())!;
    final (status, bytes, _) = await get(address);
    expect(status, 200);
    expect(bytes, data);
    expect(ranges, ['0-299', '120-299', '300-599', '600-899', '900-999']);
  });
}
