import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/explore_filters.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/video_languages.dart';
import 'package:lumtub/youtube_player_probe.dart';

String _video(String id, String title) => jsonEncode({'id': id, 'title': title, 'channel': 'c'});

Map<String, Object?> _player(String title, {String? asr, List<String> audio = const []}) => {
      'responseContext': {'visitorData': 'CgtWaXNpdG9yMTIz'},
      'playabilityStatus': {'status': 'OK'},
      'videoDetails': {'title': title, 'shortDescription': ''},
      if (asr != null)
        'captions': {
          'playerCaptionsTracklistRenderer': {
            'captionTracks': [
              {'languageCode': asr, 'kind': 'asr'},
            ],
          },
        },
      if (audio.isNotEmpty)
        'streamingData': {
          'adaptiveFormats': [
            for (final (i, code) in audio.indexed)
              {
                'itag': 140,
                'audioTrack': {'id': '$code.${i == 0 ? 4 : 3}', 'displayName': code, 'audioIsDefault': i == 0},
                'xtags': i == 0 ? 'acont=original' : 'acont=dubbed',
              },
          ],
        },
    };

http.Response _json(Object? body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

String _clientOf(http.Request request) => (((jsonDecode(request.body) as Map)['context'] as Map)['client'] as Map)['clientName'] as String;

void main() {
  final core = NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null;
  setUp(() {
    VideoLanguages.reset();
    YoutubePlayerProbe.forgetVisitor();
  });

  group('passes', () {
    SpokenVideo spoken(ExploreLanguage? language, String source) => (language: language, title: 'Titolo', source: source);

    test('audio or captions decide', () {
      expect(VideoLanguages.passes(spoken(ExploreLanguage.it, 'captions'), ExploreLanguage.it), isTrue);
      expect(VideoLanguages.passes(spoken(ExploreLanguage.it, 'audio'), ExploreLanguage.it), isTrue);
      expect(VideoLanguages.passes(spoken(ExploreLanguage.en, 'captions'), ExploreLanguage.it), isFalse);
    });

    test('titles and descriptions never decide, nor does no answer', () {
      // An English lecture whose uploader gave it an Italian title.
      expect(VideoLanguages.passes(spoken(ExploreLanguage.it, 'text'), ExploreLanguage.it), isFalse);
      expect(VideoLanguages.passes(spoken(null, 'none'), ExploreLanguage.it), isFalse);
      expect(VideoLanguages.passes(null, ExploreLanguage.it), isFalse);
    });
  });

  test('keeps only videos whose captions or audio say the language, under the title asked in it', () async {
    final players = {
      'aaaaaaaaaaa': _player('Lezione di filosofia: Kant', asr: 'it'),
      'bbbbbbbbbbb': _player('Introduzione a Nietzsche', asr: 'en'),
      // Dubbed into Italian, spoken in English.
      'ccccccccccc': _player('Aristotele in 7 minuti', audio: ['en', 'it']),
      'ddddddddddd': _player('Platone, la Repubblica'),
    };
    final hls = <String>{};
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      hls.add(((body['context'] as Map)['client'] as Map)['hl'] as String);
      return _json(players[body['videoId']] ?? {'playabilityStatus': {'status': 'ERROR'}});
    });
    final folder = Directory.systemTemp.createTempSync('languages');
    addTearDown(() => folder.deleteSync(recursive: true));
    final languages = VideoLanguages(client, file: File('${folder.path}/languages.json'));
    LanguageCheck? check;
    final kept = await languages
        .only(
          Stream.fromIterable([
            _video('aaaaaaaaaaa', 'Philosophy lecture: Kant'),
            _video('bbbbbbbbbbb', 'Introduction to Nietzsche'),
            jsonEncode({'id': 'UCxxxxxxxxxxxxxxxxxxxxxx', 'title': 'A channel', '_type': 'url', 'ie_key': 'YoutubeTab', 'url': 'https://www.youtube.com/channel/UCxxxxxxxxxxxxxxxxxxxxxx'}),
            _video('ccccccccccc', 'Aristotle in 7 minutes'),
            _video('ddddddddddd', 'Platone, la Repubblica'),
            _video('eeeeeeeeeee', 'La filosofia di Spinoza'),
          ]),
          ExploreLanguage.it,
          done: (c) => check = c,
        )
        .toList();
    expect([for (final line in kept) (jsonDecode(line) as Map)['title']], unorderedEquals(['A channel', 'Lezione di filosofia: Kant']));
    expect(hls, {'it'});
    expect(check, (asked: 5, kept: 1, heard: 3));
  }, skip: core);

  test('asks the next app when one gives no captions, and asks it first from then on', () async {
    final asked = <String>[];
    final client = MockClient((request) async {
      final name = _clientOf(request);
      asked.add(name);
      return _json(name == 'TVHTML5' ? _player('Giardinaggio sul balcone', asr: 'it') : _player('Giardinaggio sul balcone'));
    });
    final languages = VideoLanguages(client);
    final kept = await languages.only(Stream.fromIterable([_video('hhhhhhhhhhh', 'Gardening on the balcony')]), ExploreLanguage.it).toList();
    expect([for (final line in kept) (jsonDecode(line) as Map)['title']], ['Giardinaggio sul balcone']);
    expect(asked, ['VISIONOS', 'TVHTML5']);
    asked.clear();
    await languages.only(Stream.fromIterable([_video('iiiiiiiiiii', 'More gardening')]), ExploreLanguage.it).toList();
    expect(asked, ['TVHTML5']);
  }, skip: core);

  test('sends back the visitor id YouTube gave', () async {
    final visitors = <String?>[];
    final client = MockClient((request) async {
      visitors.add(request.headers['X-Goog-Visitor-Id']);
      return _json(_player('Ricette di casa', asr: 'it'));
    });
    final languages = VideoLanguages(client);
    await languages.of('jjjjjjjjjjj', asking: ExploreLanguage.it);
    await languages.of('kkkkkkkkkkk', asking: ExploreLanguage.it);
    expect(visitors, [null, 'CgtWaXNpdG9yMTIz']);
  }, skip: core);

  test('keeps only heard answers, on disk and in memory', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final id = (jsonDecode(request.body) as Map)['videoId'];
      return _json(id == 'aaaaaaaaaaa' ? _player('Lezione', asr: 'it') : _player('Lezione senza sottotitoli'));
    });
    final folder = Directory.systemTemp.createTempSync('languages');
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File('${folder.path}/languages.json')
      // Written by an earlier version: a guess from the title.
      ..writeAsStringSync(jsonEncode({
        'zzzzzzzzzzz': {'language': ExploreLanguage.it.index, 'title': 'Titolo', 'source': 'text'},
      }));
    final languages = VideoLanguages(client, file: file);
    await languages.of('aaaaaaaaaaa', asking: ExploreLanguage.it);
    await languages.of('bbbbbbbbbbb', asking: ExploreLanguage.it);
    await languages.of('zzzzzzzzzzz', asking: ExploreLanguage.it);
    calls = 0;
    expect((await languages.of('aaaaaaaaaaa', asking: ExploreLanguage.it))?.source, 'captions');
    expect(calls, 0, reason: 'a heard answer is kept');
    await languages.of('bbbbbbbbbbb', asking: ExploreLanguage.it);
    expect(calls, PlayerClient.values.length, reason: 'an unheard one is asked again, of every app');
  }, skip: core);

  test('leaves out a channel plainly in another language without asking about its videos', () async {
    final asked = <String>{};
    final client = MockClient((request) async {
      final id = (jsonDecode(request.body) as Map)['videoId'] as String;
      asked.add(id);
      return _json(_player('Lecture', asr: id.startsWith('e') ? 'en' : 'it'));
    });
    final folder = Directory.systemTemp.createTempSync('languages');
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File('${folder.path}/languages.json');
    String line(String id, String channel) => jsonEncode({'id': id, 'title': 'Lecture', 'channel': 'c', 'channel_id': channel});
    const english = 'UCaaaaaaaaaaaaaaaaaaaaaa', mixed = 'UCbbbbbbbbbbbbbbbbbbbbbb';
    var languages = VideoLanguages(client, file: file);
    await languages.only(Stream.fromIterable([for (var i = 0; i < VideoLanguages.channelSure; i++) line('e000000000$i', english)]), ExploreLanguage.it).toList();
    await languages.only(Stream.fromIterable([line('e0000000009', mixed), line('i0000000009', mixed), line('e0000000008', mixed)]), ExploreLanguage.it).toList();
    expect(languages.channelSpeaks(english), ExploreLanguage.en);
    expect(languages.channelSpeaks(mixed), isNull, reason: 'heard in two languages');
    // Kept on disk, so a later run knows the channel too.
    await Future<void>.delayed(const Duration(seconds: 6));
    languages = VideoLanguages(client, file: file);
    asked.clear();
    final kept = await languages.only(Stream.fromIterable([line('e0000000005', english), line('i0000000005', mixed)]), ExploreLanguage.it).toList();
    expect(asked, {'i0000000005'});
    expect(kept, hasLength(1));
  }, skip: core);

  test('stops once YouTube tells none of the first answers by audio or captions', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return _json(_player('Una passeggiata a Roma'));
    });
    final languages = VideoLanguages(client);
    String id(int i) => 'w${i.toString().padLeft(10, '0')}';
    LanguageCheck? check;
    final kept = await languages
        .only(Stream.fromIterable([for (var i = 0; i < 200; i++) _video(id(i), 'Una passeggiata a Roma')]), ExploreLanguage.it, done: (c) => check = c)
        .toList();
    expect(kept, isEmpty);
    expect(check?.heard, 0);
    expect(check!.asked, lessThan(200));
    expect(calls, lessThan(200 * PlayerClient.values.length));
  }, skip: core);

  test('stops asking for a while once YouTube leaves the video out', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{"playabilityStatus":{"status":"LOGIN_REQUIRED"}}', 200);
    });
    final languages = VideoLanguages(client);
    for (var i = 0; i < 40; i++) {
      await languages.of('x${i.toString().padLeft(10, '0')}', asking: ExploreLanguage.it);
    }
    final before = calls;
    expect(await languages.of('yyyyyyyyyyy', asking: ExploreLanguage.it), isNull);
    expect(calls, before, reason: 'resting');
  }, skip: core);
}
