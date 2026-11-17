import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/youtube_player_probe.dart';

const _page = '<script>ytcfg.set({"VISITOR_DATA":"CgtTaGFyZWQxMjM"})</script>';
const _refusal = '{"responseContext":{"visitorData":"CgtGcmVzaDQ1Ng%3D%3D"},"playabilityStatus":{"status":"LOGIN_REQUIRED","reason":"Sign in to confirm you’re not a bot"}}';
const _playable = '{"playabilityStatus":{"status":"OK"},"videoDetails":{"videoId":"aaaaaaaaaaa"}}';

Map<String, String> _headers() => {'Content-Type': 'application/json'};
Map<String, Object?> _body() => {
      'context': {
        'client': {'clientName': 'VISIONOS', 'clientVersion': '1.02'},
      },
      'videoId': 'aaaaaaaaaaa',
    };

void main() {
  setUp(() {
    YoutubePlayerProbe.forgetVisitor();
    YoutubePlayerProbe.resetTraffic();
  });

  test('a start refused as the shared visitor asks again at once as the one the refusal names, and keeps it', () async {
    final visitors = <String?>[];
    final client = MockClient((request) async {
      if (request.method == 'GET') return http.Response(_page, 200);
      final visitor = request.headers['X-Goog-Visitor-Id'];
      visitors.add(visitor);
      return http.Response.bytes(utf8.encode(visitor == 'CgtTaGFyZWQxMjM' ? _refusal : _playable), 200);
    });
    final first = await YoutubePlayerProbe.post(client, _headers(), _body(), playing: true);
    expect(utf8.decode(first.bodyBytes), _playable);
    expect(visitors, ['CgtTaGFyZWQxMjM', 'CgtGcmVzaDQ1Ng%3D%3D']);
    visitors.clear();
    await YoutubePlayerProbe.post(client, _headers(), _body(), playing: true);
    expect(visitors, ['CgtGcmVzaDQ1Ng%3D%3D'], reason: 'playback keeps its own visitor');
    visitors.clear();
    YoutubePlayerProbe.resetTraffic();
    await YoutubePlayerProbe.post(client, _headers(), _body());
    expect(visitors, ['CgtTaGFyZWQxMjM'], reason: 'lookups for lists stay the shared visitor');
  });

  test('lookups for lists wait while a video starts', () async {
    final order = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'GET') return http.Response(_page, 200);
      final playing = request.headers['X-Test'] == 'play';
      order.add(playing ? 'play' : 'list');
      if (playing) await Future<void>.delayed(const Duration(milliseconds: 300));
      return http.Response(_playable, 200);
    });
    final play = YoutubePlayerProbe.post(client, {..._headers(), 'X-Test': 'play'}, _body(), playing: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final watch = Stopwatch()..start();
    await YoutubePlayerProbe.post(client, _headers(), _body());
    await play;
    expect(order, ['play', 'list']);
    expect(watch.elapsed, greaterThanOrEqualTo(YoutubePlayerProbe.afterPlayback));
  });

  test('lookups for lists rest after YouTube took several in a row for a bot\'s', () async {
    var posts = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET') return http.Response(_page, 200);
      posts++;
      return http.Response.bytes(utf8.encode(_refusal), 200);
    });
    for (var i = 0; i < YoutubePlayerProbe.refusalsBeforeRest; i++) {
      await YoutubePlayerProbe.post(client, _headers(), _body());
    }
    expect(posts, YoutubePlayerProbe.refusalsBeforeRest);
    final resting = await YoutubePlayerProbe.post(client, _headers(), _body());
    expect(resting.statusCode, 429);
    expect(posts, YoutubePlayerProbe.refusalsBeforeRest, reason: 'nothing more is asked while resting');
    await YoutubePlayerProbe.post(client, _headers(), _body(), playing: true);
    expect(posts, greaterThan(YoutubePlayerProbe.refusalsBeforeRest), reason: 'a start still asks');
  });
}
