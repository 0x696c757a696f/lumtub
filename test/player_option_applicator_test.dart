import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/player_option_applicator.dart';
import 'package:ytplus/player_settings.dart';

void main() {
  test('maps supported UI settings to libmpv options', () {
    const settings = PlayerSettings(
      hwdec: 'd3d11va',
      scale: 'lanczos',
      deband: true,
      cacheMode: 'yes',
      cacheSeconds: 45,
      cacheMemoryMb: 128,
    );
    final options = PlayerOptionApplicator.optionsFor(settings);
    expect(options['hwdec'], 'd3d11va');
    expect(options['scale'], 'lanczos');
    expect(options['deband'], 'yes');
    expect(options['cache-secs'], '45');
    expect(options['demuxer-max-bytes'], '128MiB');
  });
}
