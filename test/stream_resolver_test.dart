import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/stream_resolver.dart';

Map<String, dynamic> _info({int? expire}) {
  final exp = expire ?? DateTime.now().add(const Duration(hours: 6)).millisecondsSinceEpoch ~/ 1000;
  return {
    'id': 'dQw4w9WgXcQ',
    'title': 'Never Gonna Give You Up',
    'channel': 'Rick Astley',
    'channel_id': 'UCuAXFkgsw1L7xaCfnd5JJOw',
    'formats': [
      {'format_id': '137', 'vcodec': 'avc1', 'height': 1080},
      {'format_id': '136', 'vcodec': 'avc1', 'height': 720},
      {'format_id': '248', 'vcodec': 'vp9', 'height': 1080},
      {'format_id': '140', 'vcodec': 'none', 'acodec': 'mp4a'},
    ],
    'requested_formats': [
      {'url': 'https://r1.googlevideo.com/videoplayback?expire=$exp&itag=137', 'protocol': 'https', 'vcodec': 'avc1', 'http_headers': {'User-Agent': 'UA/1'}},
      {'url': 'https://r1.googlevideo.com/videoplayback?expire=$exp&itag=140&ü', 'protocol': 'https', 'acodec': 'mp4a'},
    ],
  };
}

void main() {
  final file = File('info.json');

  test('builds the EDL address mpv\'s ytdl_hook would', () {
    final video = ResolvedVideo(_info(), file, 'f');
    final tracks = (video.info['requested_formats'] as List).map((t) => t['url'] as String).toList();
    expect(
      video.directUrl,
      'edl://!new_stream;!no_clip;!no_chapters;%${tracks[0].length}%${tracks[0]};'
      '!new_stream;!no_clip;!no_chapters;%${utf8.encode(tracks[1]).length}%${tracks[1]}',
    );
    expect(video.userAgent, 'UA/1');
    expect(video.heights, [1080, 720]);
    expect(video.details.channelId, 'UCuAXFkgsw1L7xaCfnd5JJOw');
  });

  test('leaves live and fragmented streams to ytdl_hook', () {
    expect(ResolvedVideo({..._info(), 'is_live': true}, file, 'f').directUrl, isNull);
    final fragmented = _info();
    (fragmented['requested_formats'] as List)[0]['fragments'] = [{'url': 'x'}];
    expect(ResolvedVideo(fragmented, file, 'f').directUrl, isNull);
    final hls = _info();
    (hls['requested_formats'] as List)[0]['protocol'] = 'm3u8_native';
    expect(ResolvedVideo(hls, file, 'f').directUrl, isNull);
  });

  test('is used well before its addresses expire', () {
    final soon = DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000;
    expect(ResolvedVideo(_info(expire: soon), file, 'f').fresh, isFalse);
    expect(ResolvedVideo(_info(), file, 'f').fresh, isTrue);
    expect(ResolvedVideo(_info(), file, 'f', now: DateTime.now().subtract(const Duration(hours: 2))).fresh, isFalse);
  });

  test('runs yt-dlp once per video and saves the info file', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('ytplus_resolve');
    addTearDown(() => dir.delete(recursive: true));
    final count = File('${dir.path}/count');
    final script = File('${dir.path}/fake-yt-dlp');
    await script.writeAsString('#!/bin/sh\necho x >> ${count.path}\nsleep 0.2\ncat <<\'JSON\'\n${jsonEncode(_info())}\nJSON\n');
    await Process.run('chmod', ['+x', script.path]);
    final resolver = StreamResolver(script.path, infoDirectory: Directory('${dir.path}/info'));
    resolver.prefetch('dQw4w9WgXcQ', 'ytdl');
    final videos = await Future.wait([resolver.resolve('dQw4w9WgXcQ', 'ytdl'), resolver.resolve('dQw4w9WgXcQ', 'ytdl')]);
    expect(identical(videos[0], videos[1]), isTrue);
    expect(count.readAsLinesSync(), hasLength(1));
    expect(jsonDecode(videos[0].file.readAsStringSync())['title'], 'Never Gonna Give You Up');
    expect(resolver.arguments('dQw4w9WgXcQ', 'ytdl'), containsAllInOrder(['--format', 'bestvideo+bestaudio/best', '--', 'https://www.youtube.com/watch?v=dQw4w9WgXcQ']));
    resolver.forget('dQw4w9WgXcQ');
    await resolver.resolve('dQw4w9WgXcQ', 'ytdl');
    expect(count.readAsLinesSync(), hasLength(2));
  });

  test('a failed resolution is not kept', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('ytplus_resolve');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('${dir.path}/fake-yt-dlp');
    await script.writeAsString('#!/bin/sh\necho "ERROR: Sign in to confirm" >&2\nexit 1\n');
    await Process.run('chmod', ['+x', script.path]);
    final resolver = StreamResolver(script.path, infoDirectory: Directory('${dir.path}/info'));
    await expectLater(resolver.resolve('dQw4w9WgXcQ', 'ytdl'), throwsA(isA<StateError>()));
    await expectLater(resolver.resolve('dQw4w9WgXcQ', 'ytdl'), throwsA(isA<StateError>()));
  });

  test('points yt-dlp at Deno and retries a network error once', () async {
    expect(StreamResolver('yt-dlp', deno: r'C:\tools\deno.exe', infoDirectory: Directory('x')).arguments('dQw4w9WgXcQ', 'ytdl'),
        containsAllInOrder(['--js-runtimes', r'deno:C:\tools\deno.exe']));
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('ytplus_resolve');
    addTearDown(() => dir.delete(recursive: true));
    final count = File('${dir.path}/count');
    final script = File('${dir.path}/fake-yt-dlp');
    await script.writeAsString('#!/bin/sh\necho x >> ${count.path}\n'
        'if [ \$(wc -l < ${count.path}) -eq 1 ]; then echo "ERROR: HTTP Error 503: Service Unavailable" >&2; exit 1; fi\n'
        'echo "WARNING: n challenge solving failed" >&2\n'
        'cat <<\'JSON\'\n${jsonEncode(_info())}\nJSON\n');
    await Process.run('chmod', ['+x', script.path]);
    final video = await StreamResolver(script.path, infoDirectory: Directory('${dir.path}/info')).resolve('dQw4w9WgXcQ', 'ytdl');
    expect(video.info['title'], 'Never Gonna Give You Up');
    expect(count.readAsLinesSync(), hasLength(2));
  });
}
