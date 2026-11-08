import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/video_list_loader.dart';
import 'package:lumtub/video_repository.dart';
import 'package:lumtub/models.dart';

String _video(int i) => jsonEncode({'id': 'v${i.toString().padLeft(10, '0')}', 'title': '$i', 'channel': ''});

/// A source that records how many lines were read from it.
class _Source {
  _Source(this.lines);
  final List<String> lines;
  int read = 0;
  int opened = 0;
  int cancelled = 0;

  Stream<String> open() async* {
    opened++;
    var finished = false;
    try {
      for (final line in lines) {
        read++;
        yield line;
      }
      finished = true;
    } finally {
      if (!finished) cancelled++;
    }
  }
}

void main() {
  test('pages continue one listing instead of starting over', () async {
    final source = _Source([for (var i = 0; i < 5; i++) _video(i)]);
    final loader = VideoListLoader(() => Listing(source.open), pageSize: 2);
    addTearDown(loader.dispose);

    loader.loadMore();
    await pumpEventQueue();
    expect(loader.items, hasLength(2));
    expect(source.read, lessThanOrEqualTo(3), reason: '读取在一页满后暂停');
    loader.loadMore();
    await pumpEventQueue();
    loader.loadMore();
    await pumpEventQueue();
    expect(loader.items.map((v) => v.title), ['0', '1', '2', '3', '4']);
    expect(source.opened, 1);
    expect(source.read, 5);
    expect(loader.hasMore, isFalse);
  });

  test('publishes a page once instead of rebuilding for every result', () async {
    final source = _Source([for (var i = 0; i < 20; i++) _video(i)]);
    final loader = VideoListLoader(() => Listing(source.open), pageSize: 20);
    addTearDown(loader.dispose);
    var notifications = 0;
    loader.addListener(() => notifications++);

    loader.loadMore();
    await pumpEventQueue();

    expect(loader.items, hasLength(20));
    // One notification starts loading and one publishes the finished page.
    expect(notifications, 2);
  });

  test('after an error only an explicit retry loads again', () async {
    var calls = 0;
    final loader = VideoListLoader(() {
      calls++;
      return Listing(() => calls == 1 ? Stream.error(StateError('offline')) : Stream.value(_video(1)));
    });
    addTearDown(loader.dispose);

    loader.loadMore();
    await pumpEventQueue();
    expect(loader.error, contains('offline'));
    loader.loadMore();
    await pumpEventQueue();
    expect(calls, 1);
    loader.loadMore(retry: true);
    await pumpEventQueue();
    expect(calls, 2);
    expect(loader.error, isNull);
    expect(loader.items, hasLength(1));
  });

  test('an idle listing closes its source and later resumes where it was', () async {
    final source = _Source([for (var i = 0; i < 5; i++) _video(i)]);
    final listing = Listing(source.open, idleTimeout: const Duration(milliseconds: 50));
    expect((await listing.next(2).toList()).map((v) => (v as dynamic).title), ['0', '1']);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(source.cancelled, 1);
    expect((await listing.next(2).toList()).map((v) => (v as dynamic).title), ['2', '3']);
    expect(source.opened, 2);
    listing.close();
  });

  test('stops at the limit and skips filtered videos', () async {
    final loader = VideoListLoader(
      () => Listing(() => Stream.fromIterable([for (var i = 0; i < 6; i++) _video(i)])),
      pageSize: 6,
      limit: 3,
      where: (item) => item.title != '0',
    );
    addTearDown(loader.dispose);
    loader.loadMore();
    await pumpEventQueue();
    expect(loader.items.map((v) => v.title), ['1', '2', '3']);
    expect(loader.hasMore, isFalse);
  });

  test('channels count for nothing towards a strict filter, and a source failing part way is not an empty list', () async {
    String channel(int i) => jsonEncode({'_type': 'url', 'ie_key': 'YoutubeTab', 'id': 'UC${i.toString().padLeft(22, 'x')}', 'title': 'c$i'});
    final loader = VideoListLoader(
      () => Listing(() async* {
        for (var i = 0; i < 6; i++) {
          yield channel(i);
        }
        yield _video(1);
        yield _video(2);
        throw StateError('connection reset');
      }),
      pageSize: 4,
      fill: 2,
      where: (item) => item.title != '1',
    );
    addTearDown(loader.dispose);
    loader.loadMore();
    await pumpEventQueue();
    expect(loader.items.map((v) => v.title), ['2'], reason: 'pages of channels alone are read past');
    final strict = VideoListLoader(
      () => Listing(() async* {
        yield _video(1);
        throw StateError('connection reset');
      }),
      where: (item) => false,
      fill: 8,
    );
    addTearDown(strict.dispose);
    strict.loadMore();
    await pumpEventQueue();
    expect(strict.items, isEmpty);
    expect(strict.error, isNotNull, reason: 'the failure shows, with a way to retry');
  });

  test('keeps channels apart from videos', () async {
    final channel = jsonEncode({
      '_type': 'url', 'ie_key': 'YoutubeTab', 'id': 'UCsXVk37bltHxD1rDPwtNM8Q', 'title': 'Kurzgesagt',
      'channel_follower_count': 24000000, 'uploader_id': '@kurzgesagt',
      'thumbnails': [{'url': '//yt3.ggpht.com/a=s88'}, {'url': '//yt3.ggpht.com/a=s176'}],
    });
    final loader = VideoListLoader(() => Listing(() => Stream.fromIterable([channel, _video(1), 'not json'])));
    addTearDown(loader.dispose);
    loader.loadMore();
    await pumpEventQueue();
    expect(loader.items, hasLength(1));
    final result = loader.channels.single;
    expect(result.ref.name, 'Kurzgesagt');
    expect(result.subscribers, '24M subscribers');
    expect(result.handle, '@kurzgesagt');
    expect(result.avatar, 'https://yt3.ggpht.com/a=s176');
  });

  test('keeps playlists apart and reads live status', () async {
    final playlist = jsonEncode({
      '_type': 'url', 'ie_key': 'YoutubeTab', 'id': 'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI',
      'url': 'https://www.youtube.com/playlist?list=PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI', 'title': 'Hits', 'playlist_count': 42,
    });
    final live = jsonEncode({'id': 'jfKfPfyJRdk', 'title': 'lofi radio', 'live_status': 'is_live'});
    final loader = VideoListLoader(() => Listing(() => Stream.fromIterable([playlist, live])));
    addTearDown(loader.dispose);
    loader.loadMore();
    await pumpEventQueue();
    expect(loader.playlists.single.title, 'Hits');
    expect(loader.playlists.single.count, 42);
    expect(loader.items.single.isLive, isTrue);
  });
  test('reads playlists that report extractor_key instead of ie_key', () {
    final entry = parseListingEntry(jsonEncode({
      '_type': 'url', 'extractor_key': 'YoutubeTab', 'id': 'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI',
      'url': 'https://www.youtube.com/playlist?list=PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI', 'title': 'Hits',
    }));
    expect(entry, isA<PlaylistResult>());
  });
  test('a title filter reads past pages with no match', () async {
    String titled(int i, String title) => jsonEncode({'id': 'video$i'.padRight(11, '0'), 'title': title, 'channel': ''});
    final source = _Source([for (var i = 0; i < 30; i++) titled(i, i == 25 ? 'Big Dog' : 'cat $i')]);
    final loader = VideoListLoader(() => Listing(source.open), pageSize: 2, matches: (title) => title.toLowerCase().contains('dog'));
    addTearDown(loader.dispose);
    loader.loadMore();
    while (loader.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(loader.items.map((v) => v.title), ['Big Dog']);
    expect(loader.hasMore, isTrue);
  });

  test('a playlists tab follows its shelf links', () {
    expect(VideoRepository.shelfUrl(jsonEncode({'url': 'https://www.youtube.com/@x/playlists?view=50&shelf_id=2'})), 'https://www.youtube.com/@x/playlists?view=50&shelf_id=2');
    expect(VideoRepository.shelfUrl(jsonEncode({'url': 'https://www.youtube.com/playlist?list=PL123', 'ie_key': 'YoutubeTab'})), isNull);
    expect(VideoRepository.shelfUrl(jsonEncode({'url': 'https://www.youtube.com/@x/playlists'})), isNull);
    expect(VideoRepository.shelfUrl('not json'), isNull);
  });

  test('ranks every candidate gathered, not each page on its own, and fills strict filters', () async {
    final source = _Source([for (var i = 0; i < 12; i++) _video(i)]);
    final loader = VideoListLoader(
      () => Listing(source.open),
      pageSize: 4,
      where: (item) => int.parse(item.title).isEven,
      fill: 3,
      rank: (item) => double.parse(item.title),
    );
    addTearDown(loader.dispose);
    loader.loadMore();
    await pumpEventQueue();
    // Pages are read ahead until six candidates wait; the best four show.
    expect(loader.items.map((v) => v.title), ['10', '8', '6', '4']);
    expect(loader.loading, isFalse);
    expect(loader.hasMore, isTrue);
    loader.loadMore();
    await pumpEventQueue();
    expect(loader.items.map((v) => v.title), ['10', '8', '6', '4', '2', '0']);
    expect(loader.hasMore, isFalse);
    expect(source.opened, 1);
  });

  test('a slow strict filter shows what it found while it reads on', () async {
    final lines = StreamController<String>();
    final loader = VideoListLoader(
      () => Listing(() => lines.stream),
      pageSize: 2,
      where: (item) => int.parse(item.title) % 3 == 0,
      fill: 3,
      rank: (item) => double.parse(item.title),
      readAhead: false,
    );
    addTearDown(loader.dispose);
    loader.loadMore();
    for (var i = 0; i < 4; i++) {
      lines.add(_video(i));
    }
    await pumpEventQueue();
    // Each find shows as its page ends, while the next one is read.
    expect(loader.items.map((v) => v.title), ['0', '3']);
    expect(loader.loading, isTrue);
    for (var i = 4; i < 7; i++) {
      lines.add(_video(i));
    }
    await lines.close();
    await pumpEventQueue();
    expect(loader.items.map((v) => v.title), ['0', '3', '6']);
    expect(loader.loading, isFalse);
  });

  test('a candidate left out of one page still beats a worse one found later', () async {
    final scores = [5, 9, 1, 7, 2, 8, 0, 3, 4, 6, 1, 1, 1, 1, 1, 1];
    final source = _Source([for (var i = 0; i < scores.length; i++) _video(scores[i] * 100 + i)]);
    final loader = VideoListLoader(() => Listing(source.open), pageSize: 2, rank: (item) => (int.parse(item.title) ~/ 100).toDouble());
    addTearDown(loader.dispose);
    final shown = <int>[];
    while (loader.hasMore) {
      loader.loadMore();
      await pumpEventQueue();
      if (shown.length == loader.items.length) break;
      shown
        ..clear()
        ..addAll(loader.items.map((v) => int.parse(v.title) ~/ 100));
    }
    expect(shown, hasLength(scores.length));
    // Each page is the best of what was gathered by then, so nothing shows
    // after a lower score it was gathered together with.
    expect(shown.take(4), [9, 7, 8, 5]);
  });

  test('a failed list retries on its own, at once when another list loads', () async {
    final saved = VideoListLoader.retryDelays;
    addTearDown(() => VideoListLoader.retryDelays = saved);
    VideoListLoader.retryDelays = const [Duration(milliseconds: 20), Duration(hours: 1)];
    var fail = true;
    Stream<String> flaky() async* {
      if (fail) throw StateError('network down');
      yield _video(1);
    }

    final loader = VideoListLoader(() => Listing(flaky));
    addTearDown(loader.dispose);
    loader.loadMore();
    await pumpEventQueue();
    expect(loader.error, contains('network down'));
    fail = false;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await pumpEventQueue();
    expect(loader.error, isNull);
    expect(loader.items, hasLength(1));

    // The second retry waits an hour, unless another list gets through.
    fail = true;
    final other = VideoListLoader(() => Listing(flaky));
    addTearDown(other.dispose);
    other.loadMore();
    await pumpEventQueue();
    expect(other.error, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await pumpEventQueue();
    expect(other.error, isNotNull);
    fail = false;
    final third = VideoListLoader(() => Listing(flaky));
    addTearDown(third.dispose);
    third.loadMore();
    await pumpEventQueue();
    expect(other.error, isNull);
    expect(other.items, hasLength(1));

    // Being rate limited is not retried.
    final limited = VideoListLoader(() => Listing(() => Stream.error(StateError('HTTP Error 429: Too Many Requests'))));
    addTearDown(limited.dispose);
    limited.loadMore();
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(limited.error, contains('Too many requests'));
  });

  test('tries again when the first answer is empty', () async {
    VideoListLoader.emptyRetryDelays = const [Duration(milliseconds: 10), Duration(milliseconds: 10)];
    addTearDown(() => VideoListLoader.emptyRetryDelays = const [Duration(seconds: 3), Duration(seconds: 10)]);
    var opened = 0;
    final loader = VideoListLoader(() {
      opened++;
      final lines = opened < 3 ? const <String>[] : [jsonEncode(const VideoItem(id: 'abcdefghijk', title: 't', channel: 'c', url: 'u').toJson())];
      return Listing(() => Stream.fromIterable(lines));
    }, name: 'test');
    loader.loadMore();
    while (loader.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(opened, 3);
    expect(loader.items.map((v) => v.id), ['abcdefghijk']);
  });
}
