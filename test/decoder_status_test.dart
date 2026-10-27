import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/decoder_status.dart';

void main() {
  test('libmpv reports no hardware decoder as software decoding', () {
    expect(DecoderStatus.fromMpv('no'), const DecoderStatus.software());
    expect(DecoderStatus.fromMpv(''), const DecoderStatus.software());
    expect(DecoderStatus.fromMpv('d3d11va'), const DecoderStatus.hardware('d3d11va'));
  });

  test('normalises libmpv codec names', () {
    expect(DecoderStatus.codecKey('libdav1d (AV1)'), 'av1');
    expect(DecoderStatus.codecKey('vp9'), 'vp9');
    expect(DecoderStatus.codecKey('h264 (AVC)'), 'h264');
    expect(DecoderStatus.codecKey('hevc'), isNull);
  });

  test('rejects malformed stored values', () {
    expect(DecoderStatus.fromJson({'kind': 'hardware'}), isNull);
    expect(DecoderStatus.fromJson({'kind': 'magic'}), isNull);
    expect(DecoderStatus.fromJson('d3d11va; quit'), isNull);
  });

  test('hardware decoding crops the padded edges only', () {
    expect(DecoderStatus.paddingCrop(1920, 1080, hardware: true), '1920x1076+0+0');
    expect(DecoderStatus.paddingCrop(640, 360, hardware: true), '640x356+0+0');
    expect(DecoderStatus.paddingCrop(854, 480, hardware: true), '850x476+0+0');
    expect(DecoderStatus.paddingCrop(1280, 768, hardware: true), '');
    expect(DecoderStatus.paddingCrop(3840, 2160, hardware: true), '3840x2156+0+0');
    expect(DecoderStatus.paddingCrop(1920, 1080, hardware: false), '');
    expect(DecoderStatus.paddingCrop(0, 0, hardware: true), '');
  });
}
