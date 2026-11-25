import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/invidious_streams.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/piped_streams.dart';

/// Piped and Invidious answers read by the core
/// (native/lumtub_core/src/relay_video.rs) against the Dart that read them
/// before, on answers made at random.
void main() {
  final random = Random(5);
  T pick<T>(List<T> from) => from[random.nextInt(from.length)];
  bool sometimes([int odds = 4]) => random.nextInt(odds) > 0;

  Object? url() => pick<Object?>([
        'https://rr1---sn-abc.googlevideo.com/videoplayback?id=${random.nextInt(99)}',
        'https://pipedproxy.example/videoplayback?x=1',
        'https://server.example/videoplayback?x=2',
        'http://server.example/videoplayback?x=3',
        '/videoplayback?x=4',
        'https://evil.example/v',
        'ftp://x/y',
        '',
        null,
        5,
      ]);
  Object? number() => pick<Object?>([1080, 720, 360, 0, -1, '480', '1080p', 2.7, null, true, 4000000, '0x10', ' 144 ', 1e20]);
  String mime() => pick(['video/mp4', 'video/webm', 'audio/mp4', 'audio/webm', 'video/mp4; codecs="avc1.4d401f"', ' audio/mp4 ; x', 'text/plain', '', 'VIDEO/MP4']);
  Object? codec() => pick<Object?>(['avc1.4d401f', 'VP09.00.40.08', 'vp9', 'av01.0.08M.08', 'opus', 'mp4a.40.2', '', null]);

  Map<String, dynamic> piped() => {
        if (sometimes()) 'livestream': pick<Object?>([true, false, 'true', null]),
        if (sometimes()) 'proxyUrl': pick<Object?>(['https://pipedproxy.example', 'not a url', null, 3]),
        for (final key in ['videoStreams', 'audioStreams'])
          if (sometimes(8))
            key: [
              for (var k = random.nextInt(8); k > 0; k--)
                sometimes(10)
                    ? {
                        if (sometimes(8)) 'url': url(),
                        if (sometimes()) 'codec': codec(),
                        if (sometimes()) 'mimeType': mime(),
                        if (sometimes()) 'height': number(),
                        if (sometimes()) 'bitrate': number(),
                        if (sometimes()) 'videoOnly': pick<Object?>([true, false, 'true', null]),
                      }
                    : pick<Object?>([null, 'x', 3]),
            ],
      };

  String type() => pick([
        'video/mp4; codecs="avc1.640028"',
        'video/webm; codecs="vp9"',
        'audio/webm; codecs="opus"',
        'audio/mp4; codecs="mp4a.40.2"',
        'video/mp4; codecs=""; codecs="avc1.4d"',
        'video/mp4; codecs=av01.0.05M.08',
        'video/mp4',
        'text/vtt',
        ' video/mp4 ;codecs="avc1.42001E, mp4a.40.2"',
      ]);
  Object? size() => pick<Object?>(['1920x1080', '640x360', '0x0', '12x34x56', 'x720', '1280X720', null, 1080, '256x99999999999999999999']);
  Object? label() => pick<Object?>(['1080p60', '720p', 'audio', '', null, 360, 144.5]);

  Map<String, dynamic> invidious() => {
        if (sometimes()) 'liveNow': pick<Object?>([true, false, null]),
        if (sometimes(8))
          'adaptiveFormats': [
            for (var k = random.nextInt(8); k > 0; k--)
              {
                if (sometimes(8)) 'url': url(),
                if (sometimes(8)) 'type': type(),
                if (sometimes()) 'size': size(),
                if (sometimes()) 'qualityLabel': label(),
                if (sometimes()) 'resolution': label(),
                if (sometimes()) 'bitrate': number(),
              },
          ],
        if (sometimes(8))
          'formatStreams': [
            for (var k = random.nextInt(4); k > 0; k--)
              {
                if (sometimes(8)) 'url': url(),
                if (sometimes(8)) 'type': type(),
                if (sometimes()) 'size': size(),
                if (sometimes()) 'qualityLabel': label(),
                if (sometimes()) 'bitrate': number(),
              },
          ],
      };

  String describe(PipedVideo v) => jsonEncode({
        'live': v.live,
        for (final (name, list) in [('video', v.video), ('audio', v.audio), ('muxed', v.muxed)])
          name: [for (final s in list) [s.url, s.codec, s.height, s.bitrate, s.videoOnly, s.mime]],
      });

  const server = 'https://server.example';

  test('reads Piped answers as the Dart did', () {
    var streams = 0;
    for (var round = 0; round < 3000; round++) {
      final answer = piped();
      final body = utf8.encode(jsonEncode(answer));
      final read = readRelayVideo(false, body)!.video!;
      final dart = PipedVideo.fromJson(server, jsonDecode(utf8.decode(body)) as Map<String, dynamic>);
      expect(describe(PipedVideo.fromCore(server, read)), describe(dart), reason: jsonEncode(answer));
      streams += dart.video.length + dart.audio.length + dart.muxed.length;
    }
    expect(streams, greaterThan(1000));
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);

  test('reads Invidious answers as the Dart did', () {
    var streams = 0;
    for (var round = 0; round < 3000; round++) {
      final answer = invidious();
      final body = utf8.encode(jsonEncode(answer));
      final read = readRelayVideo(true, body)!.video!;
      final PipedVideo dart;
      try {
        dart = parseInvidiousVideo(server, jsonDecode(utf8.decode(body)) as Map<String, dynamic>);
      } on FormatException {
        continue; // A height past 64 bits stopped the Dart; the core reads none.
      }
      expect(describe(invidiousVideoFromCore(server, read)), describe(dart), reason: jsonEncode(answer));
      streams += dart.video.length + dart.audio.length + dart.muxed.length;
    }
    expect(streams, greaterThan(1000));
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);

  test('an answer that is no JSON object is unread, an error is passed on', () {
    expect(readRelayVideo(false, utf8.encode('<html>'))!.unread, isTrue);
    expect(readRelayVideo(false, utf8.encode('{"message": "Video unavailable"}'))!.video!.error, 'Video unavailable');
    expect(readRelayVideo(true, utf8.encode('{"error": "This video is private"}'))!.video!.error, 'This video is private');
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);
}
