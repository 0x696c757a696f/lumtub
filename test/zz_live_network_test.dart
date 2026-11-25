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
  Future<void> media(String url) async {
    try {
      final request = http.Request('GET', Uri.parse(url))..headers['Range'] = 'bytes=0-1023';
      final response = await client.send(request).timeout(const Duration(seconds: 15));
      final bytes = await response.stream.take(1).fold<int>(0, (a, b) => a + b.length).timeout(const Duration(seconds: 15));
      print('MEDIA ${Uri.parse(url).host}: HTTP ${response.statusCode}, first chunk $bytes B');
    } catch (e) {
      print('MEDIA ${Uri.parse(url).host}: failed $e');
    }
  }

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
        try {
          final raw = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
          final vs = (raw['videoStreams'] as List?) ?? const [];
          final as = (raw['audioStreams'] as List?) ?? const [];
          print('PIPED RAW $server: proxyUrl ${raw['proxyUrl']} videoStreams ${vs.length} audioStreams ${as.length} first ${vs.isEmpty ? '' : (vs.first as Map)['url']} ${as.isEmpty ? '' : (as.first as Map)['url']}');
          final audio = core?.video?.audio ?? const [];
          if (audio.isNotEmpty) await media(audio.first[0] as String);
        } catch (e) {
          print('PIPED RAW $server: $e');
        }
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
        if (core?.video case final v?) {
          final video = invidiousVideoFromCore(server, v);
          print('INVIDIOUS RAW $server: rows audio ${v.audio.map((r) => r[0]).take(2).toList()} kept audio ${video.audio.map((s) => s.url).take(2).toList()}');
          if (video.audio.isNotEmpty) await media(video.audio.first.url);
        }
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
    final uri = Uri.https('suggestqueries-clients6.youtube.com', '/complete/search', {'client': 'firefox', 'ds': 'yt', 'hl': 'en', 'ie': 'utf-8', 'oe': 'utf-8', 'q': 'lofi'});
    final r = await client.get(uri);
    print('SUGGEST body ${r.body.length > 300 ? r.body.substring(0, 300) : r.body}');
    print('SUGGEST HTTP ${r.statusCode}: core ${SearchSuggestions.parseBytes(r.bodyBytes)} dart ${SearchSuggestions.parse(utf8.decode(r.bodyBytes, allowMalformed: true))}');
    print('SUGGEST forQuery: ${await SearchSuggestions(client).forQuery('lumtub')}');
  });
}
