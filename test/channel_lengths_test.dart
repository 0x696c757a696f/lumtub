import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/video_list_loader.dart';
import 'package:lumtub/channel_lengths.dart';
import 'package:lumtub/channel_sort.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/search_options.dart';
import 'package:lumtub/video_repository.dart';

String _video(int i, int? seconds) => jsonEncode({'id': 'v${i.toString().padLeft(10, '0')}', 'title': '$i', 'channel': '', if (seconds != null) 'duration': seconds});

/// A channel tab, newest first, that counts what was read from it.
class _Tab {
  _Tab(this.lengths);
  List<int?> lengths;
  int read = 0;

  Stream<String> open() async* {
    for (var i = lengths.length - 1; i >= 0; i--) {
      read++;
      yield _video(i, lengths[i]);
    }
  }
}

const _channel = ChannelRef('UCabcdefghijklmnopqrstuv', 'c');

Future<List<String>> _all(VideoListLoader loader) async {
  await pumpEventQueue(times: 50);
  while (loader.hasMore && loader.error == null) {
    loader.loadMore();
    await pumpEventQueue(times: 50);
  }
  return [for (final v in loader.items) v.title];
}

void main() {
  // 0..7 oldest to newest; the tab lists 7 first.
  const lengths = [300, 30, null, 4000, 90, 600, 5, 1200];

  test('without the core the tab is read whole and ordered here, unknown lengths last', () async {
    for (final (sort, want) in [
      (ChannelSort.longest, ['3', '7', '5', '0', '4', '1', '6', '2']),
      (ChannelSort.shortest, ['6', '1', '4', '0', '5', '7', '3', '2']),
    ]) {
      final tab = _Tab([...lengths]);
      final lengthsOf = ChannelLengths(newest: () => Listing(tab.open), channel: _channel, tab: ChannelTab.videos, sort: sort, core: (_) async => null);
      final loader = VideoListLoader(lengthsOf.listing, pageSize: 3);
      addTearDown(loader.dispose);
      expect(await _all(loader), want);
      expect(tab.read, lengths.length);
      expect(lengthsOf.read.value, lengths.length);
    }
    expect(ChannelSort.longest.fits(ChannelTab.shorts), isFalse);
    expect(ChannelSort.oldest.fits(ChannelTab.shorts), isTrue);
  });

  test('a length filter keeps only videos of that length', () {
    expect([for (final s in [null, 0, 239, 240, 1200, 1201]) SearchDuration.short.admits(s)], [false, true, true, false, false, false]);
    expect([for (final s in [null, 239, 240, 1200, 1201]) SearchDuration.medium.admits(s)], [false, false, true, true, false]);
    expect([for (final s in [null, 1200, 1201]) SearchDuration.long.admits(s)], [false, false, true]);
    expect(SearchDuration.any.admits(null), isTrue);
  });

  group('with the core', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('lumtub-lengths'));
    tearDown(() => dir.deleteSync(recursive: true));

    // Runs the core on this isolate: the test has it from LUMTUB_CORE_DLL.
    Future<Object?> core(Map<String, Object?> ask) async {
      final answer = NativeCore.instance?.channelLengths(jsonEncode(ask));
      return answer == null ? null : jsonDecode(answer);
    }

    test('the second time only the new uploads are read', () async {
      var now = DateTime(2026, 11, 27);
      final tab = _Tab([...lengths]);
      Future<List<String>> once(ChannelSort sort) async {
        final lengthsOf = ChannelLengths(newest: () => Listing(tab.open), channel: _channel, tab: ChannelTab.videos, sort: sort, folder: dir.path, core: core, clock: () => now);
        final loader = VideoListLoader(lengthsOf.listing, pageSize: 3);
        addTearDown(loader.dispose);
        return _all(loader);
      }

      expect(await once(ChannelSort.longest), ['3', '7', '5', '0', '4', '1', '6', '2']);
      expect(tab.read, 8);
      expect(File('${dir.path}/videos-${_channel.id}.json').existsSync(), isTrue);

      // Two uploads later: they and the three known ones after them are read.
      tab.lengths = [...lengths, 7000, 1];
      tab.read = 0;
      now = now.add(const Duration(days: 1));
      expect(await once(ChannelSort.shortest), ['9', '6', '1', '4', '0', '5', '7', '3', '8', '2']);
      expect(tab.read, 2 + ChannelLengths.knownRun);

      // A week on, the tab is read whole again.
      tab.read = 0;
      now = now.add(ChannelLengths.fresh);
      await once(ChannelSort.longest);
      expect(tab.read, 10);
    });

    test('the app runs the core on an isolate of its own', () async {
      final tab = _Tab([...lengths]);
      final lengthsOf = ChannelLengths(newest: () => Listing(tab.open), channel: _channel, tab: ChannelTab.live, sort: ChannelSort.longest, folder: dir.path);
      final loader = VideoListLoader(lengthsOf.listing, pageSize: 20);
      addTearDown(loader.dispose);
      loader.loadMore();
      for (var i = 0; i < 100 && loader.loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect([for (final v in loader.items) v.title], ['3', '7', '5', '0', '4', '1', '6', '2']);
      expect(File('${dir.path}/live-${_channel.id}.json').existsSync(), isTrue);
    });

    test('a broken listing with nothing kept shows the failure', () async {
      final lengthsOf = ChannelLengths(
        newest: () => Listing(() => Stream.error(Exception('offline'))),
        channel: _channel,
        tab: ChannelTab.videos,
        sort: ChannelSort.longest,
        folder: dir.path,
        core: core,
      );
      final loader = VideoListLoader(lengthsOf.listing, pageSize: 3);
      addTearDown(loader.dispose);
      loader.loadMore();
      await pumpEventQueue(times: 50);
      expect(loader.error, isNotNull);
      expect(loader.items, isEmpty);
    });
  }, skip: NativeCore.instance == null ? 'needs lumtub_core (LUMTUB_CORE_DLL)' : null);
}
