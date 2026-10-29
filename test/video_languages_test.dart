import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/explore_filters.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/video_languages.dart';

String _video(String id, String title) => jsonEncode({'id': id, 'title': title, 'channel': 'c'});

void main() {
  final players = {
    'aaaaaaaaaaa': {
      'videoDetails': {'title': '成都美食之旅', 'shortDescription': ''},
    },
    'bbbbbbbbbbb': {
      'videoDetails': {'title': 'Chengdu food tour', 'shortDescription': 'Eating my way through Chengdu'},
      'captions': {
        'playerCaptionsTracklistRenderer': {
          'captionTracks': [
            {'languageCode': 'en', 'kind': 'asr'},
          ],
        },
      },
    },
  };
  var asked = 0;
  http.Client client() => MockClient((request) async {
        final id = (jsonDecode(request.body) as Map)['videoId'] as String;
        asked++;
        final player = players[id];
        return player == null ? http.Response('nope', 500) : http.Response.bytes(utf8.encode(jsonEncode(player)), 200);
      });

  test('keeps videos spoken in the language, under their own titles', () async {
    final folder = Directory.systemTemp.createTempSync('languages');
    final languages = VideoLanguages(client(), file: File('${folder.path}/languages.json'));
    final lines = Stream.fromIterable([
      _video('aaaaaaaaaaa', 'Chengdu food trip'),
      _video('bbbbbbbbbbb', 'Chengdu food tour'),
      jsonEncode({'id': 'UCxxxxxxxxxxxxxxxxxxxxxx', 'title': 'A channel', '_type': 'url', 'ie_key': 'YoutubeTab', 'url': 'https://www.youtube.com/channel/UCxxxxxxxxxxxxxxxxxxxxxx'}),
      // Only English titles may be translations; others are not asked.
      _video('ccccccccccc', '中文标题'),
      _video('eeeeeeeeeee', '日本語のタイトル'),
      // Not answered: judged by its listed title.
      _video('ddddddddddd', 'English title'),
    ]);
    final kept = await languages.only(lines, ExploreLanguage.zh).toList();
    final titles = [for (final line in kept) (jsonDecode(line) as Map)['title']];
    expect(titles, unorderedEquals(['成都美食之旅', 'A channel', '中文标题']));
    expect(asked, 3, reason: 'only the three English titles are asked about');
    asked = 0;
    final again = await languages.only(Stream.fromIterable([_video('aaaaaaaaaaa', 'Chengdu food trip')]), ExploreLanguage.en).toList();
    expect(again, isEmpty);
    expect(asked, 0, reason: 'answers are kept');
    folder.deleteSync(recursive: true);
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);
}
