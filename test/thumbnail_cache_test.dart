import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
