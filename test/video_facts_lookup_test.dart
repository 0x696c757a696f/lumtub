import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_preferences.dart';
import 'package:lumtub/language_guess.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/video_facts_lookup.dart';

void main() {
  final lookup = VideoFactsLookup.instance;
  tearDown(lookup.reset);

  VideoItem feedItem(String id) => VideoItem(id: id, title: 'T', channel: 'C', url: 'https://www.youtube.com/watch?v=$id', published: DateTime.utc(2026, 11, 1));

  test('reads length, views and day from a /player answer', () {
    final facts = VideoFacts.ofPlayer('{"videoDetails":{"videoId":"x","lengthSeconds":"754","viewCount":"12345"},"microformat":{"playerMicroformatRenderer":{"publishDate":"2026-10-30T05:00:00-07:00"}}}', DateTime.utc(2026, 11, 11))!;
    expect(facts.length, 754);
    expect(facts.views, 12345);
    expect(facts.published, DateTime.parse('2026-10-30T05:00:00-07:00'));
    expect(VideoFacts.ofPlayer('{"videoDetails":{"lengthSeconds":"0","viewCount":"9"}}', DateTime.now())!.length, isNull);
    expect(VideoFacts.ofPlayer('{"playabilityStatus":{"status":"ERROR"}}', DateTime.now()), isNull);
    expect(VideoFactsLookup.playerWhy('{"responseContext":{},"playabilityStatus":{"status":"LOGIN_REQUIRED","reason":"Sign in to confirm you’re not a bot"}}'), 'LOGIN_REQUIRED: Sign in to confirm you’re not a bot');
    expect(VideoFactsLookup.playerWhy('HTTP 403'), 'HTTP 403');
  });

  test('a live the feed did not mark becomes one, and a live just ended takes its length from its streams', () async {
    final live = VideoFacts.ofPlayer('{"streamingData":{"adaptiveFormats":[{"itag":136}]},"videoDetails":{"lengthSeconds":"0","isLive":true,"viewCount":"40"}}', DateTime.now())!;
    expect((live.length, live.liveStatus), (null, 'is_live'));
    expect(VideoFacts.ofPlayer('{"videoDetails":{"isUpcoming":true}}', DateTime.now())!.liveStatus, 'is_upcoming');
    final ended = VideoFacts.ofPlayer('{"streamingData":{"adaptiveFormats":[{"approxDurationMs":"3605120"},{"approxDurationMs":"3605201"}]},"videoDetails":{"lengthSeconds":"0","isLiveContent":true,"viewCount":"9"}}', DateTime.now())!;
    expect((ended.length, ended.liveStatus), (3605, null));
    expect(VideoFacts.fromJson(live.toJson())!.liveStatus, 'is_live');

    var time = DateTime.utc(2026, 11, 12, 10);
    var answer = VideoFacts(views: 40, liveStatus: 'is_live', asked: time);
    lookup.now = () => time;
    addTearDown(() => lookup.now = DateTime.now);
    final asked = <String>[];
    lookup.use((id) async {
      asked.add(id);
      return answer;
    }, null);
    final item = feedItem('ccccccccccc');
    lookup.of(item);
    await Future<void>.delayed(Duration.zero);
    expect(lookup.of(item).isLive, isTrue);
    expect(asked, hasLength(1));
    answer = VideoFacts(length: 3605, views: 50, asked: time);
    time = time.add(const Duration(minutes: 30));
    lookup.of(item);
    await Future<void>.delayed(Duration.zero);
    final done = lookup.of(item);
    expect(asked, hasLength(2));
    expect((done.durationLabel, done.isLive), ('1:00:05', false));
  });

  test('fills in what a card lacks once, keeps it on disk and never overrides the listing', () async {
    final dir = await Directory.systemTemp.createTemp('facts');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/video_facts.json');
    final asked = <String>[];
    lookup.use((id) async {
      asked.add(id);
      return VideoFacts(length: 125, views: 99, published: DateTime.utc(2020), asked: DateTime.now());
    }, file);
    final item = feedItem('aaaaaaaaaaa');
    expect(lookup.needs(item), isTrue);
    expect(lookup.of(item).duration, isNull);
    final changed = Completer<void>();
    lookup.addListener(() => changed.isCompleted ? null : changed.complete());
    await changed.future;
    final filled = lookup.of(item);
    expect(filled.durationLabel, '2:05');
    expect(filled.viewCount, 99);
    expect(filled.published, DateTime.utc(2026, 11, 1));
    expect(asked, ['aaaaaaaaaaa']);

    final live = VideoItem(id: 'bbbbbbbbbbb', title: 'T', channel: 'C', url: '', liveStatus: 'is_live');
    expect(lookup.needs(live), isFalse);
    expect(identical(lookup.of(live), live), isTrue);

    await lookup.write();
    lookup.reset();
    lookup.use((id) async => null, file);
    expect(lookup.of(item).duration, 125);
  });

  test('Simplified and Traditional Chinese read as one only when asked', () {
    const traditional = '這個影片真的很好看，謝謝分享';
    expect(readsAs(traditional, 'zh-CN', chineseAsOne: false), isFalse);
    expect(readsAs(traditional, 'zh-CN', chineseAsOne: true), isTrue);
    expect(readsAs('这个视频真的很好看，谢谢分享', 'zh-TW', chineseAsOne: true), isTrue);
    expect(readsAs('これはとても良い動画です', 'zh-CN', chineseAsOne: true), isFalse);
  });

  test('languages never translated are kept, unknown codes dropped', () {
    final read = AppPreferences.fromJson(const AppPreferences(neverTranslate: ['ja', 'de']).toJson()..['neverTranslate'] = ['ja', 'de', 'xx']);
    expect(read.neverTranslate, ['ja', 'de']);
    expect(AppPreferences.fromJson(const <String, dynamic>{}).neverTranslate, isEmpty);
  });
}
