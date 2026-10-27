import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/app/comments_loader.dart';
import 'package:lumtub/app_preferences.dart';
import 'package:lumtub/channel_playback.dart';
import 'package:lumtub/library_store.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/translation_services.dart';
import 'package:lumtub/ui/pages/video_pages.dart';
import 'package:lumtub/ui/pages/watch_stats_page.dart';
import 'package:lumtub/ui/playlist_length.dart';
import 'package:lumtub/ui/video_card.dart';
import 'package:lumtub/video_summary.dart';
import 'package:lumtub/watch_time.dart';
import 'package:lumtub/youtube_comments.dart';

http.Response _reply(String content) => http.Response.bytes(
      utf8.encode(jsonEncode({'choices': [{'message': {'content': content}}]})),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

String _vtt(int lines) => 'WEBVTT\n\n${[
      for (var i = 0; i < lines; i++) '00:${(i * 5 ~/ 60).toString().padLeft(2, '0')}:${(i * 5 % 60).toString().padLeft(2, '0')}.000 --> 00:${(i * 5 ~/ 60).toString().padLeft(2, '0')}:${(i * 5 % 60 + 4).toString().padLeft(2, '0')}.500\nline number $i.\n',
    ].join('\n')}';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('lumtub_plugins'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('按频道记住倍速和音量', () {
    test('keys by channel id, else by name', () {
      expect(ChannelPlayback.keyOf(const VideoItem(id: 'a', title: '', channel: 'Name', channelId: 'UC1', url: '')), 'UC1');
      expect(ChannelPlayback.keyOf(const VideoItem(id: 'a', title: '', channel: 'Name', url: '')), 'name:Name');
      expect(ChannelPlayback.keyOf(const VideoItem(id: 'a', title: '', channel: '', url: '')), isNull);
    });

    test('keeps speed and volume apart and survives a restart', () async {
      final file = File('${dir.path}/channel_playback.json');
      final store = ChannelPlayback(file)
        ..remember('UC1', rate: 1.5)
        ..remember('UC1', volume: 40)
        ..remember('UC2', volume: 80);
      expect(store.of('UC1'), (rate: 1.5, volume: 40));
      store.remember('UC1', rate: 1, forgetRate: true);
      expect(store.of('UC1'), (rate: null, volume: 40));
      await store.save();
      final again = ChannelPlayback(file);
      await again.load();
      expect(again.of('UC1'), (rate: null, volume: 40));
      expect(again.of('UC2'), (rate: null, volume: 80));
      again.clear();
      expect(again.length, 0);
    });
  });

  group('观看统计', () {
    test('adds up seconds per day and channel in lumtub_core', () async {
      final file = File('${dir.path}/watch_time.json');
      final time = WatchTime(file)
        ..add('UC1', 'One', 600, at: DateTime(2026, 10, 27, 10))
        ..add('UC1', 'One', 120, at: DateTime(2026, 10, 27, 22))
        ..add('UC2', 'Two', 1800, at: DateTime(2026, 10, 25));
      await time.save();
      final again = WatchTime(file);
      await again.load();
      final stats = (await again.stats(today: DateTime(2026, 10, 27)))!;
      expect(stats.today, 720);
      expect(stats.week, 2520);
      expect(stats.days.last, ('2026-10-27', 720));
      expect(stats.top.first, ('UC2', 'Two', 1800));
    });

    test('durations read as people say them', () {
      expect(watchDuration(0), '0 分钟');
      expect(watchDuration(30), '不到 1 分钟');
      expect(watchDuration(125), '2 分钟');
      expect(watchDuration(3600), '1 小时');
      expect(watchDuration(3900), '1 小时 5 分');
    });
  });

  group('AI 总结', () {
    test('lumtub_core turns subtitles into timed paragraphs', () async {
      final transcript = await summaryTranscript(_vtt(20));
      expect(transcript.chunks, hasLength(1));
      expect(transcript.chunks.first, startsWith('[0:00] line number 0. line number 1.'));
      expect(transcript.cut, isFalse);
    });

    test('a short video is one request, a long one notes per part and a summary', () async {
      final asked = <String>[];
      final client = MockClient((request) async {
        final messages = (jsonDecode(request.body) as Map)['messages'] as List;
        asked.add((messages.last as Map)['content'] as String);
        return _reply('<think>hm</think>\n- [0:00] point ${asked.length}');
      });
      final ai = AiTranslator(client, baseUrl: 'https://ai.example/v1', key: 'k', model: 'm', prompt: '');
      final short = await summarizeTranscript(ai, 'Title', await summaryTranscript(_vtt(10)));
      expect(short, '- [0:00] point 1');
      expect(asked.single, contains('Transcript:'));
      asked.clear();
      final progress = <(int, int)>[];
      final long = await summarizeTranscript(ai, 'Title', await summaryTranscript(_vtt(60), budget: 500), onProgress: (done, total) => progress.add((done, total)));
      expect(asked.length, greaterThan(2));
      expect(asked.last, contains('Notes on each part'));
      expect(long, '- [0:00] point ${asked.length}');
      expect(progress.last.$1, progress.last.$2 - 1);
    });

    test('a video without subtitles is summarized from its description and chapters', () async {
      String? asked;
      final client = MockClient((request) async {
        final messages = (jsonDecode(request.body) as Map)['messages'] as List;
        asked = (messages.last as Map)['content'] as String;
        return _reply('- [1:05] Setup');
      });
      final ai = AiTranslator(client, baseUrl: 'https://ai.example/v1', key: 'k', model: 'm', prompt: '');
      final chapters = [(start: Duration.zero, title: 'Intro'), (start: const Duration(seconds: 65), title: 'Setup')];
      expect(canSummarizeDescription('short', const []), isFalse);
      expect(canSummarizeDescription('short', chapters), isTrue);
      final summary = await summarizeDescription(ai, 'Title', 'About the video', chapters);
      expect(asked, contains('[1:05] Setup'));
      expect(summary, startsWith('这个视频没有字幕'));
      expect(summary, endsWith('- [1:05] Setup'));
    });

    test('needs an AI service with its key, except a local one', () {
      final client = MockClient((_) async => _reply(''));
      expect(aiServiceFor(const TranslationConfig(aiPreset: 'openai'), const {}, client), isNull);
      expect(aiServiceFor(const TranslationConfig(aiPreset: 'openai'), const {'ai': 'k'}, client), isNotNull);
      expect(aiServiceFor(const TranslationConfig(aiPreset: 'ollama'), const {}, client), isNotNull);
    });
  });

  test('搜索评论 matches every word in the text or the author, ignoring case', () {
    const comment = YoutubeComment(id: '1', author: '@Maria', text: 'Great Video about Rust and Flutter');
    expect(commentMatches(comment, commentQueryWords('rust  FLUTTER')), isTrue);
    expect(commentMatches(comment, commentQueryWords('maria great')), isTrue);
    expect(commentMatches(comment, commentQueryWords('rust go')), isFalse);
    expect(commentMatches(comment, commentQueryWords('  ')), isTrue);
  });

  test('播放列表 length adds what is known and what is left', () {
    final items = [
      const VideoItem(id: 'a', title: '', channel: '', url: '', duration: 3600),
      const VideoItem(id: 'b', title: '', channel: '', url: '', duration: 1200),
    ];
    expect(playlistLength(items), '共 1 小时 20 分');
    expect(playlistLength([...items, const VideoItem(id: 'c', title: '', channel: '', url: '')]), '至少 1 小时 20 分');
    expect(playlistLength(items, partial: true), '至少 1 小时 20 分');
    expect(playlistLength(items, progressOf: (id) => id == 'a' ? const WatchProgress(Duration(minutes: 50), Duration(hours: 1)) : null), '共 1 小时 20 分 · 还剩 30 分钟');
    expect(playlistLength(items, progressOf: (_) => const WatchProgress(Duration(hours: 1), Duration(hours: 1))), '共 1 小时 20 分 · 已全部看完');
    expect(playlistLength(const []), isNull);
  });

  test('订阅分组 are kept with the library', () async {
    final file = File('${dir.path}/library.json');
    final store = LibraryStore(file);
    store.channelGroups.add(ChannelGroup('学习', {'UC1', 'UC2'}));
    await store.save();
    final again = LibraryStore(file);
    await again.load();
    expect(again.channelGroups.single.name, '学习');
    expect(again.channelGroups.single.channels, {'UC1', 'UC2'});
  });

  testWidgets('专注模式 leaves the home page without videos', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = AppController()
      ..ready = true
      ..preferences = const AppPreferences(focusHideHome: true);
    var searched = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VideoActions(controller: controller, child: HomeFeedPage(controller: controller, onFocusSearch: () => searched = true)))));
    expect(find.text('专注模式'), findsOneWidget);
    expect(find.text('为你推荐'), findsNothing);
    await tester.tap(find.text('搜索 (Ctrl+K)'));
    expect(searched, isTrue);
  });
}
