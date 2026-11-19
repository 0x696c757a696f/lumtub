import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/player_settings.dart';
import 'package:lumtub/stream_resolver.dart';
import 'package:lumtub/video_codec.dart';

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
    final relayed = video.directAddress(relay: (url, size) => url.contains('itag=137') ? 'http://127.0.0.1:9/a' : null)!;
    expect(relayed, contains('%20%http://127.0.0.1:9/a;'));
    expect(relayed, contains(tracks[1]));
    expect(video.heights, [1080, 720]);
    expect(video.details.channelId, 'UCuAXFkgsw1L7xaCfnd5JJOw');
  });

  test('labels heights with more than 30 frames a second as YouTube does', () {
    final info = _info();
    info['formats'] = [
      {'format_id': '299', 'vcodec': 'avc1', 'height': 1080, 'fps': 60},
      {'format_id': '137', 'vcodec': 'avc1', 'height': 1080, 'fps': 30},
      {'format_id': '308', 'vcodec': 'vp9', 'height': 1440, 'fps': 50},
      {'format_id': '136', 'vcodec': 'avc1', 'height': 720, 'fps': 25},
    ];
    final video = ResolvedVideo(info, file, 'f');
    expect(video.frameRatesFor(const PlayerSettings(disabledCodecs: {})), {1440: 50, 1080: 60});
    expect(video.frameRatesFor(const PlayerSettings(disabledCodecs: {VideoCodec.vp9})), {1080: 60});
    expect([for (final h in video.heightsFor(const PlayerSettings(disabledCodecs: {}))) heightLabel(h, video.frameRatesFor(const PlayerSettings(disabledCodecs: {}))[h])], ['1440p50', '1080p60', '720p']);
    expect(heightLabel(1080, 29.97, 'P'), '1080P');
    expect(heightLabel(2160, 59.94, 'P'), '2160P60');
  });

  test('a portrait video goes by its width, as YouTube names it', () {
    expect(heightLabel(1920, 30, 'P', 1080 / 1920), '1080P');
    expect(heightLabel(1280, 60, 'P', 720 / 1280), '720P60');
    expect(heightLabel(1918, null, 'p', 1080 / 1918), '1080p');
    expect(heightLabel(1080, null, 'p', 16 / 9), '1080p');
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
    final dir = await Directory.systemTemp.createTemp('lumtub_resolve');
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
    expect(resolver.arguments('dQw4w9WgXcQ', 'bestvideo+bestaudio', formatSort: 'res,fps,vcodec:vp9'), containsAllInOrder(['--format', 'bestvideo+bestaudio', '--format-sort', 'res,fps,vcodec:vp9']));
    resolver.forget('dQw4w9WgXcQ');
    await resolver.resolve('dQw4w9WgXcQ', 'ytdl');
    expect(count.readAsLinesSync(), hasLength(2));
  });

  test('a failed video is not prefetched again for a while, and a bot check pauses prefetching', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('lumtub_resolve');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('${dir.path}/fake-yt-dlp');
    await script.writeAsString('#!/bin/sh\nfor last; do :; done\n'
        'case "\$last" in *aaaaaaaaaaa) echo "ERROR: [youtube] aaaaaaaaaaa: Private video" >&2; exit 1;; '
        '*bbbbbbbbbbb) echo "ERROR: [youtube] bbbbbbbbbbb: Sign in to confirm you\'re not a bot" >&2; exit 1;; esac\n'
        'cat <<\'JSON\'\n${jsonEncode(_info())}\nJSON\n');
    await Process.run('chmod', ['+x', script.path]);
    final resolver = StreamResolver(script.path, infoDirectory: Directory('${dir.path}/info'));
    await expectLater(resolver.resolve('aaaaaaaaaaa', 'ytdl'), throwsA(anything));
    await Future<void>.delayed(Duration.zero);
    expect(resolver.prefetchAllowed('aaaaaaaaaaa'), isFalse);
    expect(resolver.prefetchAllowed('ccccccccccc'), isTrue);
    await expectLater(resolver.resolve('bbbbbbbbbbb', 'ytdl'), throwsA(anything));
    await Future<void>.delayed(Duration.zero);
    expect(resolver.prefetchAllowed('ccccccccccc'), isFalse);
    // Opening a video still resolves it, and an answer lifts the pause.
    await resolver.resolve('ccccccccccc', 'ytdl');
    await Future<void>.delayed(Duration.zero);
    expect(resolver.prefetchAllowed('ddddddddddd'), isTrue);
    expect(resolver.prefetchAllowed('aaaaaaaaaaa'), isFalse);
  });

  test('a standby yt-dlp started ahead reads the next video from stdin', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('lumtub_resolve');
    addTearDown(() => dir.delete(recursive: true));
    final log = File('${dir.path}/log');
    final script = File('${dir.path}/fake-yt-dlp');
    await script.writeAsString('#!/bin/sh\nfor last; do :; done\nif [ "\$last" = "-" ]; then echo standby >> ${log.path}; read url; echo "read \$url" >> ${log.path}; else echo "run \$last" >> ${log.path}; fi\n'
        'cat <<\'JSON\'\n${jsonEncode(_info())}\nJSON\n');
    await Process.run('chmod', ['+x', script.path]);
    final resolver = StreamResolver(script.path, infoDirectory: Directory('${dir.path}/info'))..standbyEnabled = true;
    expect(resolver.standbyArguments('ytdl', null).sublist(resolver.standbyArguments('ytdl', null).length - 2), ['--batch-file', '-']);
    await resolver.resolve('aaaaaaaaaaa', 'ytdl');
    for (var i = 0; i < 50 && !(log.existsSync() && log.readAsLinesSync().contains('standby')); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final second = await resolver.resolve('bbbbbbbbbbb', 'ytdl');
    expect(second.info['title'], 'Never Gonna Give You Up');
    expect(log.readAsLinesSync().take(3), ['run https://www.youtube.com/watch?v=aaaaaaaaaaa', 'standby', 'read https://www.youtube.com/watch?v=bbbbbbbbbbb']);
    // Another format needs other arguments: it runs on its own.
    await resolver.resolve('ccccccccccc', 'bestvideo');
    expect(log.readAsLinesSync(), contains('run https://www.youtube.com/watch?v=ccccccccccc'));
  });

  test('prefetches one video at a time, then only the last one asked for', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('lumtub_resolve');
    addTearDown(() => dir.delete(recursive: true));
    final log = File('${dir.path}/log');
    final script = File('${dir.path}/fake-yt-dlp');
    await script.writeAsString('#!/bin/sh\nfor last; do :; done\necho "\$last" >> ${log.path}\nsleep 0.3\ncat <<\'JSON\'\n${jsonEncode(_info())}\nJSON\n');
    await Process.run('chmod', ['+x', script.path]);
    final resolver = StreamResolver(script.path, infoDirectory: Directory('${dir.path}/info'));
    for (final id in ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']) {
      resolver.prefetch(id, 'ytdl');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(log.readAsLinesSync(), hasLength(1));
    await resolver.resolve('ccccccccccc', 'ytdl');
    expect(log.readAsLinesSync().map((line) => line.substring(line.length - 11)), ['aaaaaaaaaaa', 'ccccccccccc']);
  });

  test('asks again signed in for a members-only video, and wipes the cookies', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('lumtub_resolve');
    addTearDown(() => dir.delete(recursive: true));
    final log = File('${dir.path}/log');
    final script = File('${dir.path}/fake-yt-dlp');
    await script.writeAsString('#!/bin/sh\n'
        'cookies=""\nwhile [ \$# -gt 0 ]; do [ "\$1" = --cookies ] && cookies="\$2"; shift; done\n'
        'if [ -z "\$cookies" ]; then echo none >> ${log.path}; echo "ERROR: [youtube] x: Join this channel to get access to members-only content like this video" >&2; exit 1; fi\n'
        'cat "\$cookies" >> ${log.path}\n'
        'cat <<\'JSON\'\n${jsonEncode(_info())}\nJSON\n');
    await Process.run('chmod', ['+x', script.path]);
    final cookies = _FakeCookies();
    final resolver = StreamResolver(script.path, infoDirectory: Directory('${dir.path}/info'))..members = () => cookies;
    await resolver.resolve('dQw4w9WgXcQ', 'ytdl');
    expect(log.readAsLinesSync(), ['none', 'SAPISID=x']);
    expect(cookies.written, hasLength(1));
    expect(cookies.wiped, cookies.written);
    expect(File(cookies.written.single).existsSync(), isFalse);
    // A list that marked it asks signed in at once.
    await log.writeAsString('');
    resolver.forget('dQw4w9WgXcQ');
    await resolver.resolve('dQw4w9WgXcQ', 'ytdl', membersOnly: true);
    expect(log.readAsLinesSync(), ['SAPISID=x']);
    // Signed out, the error stands and nothing is written.
    cookies.signedIn = false;
    resolver.forget('dQw4w9WgXcQ');
    await expectLater(resolver.resolve('dQw4w9WgXcQ', 'ytdl'), throwsA(isA<StateError>()));
    expect(cookies.written, hasLength(2));
    // Background prefetches never open the cookies.
    cookies.signedIn = true;
    resolver.prefetch('aaaaaaaaaaa', 'ytdl');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(cookies.written, hasLength(2));
  });

  test('a failed resolution is not kept', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('lumtub_resolve');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('${dir.path}/fake-yt-dlp');
    await script.writeAsString('#!/bin/sh\necho "ERROR: Sign in to confirm" >&2\nexit 1\n');
    await Process.run('chmod', ['+x', script.path]);
    final resolver = StreamResolver(script.path, infoDirectory: Directory('${dir.path}/info'));
    await expectLater(resolver.resolve('dQw4w9WgXcQ', 'ytdl'), throwsA(isA<StateError>()));
    await expectLater(resolver.resolve('dQw4w9WgXcQ', 'ytdl'), throwsA(isA<StateError>()));
  });

  test('a live stream is also asked as the clients a phone can play', () {
    final resolver = StreamResolver('yt-dlp', infoDirectory: Directory('x'))..liveClients = 'default,android_vr';
    expect(resolver.arguments('dQw4w9WgXcQ', 'ytdl', live: true), containsAllInOrder(['--extractor-args', 'youtube:formats=incomplete;player_client=default,android_vr']));
    expect(resolver.arguments('dQw4w9WgXcQ', 'ytdl').join(' '), isNot(contains('android_vr')));
    resolver.liveClients = null;
    expect(resolver.arguments('dQw4w9WgXcQ', 'ytdl', live: true), containsAllInOrder(['--extractor-args', 'youtube:formats=incomplete']));
  });

  test('leaves out the TV clients unless a run without them failed', () {
    final resolver = StreamResolver('yt-dlp', infoDirectory: Directory('x'));
    expect(resolver.avoidingTv, isTrue);
    expect(resolver.arguments('dQw4w9WgXcQ', 'ytdl'), containsAllInOrder(['--extractor-args', StreamResolver.visionOnly]));
    expect(resolver.arguments('dQw4w9WgXcQ', 'ytdl', cookies: 'c.txt').join(' '), isNot(contains('visionos')), reason: 'signed in keeps its clients');
    expect(resolver.arguments('dQw4w9WgXcQ', 'ytdl', live: true).join(' '), isNot(contains('visionos')), reason: 'live streams keep their own clients');
  });

  test('a video taken for a bot is asked again over the other address family, which is kept', () async {
    final dir = await Directory.systemTemp.createTemp('lumtub_resolve');
    addTearDown(() => dir.delete(recursive: true));
    addTearDown(() => ProcessTree.switchFamily(null));
    final log = File('${dir.path}/log');
    final script = File('${dir.path}/yt-dlp');
    await script.writeAsString('#!/bin/sh\necho "\$*" >> ${log.path}\ncase "\$*" in *--force-ipv4*) ;; *) echo "ERROR: [youtube] dQw4w9WgXcQ: Sign in to confirm you\'re not a bot" >&2; exit 1;; esac\n'
        'cat <<\'JSON\'\n${jsonEncode(_info())}\nJSON\n');
    await Process.run('chmod', ['+x', script.path]);
    var both = false;
    final resolver = StreamResolver(script.path, infoDirectory: Directory('${dir.path}/info'))..bothFamilies = (() => both);
    await expectLater(resolver.resolve('dQw4w9WgXcQ', 'ytdl'), throwsA(isA<StateError>()), reason: 'one family only: nothing to switch to');
    expect(log.readAsLinesSync().where((l) => l.contains('--force-ipv4')), isEmpty);
    both = true;
    resolver.forget('dQw4w9WgXcQ');
    final video = await resolver.resolve('dQw4w9WgXcQ', 'ytdl');
    expect(video.info['id'], 'dQw4w9WgXcQ');
    expect(ProcessTree.switchedFamily, '4');
    expect(ProcessTree.familyArguments, ['--force-ipv4']);
    ProcessTree.switchFamily(null);
    expect(ProcessTree.familyArguments, isEmpty);
  }, skip: Platform.isWindows ? 'uses a shell script' : null);

  test('asks again signed in when taken for a bot only with the setting on, in the foreground', () async {
    final dir = await Directory.systemTemp.createTemp('lumtub_resolve');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('${dir.path}/fake-yt-dlp');
    await script.writeAsString('#!/bin/sh\n'
        'case "\$*" in *--cookies*) ;; *) echo "ERROR: [youtube] dQw4w9WgXcQ: Sign in to confirm you\'re not a bot" >&2; exit 1;; esac\n'
        'cat <<\'JSON\'\n${jsonEncode(_info())}\nJSON\n');
    await Process.run('chmod', ['+x', script.path]);
    final cookies = _FakeCookies();
    var on = false;
    final played = <String>[];
    final resolver = StreamResolver(script.path, infoDirectory: Directory('${dir.path}/info'))
      ..members = (() => cookies)
      ..signInWhenBlocked = (() => on)
      ..onSignedInPlay = played.add;
    await expectLater(resolver.resolve('dQw4w9WgXcQ', 'ytdl'), throwsA(isA<StateError>()));
    expect(cookies.written, isEmpty, reason: 'off by default');
    on = true;
    resolver.forget('dQw4w9WgXcQ');
    final video = await resolver.resolve('dQw4w9WgXcQ', 'ytdl');
    expect(video.info['id'], 'dQw4w9WgXcQ');
    expect(cookies.written, hasLength(1));
    expect(cookies.wiped, cookies.written);
    expect(played, ['dQw4w9WgXcQ']);
    resolver.prefetch('aaaaaaaaaaa', 'ytdl');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(cookies.written, hasLength(1), reason: 'prefetches never use the account');
  }, skip: Platform.isWindows ? 'uses a shell script' : null);

  test('a run without the TV clients that fails asks with them again', () async {
    final dir = await Directory.systemTemp.createTemp('lumtub_resolve');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('${dir.path}/fake-yt-dlp');
    await script.writeAsString('#!/bin/sh\ncase "\$*" in *player_client=visionos*) echo "ERROR: [youtube] dQw4w9WgXcQ: Sign in to confirm you are not a bot" >&2; exit 1;; esac\necho \'{"id":"dQw4w9WgXcQ","formats":[]}\'\n');
    await Process.run('chmod', ['+x', script.path]);
    final resolver = StreamResolver(script.path, infoDirectory: Directory('${dir.path}/info'));
    final video = await resolver.resolve('dQw4w9WgXcQ', 'ytdl');
    expect(video.info['id'], 'dQw4w9WgXcQ');
    expect(resolver.avoidingTv, isFalse);
    expect(resolver.arguments('dQw4w9WgXcQ', 'ytdl').join(' '), isNot(contains('visionos')));
    resolver.avoidTv();
    expect(resolver.avoidingTv, isTrue, reason: 'refused TV addresses leave it out again');
  }, skip: Platform.isWindows ? 'uses a shell script' : null);

  test('visionOS addresses refused past 1 MiB turn quick starts off and bring the TV clients back', () async {
    final resolver = StreamResolver('yt-dlp', infoDirectory: Directory('x'));
    final asked = <http.Request>[];
    resolver.quickClient = MockClient((request) async {
      asked.add(request);
      return http.Response('', 403);
    });
    final info = {
      'requested_formats': [
        {'url': 'https://r1.googlevideo.com/videoplayback?itag=137&c=VISIONOS', 'filesize': 9000000, 'http_headers': {'User-Agent': 'UA/1'}},
        {'url': 'https://r1.googlevideo.com/videoplayback?itag=140&c=VISIONOS', 'filesize': 3000000},
      ],
    };
    await resolver.checkVisionCut(info);
    expect(asked.single.url.queryParameters['range'], '1048576-1052671');
    expect(asked.single.url.queryParameters['itag'], '137');
    expect(asked.single.headers['User-Agent'], 'UA/1');
    expect(resolver.visionCut, isTrue);
    expect(resolver.avoidingTv, isFalse);
    expect(resolver.arguments('dQw4w9WgXcQ', 'ytdl').join(' '), isNot(contains('visionos')));
    resolver.avoidTv();
    expect(resolver.avoidingTv, isFalse, reason: 'visionOS alone would stop after 1 MiB');
    expect(await resolver.quick('dQw4w9WgXcQ', 'ytdl', '{}'), isNull);

    await resolver.checkVisionCut(info);
    expect(asked, hasLength(1), reason: 'looked at once per half hour');
  });

  test('visionOS addresses that play on are left alone; small files are not looked at', () async {
    final resolver = StreamResolver('yt-dlp', infoDirectory: Directory('x'));
    final asked = <http.Request>[];
    resolver.quickClient = MockClient((request) async {
      asked.add(request);
      return http.Response('', 206);
    });
    await resolver.checkVisionCut({'requested_formats': [{'url': 'https://r1.googlevideo.com/videoplayback?itag=18', 'filesize': 500000}]});
    expect(asked, isEmpty);
    await resolver.checkVisionCut({'requested_formats': [{'url': 'https://r1.googlevideo.com/videoplayback?itag=137', 'filesize': 9000000}]});
    expect(asked, hasLength(1));
    expect(resolver.visionCut, isFalse);
    expect(resolver.avoidingTv, isTrue);
  });

  test('points yt-dlp at Deno and retries a network error once', () async {
    expect(StreamResolver('yt-dlp', deno: r'C:\tools\deno.exe', infoDirectory: Directory('x')).arguments('dQw4w9WgXcQ', 'ytdl'),
        containsAllInOrder(['--js-runtimes', r'deno:C:\tools\deno.exe']));
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('lumtub_resolve');
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

  test('resolves again when the format differs from the cached one', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('lumtub_resolve');
    addTearDown(() => dir.delete(recursive: true));
    final count = File('${dir.path}/count');
    final script = File('${dir.path}/fake-yt-dlp');
    await script.writeAsString('#!/bin/sh\necho x >> ${count.path}\ncat <<\'JSON\'\n${jsonEncode(_info())}\nJSON\n');
    await Process.run('chmod', ['+x', script.path]);
    final resolver = StreamResolver(script.path, infoDirectory: Directory('${dir.path}/info'));
    final first = await resolver.resolve('dQw4w9WgXcQ', 'best[height<=720]');
    expect(first.format, 'best[height<=720]');
    expect(identical(await resolver.resolve('dQw4w9WgXcQ', 'best[height<=720]'), first), isTrue);
    final second = await resolver.resolve('dQw4w9WgXcQ', 'bestvideo+bestaudio');
    expect(second.format, 'bestvideo+bestaudio');
    expect(count.readAsLinesSync(), hasLength(2));
    // A prefetch for the cached format is skipped, one for another is not.
    resolver.prefetch('dQw4w9WgXcQ', 'bestvideo+bestaudio');
    resolver.prefetch('dQw4w9WgXcQ', 'ytdl');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(count.readAsLinesSync(), hasLength(3));
    expect((await resolver.cached('dQw4w9WgXcQ'))!.format, 'ytdl');
  });

  test('deletes the info file of a forgotten or evicted video, and of old runs', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('lumtub_resolve');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('${dir.path}/fake-yt-dlp');
    await script.writeAsString('#!/bin/sh\ncat <<\'JSON\'\n${jsonEncode(_info())}\nJSON\n');
    await Process.run('chmod', ['+x', script.path]);
    final info = Directory('${dir.path}/info')..createSync();
    final old = File('${info.path}/oldoldoldol.json')..writeAsStringSync('{}');
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
    final recent = File('${info.path}/recentrecen.json')..writeAsStringSync('{}');
    final resolver = StreamResolver(script.path, infoDirectory: info);
    await resolver.deleteStaleInfo();
    expect(old.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue);

    final ids = [for (var i = 0; i < 6; i++) 'video${i.toString().padLeft(6, '0')}'];
    for (final id in ids) {
      await resolver.resolve(id, 'ytdl');
    }
    // Only the 4 kept entries still have a file.
    for (final id in ids) {
      expect(File('${info.path}/$id.json').existsSync(), ids.indexOf(id) >= 2, reason: id);
    }
    // Background extractions never push out the video asked for last.
    final hovered = [for (var i = 0; i < 6; i++) 'hover${i.toString().padLeft(6, '0')}'];
    for (final id in hovered) {
      resolver.prefetch(id, 'ytdl');
      await resolver.cached(id);
      await Future<void>.delayed(Duration.zero);
    }
    expect(resolver.cached(ids.last), isNotNull);
    expect(File('${info.path}/${ids.last}.json').existsSync(), isTrue);
    expect(File('${info.path}/${ids[4]}.json').existsSync(), isFalse);
    // Going to the background with nothing playing keeps only that one.
    resolver.trim();
    expect([for (final id in hovered) resolver.cached(id)], everyElement(isNull));
    expect(resolver.cached(ids.last), isNotNull);
    resolver.forget(ids.last);
    expect(File('${info.path}/${ids.last}.json').existsSync(), isFalse);
  });
}

class _FakeCookies implements MembersCookies {
  @override
  bool signedIn = true;
  final written = <String>[];
  final wiped = <String>[];

  @override
  Future<bool> writeCookies(String path) async {
    written.add(path);
    await File(path).writeAsString('SAPISID=x\n');
    return true;
  }

  @override
  void wipeCookies(String path) {
    wiped.add(path);
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
}
