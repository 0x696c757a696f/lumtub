import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/format_policy.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/player_settings.dart';
import 'package:lumtub/stream_resolver.dart';

Map<String, dynamic> _stream(int itag, String mime, int height, int bitrate) => {
      'itag': itag,
      'url': 'https://rr1.googlevideo.com/videoplayback?expire=${DateTime.now().add(const Duration(hours: 6)).millisecondsSinceEpoch ~/ 1000}&c=VISIONOS&itag=$itag',
      'mimeType': mime,
      'bitrate': bitrate,
      'contentLength': '1000',
      if (height > 0) ...{'height': height, 'width': height * 16 ~/ 9, 'fps': 30},
    };

void main() {
  final core = NativeCore.instance;

  test('asks YouTube as its visionOS client', () {
    final request = jsonDecode(core!.quickRequest('abc')!) as Map<String, dynamic>;
    expect(request['body']['videoId'], 'abc');
    expect(request['body']['context']['client']['clientName'], 'VISIONOS');
    expect(request['headers']['X-YouTube-Client-Name'], '101');
  }, skip: core == null);

  test('plays the picked streams directly, or leaves the video to yt-dlp', () {
    final player = {
      'playabilityStatus': {'status': 'OK'},
      'videoDetails': {'videoId': 'abc', 'title': 'T', 'lengthSeconds': '60'},
      'streamingData': {
        'adaptiveFormats': [
          _stream(137, 'video/mp4; codecs="avc1.640028"', 1080, 4000000),
          _stream(248, 'video/webm; codecs="vp9"', 1080, 2500000),
          _stream(140, 'audio/mp4; codecs="mp4a.40.2"', 0, 130000),
        ],
      },
    };
    const settings = PlayerSettings(disabledCodecs: {});
    final text = core!.quickInfo(jsonEncode(player), FormatPolicy.settingsJson(settings))!;
    final video = ResolvedVideo(jsonDecode(text) as Map<String, dynamic>, File('info.json'), 'f', text: text);
    expect(video.directUrl, allOf(startsWith('edl://'), contains('itag=137'), contains('itag=140')));
    expect(video.heights, [1080]);
    expect(video.origin, contains('VISIONOS'));
    player['playabilityStatus'] = {'status': 'LOGIN_REQUIRED'};
    expect(core.quickInfo(jsonEncode(player), FormatPolicy.settingsJson(settings)), isNull);
  }, skip: core == null);
}
