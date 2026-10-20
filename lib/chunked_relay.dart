import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'app_log.dart';
import 'l10n/l10n.dart';

/// A loopback HTTP server libmpv reads YouTube streams through. YouTube
/// throttles a request for more than about 10 MB of a stream to a crawl,
/// and libmpv asks for the whole rest of the file at once; the relay
/// answers each libmpv request by fetching the stream in smaller pieces
/// with YouTube's own `range` parameter, as yt-dlp and the YouTube website
/// do. Only addresses the app registered are served, only on 127.0.0.1.
class ChunkedRelay {
  ChunkedRelay({this.chunkSize = 9 << 20, HttpClient? client}) : _client = client ?? HttpClient();

  final int chunkSize;
  final HttpClient _client;
  HttpServer? _server;
  final _targets = <String, _Target>{};
  final _random = Random.secure();

  static const _keep = 16;

  Future<void> start() async {
    if (_server != null) return;
    final server = _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => unawaited(_serve(request)));
  }

  /// A loopback address that serves [url], or null when the relay is not
  /// running or the stream's size is unknown (it is needed for seeking).
  String? register(String url, {int? size, String? userAgent}) {
    final server = _server;
    final uri = Uri.tryParse(url);
    if (server == null || uri == null) return null;
    final length = size ?? int.tryParse(uri.queryParameters['clen'] ?? '');
    if (length == null || length <= 0) return null;
    final token = List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();
    _targets[token] = _Target(uri, length, userAgent, uri.queryParameters['mime']);
    while (_targets.length > _keep) {
      _targets.remove(_targets.keys.first);
    }
    return 'http://127.0.0.1:${server.port}/$token';
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    final target = _targets[request.uri.pathSegments.firstOrNull ?? ''];
    if (target == null || (request.method != 'GET' && request.method != 'HEAD')) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final size = target.size;
    var start = 0;
    var end = size - 1;
    final range = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
    if (range != null) {
      final from = int.tryParse(range[1]!);
      final to = int.tryParse(range[2]!);
      if (from == null && to != null) {
        start = max(0, size - to);
      } else {
        start = from ?? 0;
        if (to != null) end = min(to, size - 1);
      }
      if (start >= size || start > end) {
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        await response.close();
        return;
      }
      response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$size');
    }
    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentLength = end - start + 1;
    if (target.mime != null) response.headers.set(HttpHeaders.contentTypeHeader, target.mime!);
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    try {
      for (var position = start; position <= end; position += chunkSize) {
        final last = min(position + chunkSize - 1, end);
        await _copy(target, position, last, response);
      }
      await response.close();
    } catch (e) {
      // libmpv closing the connection to seek is the common case.
      if (e is! SocketException && e is! HttpException) logInfo('分块转发中断：$e');
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _copy(_Target target, int from, int to, HttpResponse into) async {
    // Appended as text: rebuilding the query could re-encode signed values.
    final uri = Uri.parse('${target.url}&range=$from-$to');
    HttpClientResponse? answer;
    for (var attempt = 0; answer == null; attempt++) {
      try {
        final upstream = await _client.getUrl(uri);
        if (target.userAgent != null) upstream.headers.set(HttpHeaders.userAgentHeader, target.userAgent!);
        final reply = await upstream.close();
        if (reply.statusCode != HttpStatus.ok && reply.statusCode != HttpStatus.partialContent) {
          await reply.drain<void>();
          // A 403 means the address expired; libmpv's own fallback handles it.
          if (reply.statusCode == HttpStatus.forbidden || attempt >= 1) throw HttpException(tr('YouTube 返回 {0}', [reply.statusCode]), uri: uri);
          continue;
        }
        answer = reply;
      } on SocketException {
        if (attempt >= 1) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    // Retried only before any byte was sent, so nothing is sent twice.
    await into.addStream(answer);
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
    _client.close(force: true);
  }
}

class _Target {
  _Target(this.url, this.size, this.userAgent, this.mime);
  final Uri url;
  final int size;
  final String? userAgent;
  final String? mime;
}
