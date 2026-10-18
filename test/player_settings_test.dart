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
}
