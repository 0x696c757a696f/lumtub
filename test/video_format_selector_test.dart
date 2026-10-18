import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/player_settings.dart';
import 'package:ytplus/video_format_selector.dart';

void main() {
  test('uses H.264 until a hardware codec was actually verified', () {
    expect(VideoFormatSelector.expressionFor(const PlayerSettings()), contains('avc1'));
  });

  test('prefers verified VP9 hardware decoding over unverified AV1', () {
    const settings = PlayerSettings(decoderResults: {'vp9': 'd3d11va', 'av1': '尚未验证'});
    expect(VideoFormatSelector.expressionFor(settings), startsWith('bestvideo[vcodec^=vp9]'));
  });

  test('prefers verified AV1 hardware decoding', () {
    const settings = PlayerSettings(decoderResults: {'vp9': 'd3d11va', 'av1': 'd3d11va'});
    expect(VideoFormatSelector.expressionFor(settings), startsWith('bestvideo[vcodec^=av01]'));
  });
}
