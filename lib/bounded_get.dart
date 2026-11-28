import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// [url]'s status and body, at most [limit] bytes: a server that is broken
/// or hostile cannot fill the memory with a longer one, which is not read.
Future<(int, Uint8List)> getBounded(http.Client client, Uri url,
    {required int limit, Map<String, String>? headers}) async {
  final request = http.Request('GET', url);
  if (headers != null) request.headers.addAll(headers);
  final response = await client.send(request);
  final subscription = StreamIterator(response.stream);
  try {
    if ((response.contentLength ?? 0) > limit) throw const HttpException('The reply is too long');
    final bytes = BytesBuilder(copy: false);
    while (await subscription.moveNext()) {
      final chunk = subscription.current;
      if (bytes.length + chunk.length > limit) throw const HttpException('The reply is too long');
      bytes.add(chunk);
    }
    return (response.statusCode, bytes.takeBytes());
  } finally {
    await subscription.cancel();
  }
}
