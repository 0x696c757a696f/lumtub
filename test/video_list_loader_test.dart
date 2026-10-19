import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/app/video_list_loader.dart';
import 'package:ytplus/models.dart';

VideoItem _video(int i) => VideoItem(id: 'video$i'.padRight(11, '0'), title: '$i', channel: '', url: '');

void main() {
  test('pages until a short page arrives', () async {
    final starts = <int>[];
    final loader = VideoListLoader((start) {
      starts.add(start);
      final count = start == 1 ? 2 : 1;
      return Stream.fromIterable([for (var i = start; i < start + count; i++) _video(i)]);
    }, pageSize: 2);
    addTearDown(loader.dispose);

    loader.loadMore();
    await pumpEventQueue();
    expect(loader.items, hasLength(2));
    expect(loader.hasMore, isTrue);
    loader.loadMore();
    await pumpEventQueue();
    expect(starts, [1, 3]);
    expect(loader.items, hasLength(3));
    expect(loader.hasMore, isFalse);
  });

  test('after an error only an explicit retry loads again', () async {
    var calls = 0;
    final loader = VideoListLoader((start) {
      calls++;
      return calls == 1 ? Stream.error(StateError('offline')) : Stream.value(_video(1));
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

  test('stops at the limit', () async {
    final loader = VideoListLoader((start) => Stream.fromIterable([for (var i = 0; i < 5; i++) _video(i)]), pageSize: 5, limit: 3);
    addTearDown(loader.dispose);
    loader.loadMore();
    await pumpEventQueue();
    expect(loader.items, hasLength(3));
    expect(loader.hasMore, isFalse);
  });
}
