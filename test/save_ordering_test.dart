import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/channel_feed.dart';
import 'package:lumtub/library_store.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/search_suggestions.dart';
import 'package:lumtub/watch_time.dart';

void main() {
  const channel = ChannelRef('UCuAXFkgsw1L7xaCfnd5JJOw', 'Rick Astley');

  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('lumtub_order'));
  tearDown(() => dir.delete(recursive: true));

  test('watch time stays dirty after a failed save and saves again', () async {
    final blocker = File('${dir.path}/blocked')..writeAsStringSync('x');
    final watch = WatchTime(File('${blocker.path}/watch_time.json'));
    watch.add('c', 'C', 5);
    await watch.save();
    blocker.deleteSync();
    await watch.save();
    expect(File('${dir.path}/blocked/watch_time.json').readAsStringSync(), contains('"c":5'));
  });

  test('watch time added during a save is saved afterwards', () async {
    final file = File('${dir.path}/watch_time.json');
    final watch = WatchTime(file);
    watch.add('c', 'C', 5);
    final first = watch.save();
    watch.add('c', 'C', 7);
    await first;
    await watch.save();
    expect(file.readAsStringSync(), contains('"c":12'));
  });

  test('overlapping library saves leave the latest state', () async {
    final file = File('${dir.path}/library.json');
    final library = LibraryStore(file);
    final first = library.save();
    library.toggleFollow(channel);
    final second = library.save();
    await Future.wait([first, second]);
    expect(file.readAsStringSync(), contains(channel.id));
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('a pending search add cannot come back after clear', () async {
    final file = File('${dir.path}/history.json')..writeAsStringSync('["old"]');
    final history = SearchHistory(file);
    final add = history.add('new');
    final clear = history.clear();
    await Future.wait([add, clear]);
    expect(await history.items(), isEmpty);
    expect(file.readAsStringSync(), '[]');
  });

  test('concurrent feed requests share one network call', () async {
    var calls = 0;
    final gate = Completer<void>();
    final feed = ChannelFeed(MockClient((request) async {
      calls++;
      await gate.future;
      return http.Response('<feed></feed>', 200);
    }));
    final first = feed.latest(channel);
    final second = feed.latest(channel, fresh: true);
    gate.complete();
    await Future.wait([first, second]);
    expect(calls, 1);
    await feed.latest(channel, fresh: true);
    expect(calls, 2);
  });

  test('a failed feed request is not kept in flight', () async {
    var calls = 0;
    final feed = ChannelFeed(MockClient((request) async {
      calls++;
      return http.Response('', calls == 1 ? 500 : 200);
    }));
    await expectLater(feed.latest(channel), throwsStateError);
    expect(await feed.latest(channel), isEmpty);
    expect(calls, 2);
  });
}
