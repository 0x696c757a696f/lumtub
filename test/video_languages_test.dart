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

Map<String, Object?> _player(String title, {String? asr, List<String> audio = const [], String description = ''}) => {
      'playabilityStatus': {'status': 'OK'},
      'videoDetails': {'title': title, 'shortDescription': description},
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
    SpokenVideo spoken(ExploreLanguage? language, String source, [String title = 'Lezione di filosofia']) => (language: language, title: title, source: source);
    bool passes(SpokenVideo? s, String listed) => VideoLanguages.passes(s, ExploreLanguage.it, listed: listed);

    test('audio or captions decide, whatever the titles say', () {
      expect(passes(spoken(ExploreLanguage.it, 'captions'), 'Philosophy lecture'), isTrue);
      expect(passes(spoken(ExploreLanguage.it, 'audio'), 'Philosophy lecture'), isTrue);
      expect(passes(spoken(ExploreLanguage.en, 'captions'), 'Lezione di filosofia'), isFalse);
      // Dubbed into Italian, spoken in English.
      expect(passes(spoken(ExploreLanguage.en, 'audio'), 'Lezione di filosofia'), isFalse);
    });

    test('without audio or captions, only texts that are not a translation', () {
      expect(passes(spoken(ExploreLanguage.it, 'text'), 'Lezione di filosofia'), isTrue);
      // Listed differently in English: the title was translated one way or the other.
      expect(passes(spoken(ExploreLanguage.it, 'text'), 'Philosophy lecture'), isFalse);
      expect(passes(spoken(ExploreLanguage.en, 'text', 'Philosophy lecture'), 'Philosophy lecture'), isFalse);
      expect(passes(spoken(null, 'none', ''), 'Lezione di filosofia'), isFalse);
    });

    test('nothing passes without an answer', () {
      expect(passes(null, 'Lezione di filosofia'), isFalse);
    });
  }, skip: core);

  test('keeps only videos whose captions or audio say the language, under the title asked in it', () async {
    final players = {
      'aaaaaaaaaaa': _player('Lezione di filosofia: Kant', asr: 'it'),
      'bbbbbbbbbbb': _player('Introduzione a Nietzsche', asr: 'en'),
      // Dubbed into Italian, spoken in English.
      'ccccccccccc': _player('Aristotele in 7 minuti', audio: ['en', 'it']),
      'ddddddddddd': _player('Platone, la Repubblica', description: 'Una lezione sulla Repubblica di Platone e sulla sua idea di giustizia, con una lettura dei passi più importanti del libro.'),
      // Its uploader translated the title into Italian; the listing shows the English one.
      'fffffffffff': _player('La felicità secondo Aristotele', description: 'Una lezione sulla felicità e sulla virtù nella filosofia di Aristotele.'),
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
            _video('fffffffffff', 'Happiness according to Aristotle'),
          ]),
          ExploreLanguage.it,
          done: (c) => check = c,
        )
        .toList();
    // Heard first, then what only its own texts let in.
    expect([for (final line in kept) (jsonDecode(line) as Map)['title']], ['A channel', 'Lezione di filosofia: Kant', 'Platone, la Repubblica']);
    expect(hls, {'it'});
    expect(check, (asked: 6, kept: 2, heard: 3));
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

  test("asks as the visitor YouTube's own page names, with its cookies", () async {
    final visitors = <String?>[];
    final cookies = <String?>[];
    var pages = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        pages++;
        return http.Response.bytes(utf8.encode('<script>ytcfg.set({"VISITOR_DATA":"CgtWaXNpdG9yMTIz"})</script>'), 200,
            headers: {'set-cookie': 'YSC=abc; Domain=.youtube.com; Path=/; Secure,VISITOR_INFO1_LIVE=xyz; Domain=.youtube.com; Path=/'});
      }
      visitors.add(request.headers['X-Goog-Visitor-Id']);
      cookies.add(request.headers['Cookie']);
      final client = ((jsonDecode(request.body) as Map)['context'] as Map)['client'] as Map;
      expect(client['visitorData'], 'CgtWaXNpdG9yMTIz');
      return _json(_player('Ricette di casa', asr: 'it'));
    });
    final languages = VideoLanguages(client);
    await languages.of('jjjjjjjjjjj', asking: ExploreLanguage.it);
    await languages.of('kkkkkkkkkkk', asking: ExploreLanguage.it);
    expect(pages, 1, reason: 'the page is opened once');
    expect(visitors, ['CgtWaXNpdG9yMTIz', 'CgtWaXNpdG9yMTIz']);
    expect(cookies.first, allOf(contains('SOCS=CAI'), contains('YSC=abc'), contains('VISITOR_INFO1_LIVE=xyz')));
  }, skip: core);

  test('reads visitor data the page writes with escapes', () async {
    final visitors = <String?>[];
    final client = MockClient((request) async {
      if (request.method == 'GET') return http.Response(r'<script>ytcfg.set({"VISITOR_DATA":"CgtWaXNpdG9y\u003d\u003d"})</script>', 200);
      visitors.add(request.headers['X-Goog-Visitor-Id']);
      return _json(_player('Ricette di casa', asr: 'it'));
    });
    await VideoLanguages(client).of('lllllllllll', asking: ExploreLanguage.it);
    expect(visitors, ['CgtWaXNpdG9y==']);
  }, skip: core);

  test("takes the visitor from YouTube's answer when the page names none, and asks a refused video again", () async {
    final asked = <(String?, String?)>[];
    final client = MockClient((request) async {
      if (request.method == 'GET') return http.Response('<html>no config here</html>', 200);
      final visitor = request.headers['X-Goog-Visitor-Id'];
      asked.add((visitor, request.headers['X-Goog-FieldMask']));
      if (visitor == null) {
        return _json({
          'responseContext': {'visitorData': 'CgtSZWZ1c2Vk'},
          'playabilityStatus': {'status': 'LOGIN_REQUIRED', 'reason': "Sign in to confirm you're not a bot"},
        });
      }
      expect(((jsonDecode(request.body) as Map)['context'] as Map)['client']['visitorData'], visitor);
      return _json(_player('Ricette di casa', asr: 'it'));
    });
    final languages = VideoLanguages(client);
    expect((await languages.of('mmmmmmmmmmm', asking: ExploreLanguage.it))?.source, 'captions');
    await languages.of('nnnnnnnnnnn', asking: ExploreLanguage.it);
    expect([for (final (visitor, _) in asked) visitor], [null, 'CgtSZWZ1c2Vk', 'CgtSZWZ1c2Vk']);
    expect(asked.first.$2, isNull, reason: 'a masked answer would leave the visitor data out');
    expect(asked.skip(1).every((a) => a.$2 != null), isTrue, reason: 'masked again once the visitor is known');
  }, skip: core);

  test('keeps heard answers on disk, others for this run only', () async {
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
    var languages = VideoLanguages(client, file: file);
    await languages.of('aaaaaaaaaaa', asking: ExploreLanguage.it);
    await languages.of('bbbbbbbbbbb', asking: ExploreLanguage.it);
    calls = 0;
    await languages.of('zzzzzzzzzzz', asking: ExploreLanguage.it);
    expect(calls, greaterThan(0), reason: 'a guess kept by an earlier version is asked again');
    calls = 0;
    expect((await languages.of('aaaaaaaaaaa', asking: ExploreLanguage.it))?.source, 'captions');
    expect((await languages.of('bbbbbbbbbbb', asking: ExploreLanguage.it))?.source, 'text');
    expect(calls, 0, reason: 'both are kept for this run');
    await Future<void>.delayed(const Duration(seconds: 6));
    languages = VideoLanguages(client, file: file);
    await languages.of('aaaaaaaaaaa', asking: ExploreLanguage.it);
    expect(calls, 0, reason: 'the heard one is kept on disk');
    await languages.of('bbbbbbbbbbb', asking: ExploreLanguage.it);
    expect(calls, greaterThan(0), reason: 'the other is asked again in a later run');
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

  test('lets in videos without captions by their own texts, behind the heard ones, and stops asking the other apps when they never tell', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final id = (jsonDecode(request.body) as Map)['videoId'] as String;
      return _json(id.startsWith('h') ? _player('成都美食探店', asr: 'zh') : _player('成都美食探店'));
    });
    final languages = VideoLanguages(client);
    String line(String id) => _video(id, '成都美食探店');
    final ids = [for (var i = 0; i < 60; i++) 't${i.toString().padLeft(10, '0')}', 'h0000000001'];
    final kept = await languages.only(Stream.fromIterable(ids.map(line)), ExploreLanguage.zh, heldUpTo: 100).toList();
    expect(kept, hasLength(61));
    expect((jsonDecode(kept.first) as Map)['id'], 'h0000000001', reason: 'heard ones go first');
    expect(calls, lessThan(60 * PlayerClient.values.length ~/ 2), reason: 'the other apps are left alone once they never tell');
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
