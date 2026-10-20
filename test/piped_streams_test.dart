import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ytplus/piped_streams.dart';
import 'package:ytplus/player_settings.dart';

Map<String, dynamic> _streams() => {
      'title': 'x',
      'livestream': false,
      'videoStreams': [
        {'url': 'https://proxy.example/v?itag=137', 'codec': 'avc1.640028', 'height': 1080, 'bitrate': 4000000, 'videoOnly': true, 'mimeType': 'video/mp4'},
        {'url': 'https://proxy.example/v?itag=248', 'codec': 'vp9', 'height': 1080, 'bitrate': 3000000, 'videoOnly': true, 'mimeType': 'video/webm'},
        {'url': 'https://proxy.example/v?itag=136', 'codec': 'avc1.4d401f', 'height': 720, 'bitrate': 2000000, 'videoOnly': true, 'mimeType': 'video/mp4'},
        {'url': 'https://proxy.example/v?itag=18', 'codec': 'avc1', 'height': 360, 'bitrate': 500000, 'videoOnly': false, 'mimeType': 'video/mp4'},
      ],
      'audioStreams': [
        {'url': 'https://proxy.example/a?itag=140', 'codec': 'mp4a.40.2', 'bitrate': 130000, 'mimeType': 'audio/mp4'},
        {'url': 'https://proxy.example/a?itag=251', 'codec': 'opus', 'bitrate': 160000, 'mimeType': 'audio/webm'},
        {'url': 'https://proxy.example/a?itag=139', 'codec': 'mp4a.40.5', 'bitrate': 48000, 'mimeType': 'audio/mp4'},
      ],
    };

