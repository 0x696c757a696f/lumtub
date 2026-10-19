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
  test('subtitle preferences become slang and yt-dlp options', () {
    expect(PlayerOptionApplicator.optionsFor(const PlayerSettings())['slang'], '');
    expect(PlayerOptionApplicator.optionsFor(const PlayerSettings())['ytdl-raw-options'], '');
    final options = PlayerOptionApplicator.optionsFor(const PlayerSettings(subtitleMode: SubtitleMode.always, subtitleLanguage: SubtitleLanguage.en));
    expect(options['slang'], startsWith('en,'));
    expect(options['ytdl-raw-options'], 'sub-langs=en.*,write-auto-subs=');
  });

  test('single cycle loops the file in mpv', () {
    expect(PlayerOptionApplicator.optionsFor(const PlayerSettings(playOrder: PlayOrder.singleCycle))['loop-file'], 'inf');
    expect(PlayerOptionApplicator.optionsFor(const PlayerSettings())['loop-file'], 'no');
  });
}
