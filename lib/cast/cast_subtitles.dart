import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../subtitle_cues.dart';

/// The subtitles cast with a video: one line, or two when a second
/// subtitle was on, served as WebVTT (Chromecast) and SRT (DLNA).
class CastSubtitles {
  const CastSubtitles({required this.vtt, required this.srt, this.language});
  final String vtt;
  final String srt;
  final String? language;
}

/// The lines cast for one subtitle, or two shown together: each line of
/// [main] with what [second] says meanwhile above it, as the player shows
/// them. With [main] empty, [second] alone.
List<SubtitleCue> castSubtitleLines(List<SubtitleCue> main, List<SubtitleCue> second) {
  if (main.isEmpty) return second;
  if (second.isEmpty) return main;
  return [
    for (final row in pairSubtitleCues(main, second))
      (start: row.cue.start, end: row.cue.end, text: row.second == null || row.second!.isEmpty ? row.cue.text : '${row.second}\n${row.cue.text}'),
  ];
}

/// [cues] as they fall in a stream that begins [offset] into the video:
/// earlier lines are left out and one under way starts at zero.
List<SubtitleCue> cuesFrom(List<SubtitleCue> cues, Duration offset) {
  if (offset <= Duration.zero) return cues;
  return [
    for (final cue in cues)
      if (cue.end > offset) (start: cue.start > offset ? cue.start - offset : Duration.zero, end: cue.end - offset, text: cue.text),
  ];
}

/// [cues] as a WebVTT file.
String toVtt(List<SubtitleCue> cues) {
  String stamp(Duration d) {
    String two(int n, [int width = 2]) => n.toString().padLeft(width, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}.${two(d.inMilliseconds % 1000, 3)}';
  }

  final out = StringBuffer('WEBVTT\n\n');
  for (final cue in cues) {
    out
      ..writeln('${stamp(cue.start)} --> ${stamp(cue.end)}')
      ..writeln(cue.text.replaceAll('-->', '->'))
      ..writeln();
  }
  return out.toString();
}

/// Serves the subtitles of what is cast on this PC's network address. The
/// TV asks for them itself; Chromecast's receiver needs CORS to read them,
/// so any page may, but only given the unguessable address.
class CastSubtitleServer {
  CastSubtitleServer._();
  static final instance = CastSubtitleServer._();

  HttpServer? _server;
  final _files = <String, ({String type, List<int> body})>{};
  var _serial = 0;

  /// Registers [cues] for a stream beginning [offset] into the video and
  /// returns their addresses as seen from [host]. Only the newest few are
  /// kept.
  Future<CastSubtitles> register(List<SubtitleCue> cues, {required String host, Duration offset = Duration.zero, String? language}) async {
    var server = _server;
    if (server == null) {
      server = _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      server.listen(_answer);
    }
    final lines = cuesFrom(cues, offset);
    // A random path part, so another device on the network cannot guess the address.
    final random = Random.secure();
    final token = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final name = '$token/sub${++_serial}';
    _files['/$name.vtt'] = (type: 'text/vtt; charset=utf-8', body: utf8.encode(toVtt(lines)));
    _files['/$name.srt'] = (type: 'application/x-subrip; charset=utf-8', body: utf8.encode(toSrt(lines)));
    while (_files.length > 8) {
      _files.remove(_files.keys.first);
    }
    final base = 'http://$host:${server.port}/$name';
    return CastSubtitles(vtt: '$base.vtt', srt: '$base.srt', language: language);
  }

  void _answer(HttpRequest request) {
    final response = request.response;
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS')
      ..set('Access-Control-Allow-Headers', '*');
    final file = _files[request.uri.path];
    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
    } else if (file == null || (request.method != 'GET' && request.method != 'HEAD')) {
      response.statusCode = HttpStatus.notFound;
    } else {
      response.headers
        ..contentType = ContentType.parse(file.type)
        ..contentLength = file.body.length;
      if (request.method == 'GET') response.add(file.body);
    }
    unawaited(response.close().catchError((Object _) {}));
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
    _files.clear();
  }
}
