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
  setUp(VideoLanguages.reset);
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
      // Not answered: kept, as an English title may be a translation; a
      // title plainly in a third language is not.
      _video('ddddddddddd', 'English title'),
    ]);
    final kept = await languages.only(lines, ExploreLanguage.zh).toList();
    final titles = [for (final line in kept) (jsonDecode(line) as Map)['title']];
    expect(titles, unorderedEquals(['A channel', '成都美食之旅', '中文标题', 'English title']));
    // An answer without captions is asked again whole and of the TV app,
    // in case either has them.
    expect(asked, 7, reason: 'every video is asked about');
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
    // Masked, then whole, then of the TV app.
    expect((web, tv), (2, 1));
    await languages.only(Stream.fromIterable([_video('iiiiiiiiiii', 'More gardening')]), ExploreLanguage.it).toList();
    expect((web, tv), (2, 2), reason: 'the TV app is asked first from then on');
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);

  test('asks for whole answers when the field mask leaves the video out', () async {
    var masked = 0, whole = 0;
    final client = MockClient((request) async {
      if (request.headers.containsKey('X-Goog-FieldMask')) {
        masked++;
        return http.Response('{}', 200);
      }
      whole++;
      return http.Response.bytes(utf8.encode(jsonEncode(players['bbbbbbbbbbb'])), 200);
    });
    final languages = VideoLanguages(client);
    final kept = await languages.only(Stream.fromIterable([_video('aaaaaaaaaaa', 'Chengdu food trip'), _video('fffffffffff', 'Another trip')]), ExploreLanguage.en).toList();
    expect([for (final line in kept) (jsonDecode(line) as Map)['title']], ['Chengdu food tour', 'Chengdu food tour']);
    expect(whole, 2);
    // The two lookups ran together; later ones skip the mask.
    final before = masked;
    await languages.only(Stream.fromIterable([_video('ggggggggggg', 'A third trip')]), ExploreLanguage.en).toList();
    expect(masked, before, reason: 'the mask is dropped after it left the video out');
    expect(whole, 3);
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);

  test('asks titles in the language looked for, and asks again what English titles alone decided', () async {
    final hls = <String>[];
    final client = MockClient((request) async {
      final hl = (((jsonDecode(request.body) as Map)['context'] as Map)['client'] as Map)['hl'] as String;
      hls.add(hl);
      // The uploader translated the title into English.
      final title = hl == 'it' ? 'Il nostro viaggio in Sicilia con la famiglia' : 'Our trip to Sicily with the family';
      return http.Response.bytes(utf8.encode(jsonEncode({
        'playabilityStatus': {'status': 'OK'},
        'videoDetails': {'title': title, 'shortDescription': ''},
      })), 200);
    });
    final folder = Directory.systemTemp.createTempSync('languages');
    addTearDown(() => folder.deleteSync(recursive: true));
    final languages = VideoLanguages(client, file: File('${folder.path}/languages.json'));
    expect((await languages.of('aaaaaaaaaaa'))?.language, ExploreLanguage.en);
    expect(hls.toSet(), {'en'});
    hls.clear();
    final italian = await languages.of('aaaaaaaaaaa', asking: ExploreLanguage.it);
    // Only a guess from a title the uploader may have translated: the
    // strict filter does not take it.
    expect((italian?.language, italian?.source), (ExploreLanguage.it, 'text'));
    expect(hls.toSet(), {'it'});
    hls.clear();
    await languages.of('aaaaaaaaaaa', asking: ExploreLanguage.it);
    expect(hls, isEmpty, reason: 'the answer asked in Italian is kept');
    final line = _video('aaaaaaaaaaa', 'Our trip to Sicily with the family');
    expect(await languages.only(Stream.value(line), ExploreLanguage.it, heardOnly: true).toList(), isEmpty);
    expect(await languages.only(Stream.value(line), ExploreLanguage.it).toList(), hasLength(1));
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);
  test('hearing alone gives way to titles when YouTube hardly ever tells', () async {
    // Answers with the title alone, no captions or audio tracks.
    final client = MockClient((request) async => http.Response.bytes(utf8.encode(jsonEncode({
          'playabilityStatus': {'status': 'OK'},
          'videoDetails': {'title': 'A long walk through the old town of Edinburgh at night', 'shortDescription': ''},
        })), 200));
    final languages = VideoLanguages(client);
    String id(int i) => 'v${i.toString().padLeft(10, '0')}';
    final lines = [for (var i = 0; i < 50; i++) _video(id(i), 'A long walk through the old town of Edinburgh at night')];
    final kept = await languages.only(Stream.fromIterable(lines), ExploreLanguage.en, heardOnly: true).toList();
    expect(kept, hasLength(50), reason: 'none could be heard, so the titles decide');
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);
  test('stops asking for a while once YouTube leaves the video out', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{"playabilityStatus":{"status":"LOGIN_REQUIRED"}}', 200);
    });
    final languages = VideoLanguages(client);
    String id(int i) => 'w${i.toString().padLeft(10, '0')}';
    final lines = [for (var i = 0; i < 60; i++) _video(id(i), 'A long walk through the old town of Edinburgh at night')];
    final kept = await languages.only(Stream.fromIterable(lines), ExploreLanguage.en).toList();
    expect(kept, hasLength(60), reason: 'titles judge what could not be asked');
    // Twenty lookups of two requests each, and a few already running.
    expect(calls, lessThan(60));
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);
}
