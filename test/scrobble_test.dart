import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/scrobble.dart';
import 'package:lumtub/ui/pages/scrobble_settings.dart';
import 'package:material_ui/material_ui.dart';

VideoItem _video({String id = 'abcdefghijk', String title = 'A song', String channel = 'Someone', int? duration = 200, String? description, String? liveStatus}) =>
    VideoItem(id: id, title: title, channel: channel, duration: duration, url: 'https://www.youtube.com/watch?v=$id', description: description, liveStatus: liveStatus);

VideoDetails _details(Map<String, dynamic> json) => VideoDetails.fromJson({'title': 'A song', 'channel': 'Someone', ...json});

void main() {
  group('which videos are songs', () {
    test('YouTube Music song tags win', () {
      final details = _details({'track': 'Clocks', 'artists': ['Coldplay'], 'album': 'A Rush of Blood to the Head', 'categories': ['Music']});
      final track = scrobbleTrackOf(_video(), details)!;
      expect((track.artist, track.title, track.album), ('Coldplay', 'Clocks', 'A Rush of Blood to the Head'));
    });

    test('an older yt-dlp lists the artists in one string', () {
      expect(_details({'track': 'Song', 'artist': 'One, Two'}).music.artists, ['One', 'Two']);
    });

    test('auto-generated "Provided to YouTube by" uploads', () {
      const description = 'Provided to YouTube by Sony Music\n\nSong Name · First Artist · Second Artist\n\nThe Album\n\n℗ 2020 Sony';
      final track = scrobbleTrackOf(_video(title: 'Song Name', channel: 'First Artist - Topic', description: description), null)!;
      expect((track.artist, track.title, track.album), ('First Artist, Second Artist', 'Song Name', 'The Album'));
    });

    test('"Artist - Topic" channels', () {
      final track = scrobbleTrackOf(_video(title: 'Song Name', channel: 'Artist Name - Topic'), null)!;
      expect((track.artist, track.title), ('Artist Name', 'Song Name'));
    });

    test('a music video titled "Artist - Title (Official Video)"', () {
      final details = _details({'title': 'Daft Punk - Get Lucky (Official Video) ft. Pharrell', 'channel': 'Daft Punk', 'categories': ['Music']});
      final track = scrobbleTrackOf(_video(), details)!;
      expect((track.artist, track.title), ('Daft Punk', 'Get Lucky ft. Pharrell'));
    });

    test('an official video on the artist\'s own channel', () {
      final details = _details({'title': 'Shake It Off (Official Music Video)', 'channel': 'TaylorSwiftVEVO', 'categories': ['Music']});
      final track = scrobbleTrackOf(_video(), details)!;
      expect((track.artist, track.title), ('Taylor Swift', 'Shake It Off'));
    });

    test('"(Live)" and quotes', () {
      expect(cleanSongTitle('"Yellow" (Live) [HD] | Glastonbury'), '"Yellow" (Live)');
      expect(cleanSongTitle('“Yellow” [Official Lyric Video]'), 'Yellow');
      expect(cleanSongTitle('Yellow (Live)'), 'Yellow (Live)');
    });

    test('anything else is not a song', () {
      // A talk in the Music category with no artist in its title.
      expect(scrobbleTrackOf(_video(), _details({'title': 'How I wrote my album', 'categories': ['Music']})), isNull);
      // A dash in a title outside the Music category.
      expect(scrobbleTrackOf(_video(), _details({'title': 'Rust - ownership explained', 'categories': ['Education']})), isNull);
      // No details yet and nothing in the listing says music.
      expect(scrobbleTrackOf(_video(title: 'Coldplay - Clocks'), null), isNull);
    });

    test('lives, mixes and very short clips are left out', () {
      final music = _details({'track': 'Song', 'artists': ['Artist']});
      expect(scrobbleTrackOf(_video(liveStatus: 'is_live'), music), isNull);
      expect(scrobbleTrackOf(_video(duration: 20), music), isNull);
      expect(scrobbleTrackOf(_video(duration: 3600), music), isNull);
      expect(scrobbleTrackOf(_video(duration: null), music), isNull);
      expect(scrobbleTrackOf(_video(duration: null), music, length: const Duration(seconds: 180)), isNotNull);
    });
  });

  test('a song counts after half its length or four minutes', () {
    expect(scrobbleThreshold(const Duration(seconds: 200)), const Duration(seconds: 100));
    expect(scrobbleThreshold(const Duration(minutes: 12)), const Duration(minutes: 4));
  });

  group('Scrobbler', () {
    late Directory folder;
    setUp(() => folder = Directory.systemTemp.createTempSync('scrobble'));
    tearDown(() => folder.deleteSync(recursive: true));

    const track = ScrobbleTrack(artist: 'Artist', title: 'Song', videoId: 'abcdefghijk', length: Duration(seconds: 60));

    Future<(Scrobbler, List<Map<String, dynamic>>, void Function(Duration))> make(Future<http.Response> Function(http.Request) answer) async {
      final sent = <Map<String, dynamic>>[];
      var now = DateTime(2026, 11, 27, 12);
      final client = MockClient((request) async {
        if (request.url.path == '/1/validate-token') return http.Response(jsonEncode({'valid': true, 'user_name': 'me'}), 200);
        expect(request.headers['Authorization'], 'Token secret');
        sent.add(jsonDecode(request.body) as Map<String, dynamic>);
        return answer(request);
      });
      final scrobbler = Scrobbler(client, version: '1.0', clock: () => now)..queueFile = File('${folder.path}/queue.json');
      await scrobbler.connect('secret');
      return (scrobbler, sent, (Duration step) => now = now.add(step));
    }

    Future<void> listen(Scrobbler scrobbler, void Function(Duration) advance, int seconds, {int from = 0}) async {
      for (var s = from; s <= from + seconds; s++) {
        scrobbler.observe(track, position: Duration(seconds: s), playing: true);
        advance(const Duration(seconds: 1));
      }
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    test('says what plays, then scrobbles once at half the song', () async {
      final (scrobbler, sent, advance) = await make((_) async => http.Response('{"status":"ok"}', 200));
      scrobbler.begin('abcdefghijk');
      await listen(scrobbler, advance, 20);
      expect(sent.map((s) => s['listen_type']), ['playing_now']);
      await listen(scrobbler, advance, 40, from: 21);
      expect(sent.map((s) => s['listen_type']), ['playing_now', 'single']);
      final listen0 = (sent.last['payload'] as List).single as Map;
      expect(listen0['listened_at'], DateTime(2026, 11, 27, 12).millisecondsSinceEpoch ~/ 1000);
      expect(listen0['track_metadata']['artist_name'], 'Artist');
      expect(listen0['track_metadata']['additional_info']['origin_url'], 'https://www.youtube.com/watch?v=abcdefghijk');
    });

    test('seeking ahead does not count as listening', () async {
      final (scrobbler, sent, advance) = await make((_) async => http.Response('{}', 200));
      scrobbler.begin('abcdefghijk');
      scrobbler.observe(track, position: Duration.zero, playing: true);
      advance(const Duration(seconds: 1));
      scrobbler.observe(track, position: const Duration(seconds: 55), playing: true);
      await Future<void>.delayed(Duration.zero);
      expect(sent, isEmpty);
    });

    test('another video playing is not counted', () async {
      final (scrobbler, sent, advance) = await make((_) async => http.Response('{}', 200));
      scrobbler.begin('zzzzzzzzzzz');
      await listen(scrobbler, advance, 60);
      expect(sent, isEmpty);
    });

    test('listens that could not be sent wait and go later', () async {
      var online = false;
      final (scrobbler, sent, advance) = await make((_) async => online ? http.Response('{}', 200) : http.Response('busy', 503));
      scrobbler.begin('abcdefghijk');
      await listen(scrobbler, advance, 40);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(scrobbler.waiting, 1);
      expect(File('${folder.path}/queue.json').existsSync(), isTrue);

      final again = Scrobbler(MockClient((_) async => http.Response('{}', 200)))..queueFile = File('${folder.path}/queue.json');
      await again.load();
      expect(again.waiting, 1);

      online = true;
      await scrobbler.retryWaiting();
      expect(sent.last['listen_type'], 'import');
      expect(scrobbler.waiting, 0);
      expect(File('${folder.path}/queue.json').existsSync(), isFalse);
    });

    test('a refused token stops sending', () async {
      final (scrobbler, sent, advance) = await make((_) async => http.Response('{"error":"Invalid token"}', 401));
      scrobbler.begin('abcdefghijk');
      await listen(scrobbler, advance, 40);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(scrobbler.tokenRefused, isTrue);
      final count = sent.length;
      scrobbler.begin('abcdefghijk');
      await listen(scrobbler, advance, 40);
      expect(sent.length, count);
    });
  });

  testWidgets('the settings row connects with a token and disconnects', (tester) async {
    final client = MockClient((request) async => request.headers['Authorization'] == 'Token good'
        ? http.Response(jsonEncode({'valid': true, 'user_name': 'listener'}), 200)
        : http.Response(jsonEncode({'valid': false}), 200));
    final scrobbler = Scrobbler(client);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ScrobbleSettings(scrobbler: scrobbler))));
    expect(find.textContaining('Off.'), findsOneWidget);

    await tester.tap(find.byType(ScrobbleSettings));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.text('ListenBrainz did not accept this token'), findsOneWidget);
    expect(scrobbler.connected, isFalse);

    await tester.enterText(find.byType(TextField), 'good');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(scrobbler.connected, isTrue);
    expect(find.text('Connected as listener'), findsWidgets);

    await tester.tap(find.byType(ScrobbleSettings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(scrobbler.connected, isFalse);
    expect(find.textContaining('Off.'), findsOneWidget);
  });
}
