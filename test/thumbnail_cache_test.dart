import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
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

  test('covers known only by address get a file of their own', () {
    final dir = Directory('cache');
    const url = 'https://i.ytimg.com/vi/x/hqdefault.jpg?sqp=abc';
    expect(CachedThumbnail.fileForUrl(dir, url).path, CachedThumbnail.fileForUrl(dir, url).path);
    expect(CachedThumbnail.fileForUrl(dir, url).path, isNot(CachedThumbnail.fileForUrl(dir, '$url&rs=1').path));
    expect(CachedThumbnail.fileForUrl(dir, url).uri.pathSegments.last, matches(RegExp(r'^cover_[0-9a-f]{20}\.jpg$')));
    expect(const CachedThumbnail(url, null), const CachedThumbnail(url, null));
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

  test('a queued download for a card that left the screen is dropped', () async {
    for (var i = 0; i < 6; i++) {
      await CachedThumbnail.slot(() => true);
    }
    final left = CachedThumbnail.slot(() => false);
    final shown = CachedThumbnail.slot(() => true);
    final dropped = expectLater(left, throwsA(isA<ThumbnailDropped>()));
    CachedThumbnail.free();
    await dropped;
    await shown;
    for (var i = 0; i < 6; i++) {
      CachedThumbnail.free();
    }
  });

  test('a picture no card shows any more is not downloaded', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (var i = 0; i < 6; i++) {
      await CachedThumbnail.slot(() => true);
    }
    final provider = CachedThumbnail('https://i.ytimg.com/vi/gone/hqdefault.jpg', File('${Directory.systemTemp.path}/lumtub-missing/gone.jpg'));
    final stream = provider.resolve(ImageConfiguration.empty);
    final card = ImageStreamListener((image, sync) {}, onError: (error, stack) {});
    stream.addListener(card);
    final failed = Completer<Object>();
    stream.completer!.addEphemeralErrorListener((error, _) => failed.complete(error));
    await pumpEventQueue();
    stream.removeListener(card);
    CachedThumbnail.free();
    expect(await failed.future, isA<ThumbnailDropped>());
    for (var i = 0; i < 5; i++) {
      CachedThumbnail.free();
    }
  });
}