void main() {
  final video = PipedVideo.fromJson('https://p', _streams());

  test('picks streams the way the yt-dlp expression would', () {
    expect(video.heights, [1080, 720]);
    expect(video.pickVideo(const PlayerSettings())!.url, endsWith('itag=137'));
    expect(video.pickVideo(const PlayerSettings(codec: CodecPreference.vp9))!.url, endsWith('itag=248'));
    expect(video.pickVideo(const PlayerSettings(maxHeight: 720))!.url, endsWith('itag=136'));
    expect(video.pickVideo(const PlayerSettings(maxHeight: 144))!.height, 720);
    expect(video.pickAudio(const PlayerSettings())!.url, endsWith('itag=251'));
    expect(video.pickAudio(const PlayerSettings(audioQuality: AudioQuality.medium))!.url, endsWith('itag=140'));
    expect(video.pickAudio(const PlayerSettings(audioQuality: AudioQuality.low))!.url, endsWith('itag=139'));
    final edl = video.edl(const PlayerSettings())!;
    expect(edl, startsWith('edl://!new_stream;!no_clip;!no_chapters;%'));
    expect(edl, contains('itag=137'));
    expect(PipedVideo.fromJson('s', {..._streams(), 'livestream': true}).edl(const PlayerSettings()), isNull);
  });

  test('normalises typed servers', () {
    expect(normalizePipedServer('pipedapi.kavin.rocks/'), 'https://pipedapi.kavin.rocks');
    expect(normalizePipedServer('http://insecure.example'), isNull);
    expect(normalizePipedServer(''), isNull);
  });

  test('ranks servers by speed and moves on from one that fails', () async {
    final asked = <String>[];
    final client = MockClient((request) async {
      final url = request.url.toString();
      asked.add(url);
      if (url == 'https://piped-instances.kavin.rocks/') {
        return http.Response(jsonEncode([
          {'api_url': 'https://slow.example', 'up_to_date': true},
          {'api_url': 'https://broken.example', 'up_to_date': true},
          {'api_url': 'https://down.example', 'up_to_date': true},
        ]), 200);
      }
      if (url.endsWith('/healthcheck')) {
        if (url.startsWith('https://down.example')) return http.Response('no', 503);
        if (url.startsWith('https://slow.example')) await Future<void>.delayed(const Duration(milliseconds: 60));
        if (PipedStreams.knownServers.any(url.startsWith)) return http.Response('no', 503);
        return http.Response('OK', 200);
      }
      if (url.startsWith('https://broken.example/streams/')) return http.Response(jsonEncode({'message': 'blocked'}), 500);
      return http.Response.bytes(utf8.encode(jsonEncode(_streams())), 200);
    });
    final piped = PipedStreams(client);
    expect(await piped.servers(), ['https://broken.example', 'https://slow.example']);
    final fetched = await piped.fetch('dQw4w9WgXcQ');
    expect(fetched.server, 'https://slow.example');
    expect(await piped.servers(), ['https://slow.example', 'https://broken.example']);
    expect(asked.where((u) => u.contains('/streams/')), ['https://broken.example/streams/dQw4w9WgXcQ', 'https://slow.example/streams/dQw4w9WgXcQ']);
  });

  test('playback source is saved, Piped by default', () {
    expect(const PlayerSettings().playbackSource, PlaybackSource.pipedAuto);
    final saved = PlayerSettings.fromJson(const PlayerSettings(playbackSource: PlaybackSource.pipedCustom, pipedServer: 'https://p.example').toJson());
    expect((saved.playbackSource, saved.pipedServer), (PlaybackSource.pipedCustom, 'https://p.example'));
  });

  test('stops asking after three failed videos in a row', () async {
    var calls = 0;
    final piped = PipedStreams(MockClient((request) async {
      calls++;
      return http.Response('down', 502);
    }));
    for (var i = 0; i < 3; i++) {
      await expectLater(piped.fetch('dQw4w9WgXcQ', server: 'https://p.example'), throwsStateError);
    }
    final before = calls;
    await expectLater(piped.fetch('dQw4w9WgXcQ', server: 'https://p.example'), throwsStateError);
    expect(calls, before);
  });

  test('reads the documentation table and the JSON status list', () {
    const table = '''
Instance Name | Instance API URL | Instance Location(s) | CDN | Registered Users
--- | --- | --- | --- | ---
kavin.rocks (Official) | https://pipedapi.kavin.rocks | 🇺🇸, 🇮🇳 | Yes | ![](https://pipedapi.kavin.rocks/registered/badge)
piped.yt | https://api.piped.yt | 🇩🇪 | No | ![](https://api.piped.yt/registered/badge)
''';
    expect(parsePipedInstanceList(table), ['https://pipedapi.kavin.rocks', 'https://api.piped.yt']);
    expect(
      parsePipedInstanceList(jsonEncode([
        {'api_url': 'https://a.example/', 'up_to_date': true},
        {'api_url': 'https://old.example', 'up_to_date': false},
        {'api_url': 'http://insecure.example'},
      ])),
      ['https://a.example'],
    );
    expect(parsePipedInstanceList('{"message": "x"}'), isEmpty);
  });

  test('keeps the downloaded list and updates it once a day', () async {
    final dir = await Directory.systemTemp.createTemp('piped');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/piped_servers.json');
    var listRequests = 0;
    PipedStreams make() => PipedStreams(MockClient((request) async {
          final url = request.url.toString();
          if (PipedStreams.instanceLists.contains(url)) {
            listRequests++;
            return http.Response('| new | https://new.example | x |', 200);
          }
          return http.Response('OK', url.startsWith('https://new.example') ? 200 : 503);
        }))
      ..catalogFile = file;

    expect(await make().servers(), ['https://new.example']);
    expect(listRequests, 2);
    final saved = jsonDecode(await file.readAsString()) as Map;
    expect(saved['servers'], ['https://new.example']);

    // A fresh list is used as it is.
    final next = make();
    expect(await next.servers(), ['https://new.example']);
    expect(listRequests, 2);
    expect(next.catalog, containsAll([...PipedStreams.knownServers, 'https://new.example']));
    expect(next.timingOf('https://new.example'), isNotNull);
    expect((next.wasTried('https://pipedapi.kavin.rocks'), next.timingOf('https://pipedapi.kavin.rocks')), (true, null));

    // A day-old one is downloaded again.
    await file.writeAsString(jsonEncode({...saved, 'updated': DateTime.now().subtract(const Duration(days: 2)).toIso8601String()}));
    await make().servers();
    // Known servers answered, so the list is downloaded in the background.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(listRequests, 4);
  });
}
