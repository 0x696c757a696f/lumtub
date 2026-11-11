import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/thumbnail_cache.dart';

void main() {
  test('cache files are named after the video id', () {
    final file = CachedThumbnail.fileFor(Directory('cache'), 'dQw4w9WgXcQ');
    expect(file.path, endsWith('dQw4w9WgXcQ.jpg'));
  });

  test('providers for the same video share an image cache key', () {
    final a = CachedThumbnail('https://i.ytimg.com/vi/x/hqdefault.jpg', File('a.jpg'));
    final b = CachedThumbnail('https://i.ytimg.com/vi/x/hqdefault.jpg', File('a.jpg'));
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('asks for the WebP copy first, then the JPEG, then hqdefault', () {
    expect(CachedThumbnail.candidates('https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg'), [
      'https://i.ytimg.com/vi_webp/dQw4w9WgXcQ/mqdefault.webp',
      'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
    ]);
    expect(CachedThumbnail.candidates('https://i.ytimg.com/vi/a-b_c/maxresdefault.jpg'), [
      'https://i.ytimg.com/vi_webp/a-b_c/maxresdefault.webp',
      'https://i.ytimg.com/vi/a-b_c/maxresdefault.jpg',
      'https://i.ytimg.com/vi_webp/a-b_c/hqdefault.webp',
      'https://i.ytimg.com/vi/a-b_c/hqdefault.jpg',
    ]);
    expect(CachedThumbnail.candidates('https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID=x&time=1'), ['https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID=x&time=1']);
  });

  test('a thumbnail larger than the limit is refused', () async {
    final big = MockClient.streaming((request, _) async => http.StreamedResponse(Stream.fromIterable([for (var i = 0; i < 80; i++) List.filled(64 << 10, 1)]), 200));
    expect((await CachedThumbnail.fetch(big, Uri.parse('https://i.ytimg.com/x'))).$1, 413);
    final small = MockClient((request) async => http.Response.bytes([1, 2, 3], 200));
    final (status, body) = await CachedThumbnail.fetch(small, Uri.parse('https://i.ytimg.com/x'));
    expect(status, 200);
    expect(body, [1, 2, 3]);
  });
}
