import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/live_split.dart';
import 'package:lumtub/player_settings.dart';
import 'package:lumtub/video_codec.dart';

Map<String, dynamic> live(String id, {int? height, String vcodec = 'none', String acodec = 'none', int fps = 60, String protocol = 'https', double tbr = 0}) => {
      'format_id': id,
      if (height != null) 'height': height,
      'fps': fps,
      'vcodec': vcodec,
      'acodec': acodec,
      'tbr': tbr,
      'protocol': protocol,
      'url': 'https://r1.googlevideo.com/videoplayback?itag=$id&live=1&noclen=1',
    };

void main() {
  final info = <String, dynamic>{
    'formats': [
      live('96', height: 1080, vcodec: 'avc1.640028', acodec: 'mp4a.40.2', protocol: 'm3u8_native'),
      live('308', height: 1440, vcodec: 'vp9'),
      live('315', height: 2160, vcodec: 'vp9'),
      live('140', acodec: 'mp4a.40.2'),
      {...live('299', height: 1440, vcodec: 'avc1.64002a'), 'manifest_url': 'https://manifest'},
    ],
  };

  test('takes the tallest live picture within the cap with the AAC sound', () {
    final any = LiveSplit.pick(info, const PlayerSettings(disabledCodecs: {}))!;
    expect(any.video['format_id'], '315');
    expect(any.audio['format_id'], '140');
    expect(LiveSplit.pick(info, const PlayerSettings(disabledCodecs: {}, maxHeight: 1440))!.video['format_id'], '308');
  });

  test('none at a cap of 1080p, in a disabled codec, or without such formats', () {
    expect(LiveSplit.pick(info, const PlayerSettings(disabledCodecs: {}, maxHeight: 1080)), isNull);
    expect(LiveSplit.pick(info, const PlayerSettings(disabledCodecs: {VideoCodec.vp9})), isNull);
    expect(LiveSplit.pick({'formats': [info['formats'][0]]}, const PlayerSettings(disabledCodecs: {})), isNull);
  });

  test('a phone gets the best HLS stream with picture and sound within the cap', () {
    final hls = {
      'formats': [
        live('93', height: 360, vcodec: 'avc1.4d401e', acodec: 'mp4a.40.2', protocol: 'm3u8_native', fps: 30),
        info['formats'][0],
        live('308', height: 1440, vcodec: 'vp9'),
        live('140', acodec: 'mp4a.40.2'),
      ],
    };
    expect(LiveSplit.hls(hls, const PlayerSettings(disabledCodecs: {}))!['format_id'], '96');
    expect(LiveSplit.hls(hls, const PlayerSettings(disabledCodecs: {}, maxHeight: 720))!['format_id'], '93');
    // Below every stream's height: the smallest one rather than nothing.
    expect(LiveSplit.hls(hls, const PlayerSettings(disabledCodecs: {}, maxHeight: 144))!['format_id'], '93');
    expect(LiveSplit.hls(hls, const PlayerSettings(disabledCodecs: {VideoCodec.h264})), isNull);
    expect(LiveSplit.hls({'formats': [], 'manifest_url': 'https://manifest'}, const PlayerSettings(disabledCodecs: {}))!['url'], 'https://manifest');
  });
}
