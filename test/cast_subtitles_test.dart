import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/cast/cast_subtitles.dart';
import 'package:lumtub/cast/dlna.dart';
import 'package:lumtub/subtitle_cues.dart';

SubtitleCue _cue(int start, int end, String text) => (start: Duration(seconds: start), end: Duration(seconds: end), text: text);

void main() {
  test('two subtitles are cast as one, the second above the first', () {
    final lines = castSubtitleLines([_cue(1, 3, 'Ciao a tutti'), _cue(4, 6, 'Oggi cuciniamo')], [_cue(1, 3, '大家好'), _cue(4, 6, '今天我们做饭')]);
    expect(lines.map((c) => c.text), ['大家好\nCiao a tutti', '今天我们做饭\nOggi cuciniamo']);
    expect(castSubtitleLines([_cue(1, 3, 'Ciao')], const []).single.text, 'Ciao');
    expect(castSubtitleLines(const [], [_cue(1, 3, '你好')]).single.text, '你好');
  });

  test('a stream that starts later gets its lines moved to its own time', () {
    final lines = cuesFrom([_cue(1, 3, 'a'), _cue(9, 12, 'b'), _cue(20, 22, 'c')], const Duration(seconds: 10));
    expect([for (final c in lines) (c.start.inSeconds, c.end.inSeconds, c.text)], [(0, 2, 'b'), (10, 12, 'c')]);
  });

  test('WebVTT reads back the same lines', () {
    final cues = [_cue(61, 63, '大家好\nCiao'), _cue(3700, 3702, 'x')];
    final vtt = toVtt(cues);
    expect(vtt, startsWith('WEBVTT\n\n00:01:01.000 --> 00:01:03.000\n大家好\nCiao\n'));
    expect(vtt, contains('01:01:40.000 --> 01:01:42.000'));
  });

  test('serves the files with CORS for the Chromecast receiver', () async {
    final server = CastSubtitleServer.instance;
    addTearDown(server.close);
    final subtitles = await server.register([_cue(1, 2, '你好')], host: '127.0.0.1', language: 'zh-Hans');
    final client = HttpClient();
    addTearDown(client.close);
    final response = await (await client.getUrl(Uri.parse(subtitles.vtt))).close();
    expect(response.statusCode, 200);
    expect(response.headers.value('access-control-allow-origin'), '*');
    expect(response.headers.contentType?.mimeType, 'text/vtt');
    expect(await utf8.decodeStream(response), contains('你好'));
    final srt = await (await client.getUrl(Uri.parse(subtitles.srt))).close();
    expect(await utf8.decodeStream(srt), contains('00:00:01,000 --> 00:00:02,000'));
    final missing = await (await client.getUrl(Uri.parse(subtitles.vtt.replaceFirst('.vtt', '.txt')))).close();
    expect(missing.statusCode, 404);
    await missing.drain<void>();
  });

  test('DLNA metadata names the subtitles the ways renderers look for them', () {
    final didl = didlLite(title: 'T', url: 'http://h/v.ts', mime: 'video/mpeg', subtitles: 'http://h:1/sub1.srt');
    expect(didl, contains('<res protocolInfo="http-get:*:text/srt:*">http://h:1/sub1.srt</res>'));
    expect(didl, contains('<sec:CaptionInfoEx sec:type="srt">http://h:1/sub1.srt</sec:CaptionInfoEx>'));
    expect(didl, contains('xmlns:sec="http://www.sec.co.kr/"'));
    expect(didlLite(title: 'T', url: 'u', mime: 'video/mp4'), isNot(contains('sec:')));
  });
}
