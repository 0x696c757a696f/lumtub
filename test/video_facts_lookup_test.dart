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
