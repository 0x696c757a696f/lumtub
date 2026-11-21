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
import 'package:lumtub/local_db.dart' show VideoNote;
import 'package:lumtub/models.dart';
import 'package:lumtub/translation_services.dart';
import 'package:lumtub/ui/pages/video_pages.dart';
import 'package:lumtub/ui/pages/watch_stats_page.dart';
import 'package:lumtub/ui/playlist_length.dart';
import 'package:lumtub/ui/video_card.dart';
import 'package:lumtub/ui/video_notes.dart' show notesText;
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

  group('Remember speed and volume per channel', () {
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

    test('overlapping saves leave the latest state and no temporary file', () async {
      final file = File('${dir.path}/channel_playback.json');
      final store = ChannelPlayback(file)..remember('UC1', volume: 10);
      final first = store.save();
      store.remember('UC1', volume: 20);
      final second = store.save();
      store.remember('UC1', volume: 30);
      await Future.wait([first, second, store.save()]);
      final again = ChannelPlayback(file);
      await again.load();
      expect(again.of('UC1'), (rate: null, volume: 30));
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });

    test('clear during a pending save leaves nothing', () async {
      final file = File('${dir.path}/channel_playback.json');
      final store = ChannelPlayback(file)..remember('UC1', volume: 10);
      final pending = store.save();
      store.clear();
      await pending;
      await store.save();
      final again = ChannelPlayback(file);
      await again.load();
      expect(again.length, 0);
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });
  });

  group('Watch statistics', () {
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
      expect(watchDuration(0), '0 min');
      expect(watchDuration(30), 'Under 1 min');
      expect(watchDuration(125), '2 min');
      expect(watchDuration(3600), '1 h');
      expect(watchDuration(3900), '1 h 5 min');
    });
  });

  group('AI summary', () {
    test('lumtub_core turns subtitles into timed paragraphs', () async {
      final transcript = await summaryTranscript(_vtt(20));
      expect(transcript.chunks, hasLength(1));
      expect(transcript.chunks.first, startsWith('[0:00] line number 0. line number 1.'));
      expect(transcript.cut, isFalse);
    });

    test('a short video is one request for an overview, its times checked against the subtitles', () async {
      final asked = <String>[];
      final client = MockClient((request) async {
        final messages = (jsonDecode(request.body) as Map)['messages'] as List;
        asked.add((messages.last as Map)['content'] as String);
        return _reply('<think>hm</think>\n```json\n${jsonEncode({
              'about': 'Lines are counted.',
              'chapters': [
                {'time': '0:16', 'title': 'Later lines'},
                {'time': '0:02', 'title': 'First lines'},
                {'time': '9:00', 'title': 'Made up'},
              ],
              'quotes': [
                {'time': '0:00', 'text': 'Line number 7.', 'translation': '第 7 行。'},
              ],
            })}\n```');
      });
      final ai = AiTranslator(client, baseUrl: 'https://ai.example/v1', key: 'k', model: 'm', prompt: '');
      final body = await summarizeTranscript(ai.complete, 'Title', await summaryTranscript(_vtt(10)), description: 'About lines');
      expect(asked.single, allOf(contains('Transcript:'), contains('About lines')));
      final overview = VideoOverview.parse(body)!;
      expect(overview.about, 'Lines are counted.');
      expect([for (final c in overview.chapters) (c.start.inSeconds, c.end.inSeconds, c.title)], [(0, 15, 'First lines'), (15, 49, 'Later lines')]);
      expect(overview.quotes.single.at, const Duration(seconds: 35));
      expect(overview.quotes.single.found, isTrue);
      expect(overview.text, contains('[0:35] “Line number 7.”'));
      expect(VideoOverview.parse(overview.body)!.quotes.single.translation, '第 7 行。');
      expect(VideoOverview.parse('- [0:00] an older summary'), isNull);
    });

    test('a model that will not answer in JSON gives a summary in text', () async {
      final asked = <String>[];
      final client = MockClient((request) async {
        final messages = (jsonDecode(request.body) as Map)['messages'] as List;
        asked.add((messages.last as Map)['content'] as String);
        return _reply('- [0:00] point ${asked.length}');
      });
      final ai = AiTranslator(client, baseUrl: 'https://ai.example/v1', key: 'k', model: 'm', prompt: '');
      final summary = await summarizeTranscript(ai.complete, 'Title', await summaryTranscript(_vtt(10)));
      expect(asked, hasLength(3));
      expect(asked[1], endsWith('Reply with the JSON object only.'));
      expect(summary, '- [0:00] point 3');
    });

    test('a long video is notes per part, then the overview of them', () async {
      final asked = <String>[];
      final systems = <String>[];
      final client = MockClient((request) async {
        final messages = (jsonDecode(request.body) as Map)['messages'] as List;
        systems.add((messages.first as Map)['content'] as String);
        asked.add((messages.last as Map)['content'] as String);
        if (asked.last.contains('Notes on each part')) return _reply('{"about": "All of it.", "chapters": [{"time": "0:00", "title": "Start"}, {"time": "4:00", "title": "End"}]}');
        return _reply('- [0:00] point\n> [0:05] "line number 1."');
      });
      final ai = AiTranslator(client, baseUrl: 'https://ai.example/v1', key: 'k', model: 'm', prompt: '');
      final progress = <(int, int)>[];
      final body = await summarizeTranscript(ai.complete, 'Title', await summaryTranscript(_vtt(60), budget: 500), onProgress: (done, total) => progress.add((done, total)));
      expect(asked.length, greaterThan(2));
      expect(asked.last, contains('Notes on each part'));
      expect(systems.last, contains('The last chapter must start after 3:44.'));
      expect(VideoOverview.parse(body)!.chapters.map((c) => c.title), ['Start', 'End']);
      expect(progress.last.$1, progress.last.$2 - 1);
    });

    test('a subtitle line is explained with the lines around it, and a note tidied', () async {
      final asked = <String>[];
      final client = MockClient((request) async {
        final messages = (jsonDecode(request.body) as Map)['messages'] as List;
        asked.add((messages.last as Map)['content'] as String);
        return _reply('<think>x</think>It means hello.');
      });
      final ai = AiTranslator(client, baseUrl: 'https://ai.example/v1', key: 'k', model: 'm', prompt: '');
      expect(await explainSubtitle(ai.complete, 'Howdy', title: 'T', before: ['a'], after: ['b']), 'It means hello.');
      expect(asked.last, allOf(contains('Before:\na'), contains('The line:\nHowdy'), contains('After:\nb')));
      expect(await tidyNoteText(ai.complete, 'um so like the cold', 'cold bad'), 'It means hello.');
      expect(asked.last, contains("The viewer's note:\ncold bad"));
    });

    test('notes are Markdown with their times', () {
      final notes = [
        VideoNote(id: 1, video: 'v', at: const Duration(seconds: 65), quote: 'Batteries hate\nthe cold.', body: 'Keep it warm.', created: DateTime(2026)),
        VideoNote(id: 2, video: 'v', at: const Duration(minutes: 2), body: 'Only a thought.', created: DateTime(2026)),
      ];
      expect(notesText('Talk', notes), '# Talk\n\n> [01:05] Batteries hate the cold.\n\nKeep it warm.\n\n[02:00]\n\nOnly a thought.');
    });

    test('translations into Chinese follow its style rules, other languages and own prompts do not', () {
      final client = MockClient((_) async => _reply(''));
      final built = AiTranslator(client, baseUrl: 'https://ai.example/v1', model: 'm', prompt: AiTranslator.promptPresets.first.text);
      expect(built.systemPrompt('zh-CN', 1, const []), contains(AiTranslator.chineseStyle));
      expect(built.systemPrompt('zh-TW', 1, const []), contains(AiTranslator.chineseStyle));
      expect(built.systemPrompt('ja', 1, const []), isNot(contains(AiTranslator.chineseStyle)));
      final own = AiTranslator(client, baseUrl: 'https://ai.example/v1', model: 'm', prompt: 'Translate into {target}.');
      expect(own.systemPrompt('zh-CN', 1, const []), isNot(contains(AiTranslator.chineseStyle)));
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
      final summary = await summarizeDescription(ai.complete, 'Title', 'About the video', chapters);
      expect(asked, contains('[1:05] Setup'));
      expect(summary, startsWith('This video has no subtitles'));
      expect(summary, endsWith('- [1:05] Setup'));
    });

    test('needs an AI service with its key, except a local one', () {
      final client = MockClient((_) async => _reply(''));
      expect(aiServiceFor(const TranslationConfig(aiPreset: 'openai'), const {}, client), isNull);
      expect(aiServiceFor(const TranslationConfig(aiPreset: 'openai'), const {'ai@api.openai.com': 'k'}, client), isNotNull);
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
    expect(playlistLength(items), '1 h 20 min in total');
    expect(playlistLength([...items, const VideoItem(id: 'c', title: '', channel: '', url: '')]), 'At least 1 h 20 min');
    expect(playlistLength(items, partial: true), 'At least 1 h 20 min');
    expect(playlistLength(items, progressOf: (id) => id == 'a' ? const WatchProgress(Duration(minutes: 50), Duration(hours: 1)) : null), '1 h 20 min in total · 30 min left');
    expect(playlistLength(items, progressOf: (_) => const WatchProgress(Duration(hours: 1), Duration(hours: 1))), '1 h 20 min in total · all watched');
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
    expect(find.text('Focus mode'), findsOneWidget);
    expect(find.text('For you'), findsNothing);
    await tester.tap(find.text(Platform.isMacOS ? 'Search (⌘K)' : 'Search (Ctrl+K)'));
    expect(searched, isTrue);
  });
}
