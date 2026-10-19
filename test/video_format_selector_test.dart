import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/decoder_status.dart';
import 'package:ytplus/player_settings.dart';
import 'package:ytplus/video_format_selector.dart';

void main() {
  test('uses H.264 until a hardware codec was actually verified', () {
    expect(VideoFormatSelector.expressionFor(const PlayerSettings()), startsWith('bestvideo[vcodec^=avc1]+bestaudio/'));
  });

  test('prefers verified VP9 hardware decoding', () {
    const settings = PlayerSettings(decoderResults: {'vp9': DecoderStatus.hardware('d3d11va'), 'av1': DecoderStatus.unverified()});
    expect(VideoFormatSelector.expressionFor(settings), startsWith('bestvideo[vcodec^=vp9]+bestaudio/bestvideo[vcodec^=avc1]'));
  });

  test('never prefers AV1 automatically, even with hardware decoding', () {
    const settings = PlayerSettings(decoderResults: {'vp9': DecoderStatus.hardware('d3d11va'), 'av1': DecoderStatus.hardware('d3d11va')});
    expect(VideoFormatSelector.expressionFor(settings), isNot(contains('av01')));
  });

  test('falls back to any codec instead of a low-quality muxed stream', () {
    expect(VideoFormatSelector.expressionFor(const PlayerSettings()), endsWith('/bestvideo+bestaudio/best/best'));
  });

  test('caps every alternative at the chosen height', () {
    final expression = VideoFormatSelector.expressionFor(const PlayerSettings(maxHeight: 720));
    expect(expression, 'bestvideo[vcodec^=avc1][height<=?720]+bestaudio/bestvideo[height<=?720]+bestaudio/best[height<=?720]/best');
  });

  test('asks for VP9 or AV1 above 1080p, where YouTube has no H.264', () {
    final expression = VideoFormatSelector.expressionFor(const PlayerSettings(maxHeight: 2160));
    expect(expression, startsWith('bestvideo[vcodec^=vp9][height<=?2160]+bestaudio/bestvideo[vcodec^=av01][height<=?2160]+bestaudio/'));
  });

  test('applies the height cap when codec selection is off', () {
    expect(VideoFormatSelector.expressionFor(const PlayerSettings(autoSelectCodec: false)), 'ytdl');
    expect(VideoFormatSelector.expressionFor(const PlayerSettings(autoSelectCodec: false, maxHeight: 480)), startsWith('bestvideo[height<=?480]'));
  });
}
