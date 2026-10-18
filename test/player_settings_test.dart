import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/player_settings.dart';

void main() {
  test('invalid persisted values return safe defaults', () {
    final settings = PlayerSettings.fromJson({
      'hwdec': 'unsafe',
      'cacheSeconds': -4,
      'subtitleScale': 99,
      'customOptions': {'vo': 'gpu-next', 'scale': 'lanczos'},
    });
    expect(settings.hwdec, 'auto-safe');
    expect(settings.cacheSeconds, 30);
    expect(settings.subtitleScale, 3.0);
    expect(settings.customOptions, {'scale': 'lanczos'});
  });

  test('custom option validation keeps media_kit output options private', () {
    expect(PlayerSettings.isSafeCustomOption('scale', 'lanczos'), isTrue);
    expect(PlayerSettings.isSafeCustomOption('vo', 'gpu-next'), isFalse);
    expect(PlayerSettings.isSafeCustomOption('cache', 'yes; quit'), isFalse);
  });

  test('keeps only recorded results for supported codecs', () {
    final settings = PlayerSettings.fromJson({
      'decoderResults': {'vp9': 'd3d11va', 'av1': '软件解码已验证', 'hevc': 'unsupported'},
    });
    expect(settings.decoderResults, {'vp9': 'd3d11va', 'av1': '软件解码已验证'});
  });
}
