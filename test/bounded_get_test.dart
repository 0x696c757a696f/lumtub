import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/bounded_get.dart';

void main() {
  test('reads a reply within the limit and refuses a longer one', () async {
    final client = MockClient(
        (request) async => http.Response('x' * int.parse(request.url.queryParameters['n']!), 200));
    final (status, body) =
        await getBounded(client, Uri.parse('https://example.org/?n=10'), limit: 10);
    expect((status, body.length), (200, 10));
    expect(getBounded(client, Uri.parse('https://example.org/?n=11'), limit: 10),
        throwsA(isA<HttpException>()));
  });

  test('refuses a long reply that does not say its length', () async {
    final client = MockClient.streaming((request, body) async =>
        http.StreamedResponse(Stream.fromIterable([List.filled(6, 1), List.filled(6, 1)]), 200));
    expect(getBounded(client, Uri.parse('https://example.org/'), limit: 10),
        throwsA(isA<HttpException>()));
  });
}
