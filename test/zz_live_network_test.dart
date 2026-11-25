// ignore_for_file: avoid_print
// TEMPORARY: real requests to the relay servers and the suggestion service,
// run once in CI to check the new readers on live answers. Not to be merged.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lumtub/invidious_streams.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/piped_streams.dart';
import 'package:lumtub/player_settings.dart';
import 'package:lumtub/relay_servers.dart';
import 'package:lumtub/search_suggestions.dart';

String describe(PipedVideo v) => jsonEncode({
      'live': v.live,
      for (final (name, list) in [('video', v.video), ('audio', v.audio), ('muxed', v.muxed)])
        name: [for (final s in list) [s.url, s.codec, s.height, s.bitrate, s.videoOnly, s.mime]],
    });

void main() {
  final client = http.Client();
  test('live relay servers', () async {
    print('core loaded: ${NativeCore.instance != null}');
    for (final server in PipedStreams.knownServers) {
      final watch = Stopwatch()..start();
      try {
        final r = await client.get(Uri.parse('$server/streams/${RelayServers.probeVideo}')).timeout(const Duration(seconds: 15));
        final core = readRelayVideo(false, r.bodyBytes);
        final same = core?.video != null && r.statusCode == 200
            ? describe(PipedVideo.fromCore(server, core!.video!)) == describe(PipedVideo.fromJson(server, jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>))
            : null;
        final plays = await PipedStreams(client).plays(server).timeout(const Duration(seconds: 20)).catchError((Object e) => false);
        print('PIPED $server: HTTP ${r.statusCode} ${r.bodyBytes.length} B, core==dart: $same, '
            'video ${core?.video?.video.length} audio ${core?.video?.audio.length}, plays: $plays, ${watch.elapsedMilliseconds} ms, error: ${core?.video?.error}');
      } catch (e) {
        print('PIPED $server: failed $e');
      }
    }
    for (final server in InvidiousStreams.knownServers) {
      final watch = Stopwatch()..start();
      try {
        final r = await client.get(Uri.parse('$server/api/v1/videos/${RelayServers.probeVideo}?local=true')).timeout(const Duration(seconds: 15));
        final core = readRelayVideo(true, r.bodyBytes);
        final same = core?.video != null && r.statusCode == 200
            ? describe(invidiousVideoFromCore(server, core!.video!)) == describe(parseInvidiousVideo(server, jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>))
            : null;
        final plays = await InvidiousStreams(client).plays(server).timeout(const Duration(seconds: 20)).catchError((Object e) => false);
        print('INVIDIOUS $server: HTTP ${r.statusCode} ${r.bodyBytes.length} B, core==dart: $same, '
            'video ${core?.video?.video.length} audio ${core?.video?.audio.length}, plays: $plays, ${watch.elapsedMilliseconds} ms, error: ${core?.video?.error}');
      } catch (e) {
        print('INVIDIOUS $server: failed $e');
      }
    }
    for (final (name, relay) in [('Piped', PipedStreams(client) as RelayServers), ('Invidious', InvidiousStreams(client))]) {
      final watch = Stopwatch()..start();
      final ranked = await relay.servers();
      print('RANKED $name in ${watch.elapsedMilliseconds} ms: ${[for (final s in ranked) '$s ${relay.timingOf(s)} ms']}');
      if (ranked.isNotEmpty) {
        try {
          final video = relay is PipedStreams ? await relay.fetch('dQw4w9WgXcQ') : await (relay as InvidiousStreams).fetch('dQw4w9WgXcQ');
          print('FETCH $name ${video.server}: heights ${video.heights}, edl ${video.edl(const PlayerSettings()) != null}');
        } catch (e) {
          print('FETCH $name failed: $e');
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('live suggestions', () async {
    final uri = Uri.https('suggestqueries-clients6.youtube.com', '/complete/search', {'client': 'firefox', 'ds': 'yt', 'q': 'lofi'});
    final r = await client.get(uri);
    print('SUGGEST HTTP ${r.statusCode}: core ${SearchSuggestions.parseBytes(r.bodyBytes)} dart ${SearchSuggestions.parse(utf8.decode(r.bodyBytes, allowMalformed: true))}');
    print('SUGGEST forQuery: ${await SearchSuggestions(client).forQuery('lumtub')}');
  });
}
