import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/decoder_status.dart';
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
      'decoderResults': {
        'vp9': {'kind': 'hardware', 'hwdec': 'd3d11va'},
        'av1': {'kind': 'software'},
        'hevc': {'kind': 'hardware', 'hwdec': 'd3d11va'},
      },
    });
    expect(settings.decoderResults, {'vp9': const DecoderStatus.hardware('d3d11va'), 'av1': const DecoderStatus.software()});
  });

  test('reads decoder results saved as text by earlier builds', () {
    final settings = PlayerSettings.fromJson({
      'decoderResults': {'h264': '尚未验证', 'vp9': 'd3d11va', 'av1': '软件解码已验证'},
    });
    expect(settings.decoderResults, {
      'h264': const DecoderStatus.unverified(),
      'vp9': const DecoderStatus.hardware('d3d11va'),
      'av1': const DecoderStatus.software(),
    });
  });

  test('decoder results survive a save and load round trip', () {
    const original = PlayerSettings(decoderResults: {'vp9': DecoderStatus.hardware('d3d11va-copy')});
    final restored = PlayerSettings.fromJson(jsonDecode(jsonEncode(original.toJson())));
    expect(restored.decoderResults, original.decoderResults);
  });

  test('quality limit and autoplay survive a round trip', () {
    const original = PlayerSettings(maxHeight: 720, autoplayNext: false);
    final restored = PlayerSettings.fromJson(jsonDecode(jsonEncode(original.toJson())));
    expect(restored.maxHeight, 720);
    expect(restored.autoplayNext, isFalse);
  });

  test('unknown quality limits fall back to automatic', () {
    expect(PlayerSettings.fromJson({'maxHeight': 999}).maxHeight, 0);
    expect(PlayerSettings.fromJson({'maxHeight': '720'}).maxHeight, 0);
    expect(PlayerSettings.fromJson(const {}).autoplayNext, isTrue);
  });
}
