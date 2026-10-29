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
      _video('ccccccccccc', '中文标题'),
      _video('eeeeeeeeeee', '日本語のタイトル'),
      // Not answered: judged by its listed title.
      _video('ddddddddddd', 'English title'),
    ]);
    final kept = await languages.only(lines, ExploreLanguage.zh).toList();
    final titles = [for (final line in kept) (jsonDecode(line) as Map)['title']];
    expect(titles, unorderedEquals(['成都美食之旅', 'A channel', '中文标题']));
    // The first answer without captions is asked again whole, in case
    // the field mask left them out.
    expect(asked, 6, reason: 'every video is asked about');
    asked = 0;
    final again = await languages.only(Stream.fromIterable([_video('aaaaaaaaaaa', 'Chengdu food trip')]), ExploreLanguage.en).toList();
    expect(again, isEmpty);
    expect(asked, 0, reason: 'answers are kept');
    folder.deleteSync(recursive: true);
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);

  test('asks the TV app when the website gets no captions', () async {
    var web = 0, tv = 0;
    final client = MockClient((request) async {
      final client = ((jsonDecode(request.body) as Map)['context'] as Map)['client'] as Map;
      if (client['clientName'] == 'TVHTML5') {
        tv++;
        return http.Response.bytes(utf8.encode(jsonEncode({
          'playabilityStatus': {'status': 'OK'},
          'videoDetails': {'title': 'Giardinaggio sul balcone', 'shortDescription': ''},
          'captions': {
            'playerCaptionsTracklistRenderer': {
              'captionTracks': [
                {'languageCode': 'it', 'kind': 'asr'},
              ],
            },
          },
        })), 200);
      }
      web++;
      return http.Response.bytes(utf8.encode(jsonEncode({
        'playabilityStatus': {'status': 'LOGIN_REQUIRED'},
        'videoDetails': {'title': 'Giardinaggio sul balcone', 'shortDescription': ''},
      })), 200);
    });
    final languages = VideoLanguages(client);
    final kept = await languages.only(Stream.fromIterable([_video('hhhhhhhhhhh', 'Gardening on the balcony')]), ExploreLanguage.it).toList();
    expect([for (final line in kept) (jsonDecode(line) as Map)['title']], ['Giardinaggio sul balcone']);
    expect((web, tv), (1, 1));
    await languages.only(Stream.fromIterable([_video('iiiiiiiiiii', 'More gardening')]), ExploreLanguage.it).toList();
    expect((web, tv), (1, 2), reason: 'the TV app is asked first from then on');
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);

  test('asks for whole answers when the field mask leaves the video out', () async {
    var masked = 0, whole = 0;
    final client = MockClient((request) async {
      if (request.headers.containsKey('X-Goog-FieldMask')) {
        masked++;
        return http.Response('{}', 200);
      }
      whole++;
      return http.Response.bytes(utf8.encode(jsonEncode(players['aaaaaaaaaaa'])), 200);
    });
    final languages = VideoLanguages(client);
    final kept = await languages.only(Stream.fromIterable([_video('aaaaaaaaaaa', 'Chengdu food trip'), _video('fffffffffff', 'Another trip')]), ExploreLanguage.zh).toList();
    expect([for (final line in kept) (jsonDecode(line) as Map)['title']], ['成都美食之旅', '成都美食之旅']);
    expect(whole, 2);
    // The two lookups ran together; later ones skip the mask.
    final before = masked;
    await languages.only(Stream.fromIterable([_video('ggggggggggg', 'A third trip')]), ExploreLanguage.zh).toList();
    expect(masked, before, reason: 'the mask is dropped after it left the video out');
    expect(whole, 3);
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);
}
