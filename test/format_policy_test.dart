import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/decoder_status.dart';
import 'package:ytplus/format_policy.dart';
import 'package:ytplus/player_settings.dart';
import 'package:ytplus/video_codec.dart';

const _hw = DecoderStatus.hardware('d3d11va');

String _expression(PlayerSettings settings) => FormatPolicy.expression(settings);

List<VideoCodec> _order(PlayerSettings settings) => FormatPolicy.codecOrder(settings);

void main() {
  group('auto', () {
    test('uses H.264 until a hardware codec was actually verified', () {
      expect(_order(const PlayerSettings()), [VideoCodec.h264, VideoCodec.vp9, VideoCodec.av1, VideoCodec.vp8]);
      expect(_expression(const PlayerSettings()), startsWith("bestvideo[vcodec~='^(avc1|avc3|h264)']+bestaudio/"));
    });

    test('prefers verified hardware codecs, VP9 then AV1, then H.264', () {
      const all = PlayerSettings(decoderResults: {'vp9': _hw, 'av1': _hw, 'h264': _hw});
      expect(_order(all).take(3), [VideoCodec.vp9, VideoCodec.av1, VideoCodec.h264]);
      const vp9Only = PlayerSettings(decoderResults: {'vp9': _hw, 'av1': DecoderStatus.unverified()});
      expect(_order(vp9Only).take(2), [VideoCodec.vp9, VideoCodec.h264]);
    });

    test('asks for VP9 or AV1 above 1080p, where YouTube has no H.264', () {
      final expression = _expression(const PlayerSettings(maxHeight: 2160));
      expect(
        expression,
        startsWith("bestvideo[vcodec~='^(vp09|vp9)'][height<=?2160]+bestaudio/bestvideo[vcodec~='^(av01|av1)'][height<=?2160]+bestaudio/bestvideo[vcodec~='^(avc1"),
      );
    });

    test('puts AV1 before H.264 only with verified hardware decoding or a tall cap', () {
      final plain = _order(const PlayerSettings(maxHeight: 1080));
      expect(plain.indexOf(VideoCodec.av1), greaterThan(plain.indexOf(VideoCodec.h264)));
      expect(_order(const PlayerSettings(decoderResults: {'av1': _hw})).first, VideoCodec.av1);
    });

    test('caps every alternative at the chosen height and ends with plain fallbacks', () {
      final expression = _expression(const PlayerSettings(maxHeight: 720));
      expect(expression.split('/').where((a) => a.startsWith('bestvideo')), everyElement(contains('[height<=?720]')));
      expect(expression, endsWith('/bestvideo[height<=?720]+bestaudio/best[height<=?720]/best'));
    });

    test('keeps the audio cap on the alternatives', () {
      final expression = _expression(const PlayerSettings(audioQuality: AudioQuality.low));
      expect(expression, startsWith("bestvideo[vcodec~='^(avc1|avc3|h264)']+bestaudio[abr<=?64]/"));
      expect(expression, endsWith('/bestvideo+bestaudio[abr<=?64]/bestvideo+bestaudio/best/best'));
    });
  });

  group('lowResource', () {
    test('H.264 first, then verified hardware codecs, then the rest', () {
      const settings = PlayerSettings(strategy: PlaybackStrategy.lowResource, decoderResults: {'av1': _hw});
      expect(_order(settings), [VideoCodec.h264, VideoCodec.av1, VideoCodec.vp9, VideoCodec.vp8]);
    });

    test('goes to verified codecs first above 1080p', () {
      const settings = PlayerSettings(strategy: PlaybackStrategy.lowResource, maxHeight: 2160, decoderResults: {'vp9': _hw});
      expect(_order(settings).take(2), [VideoCodec.vp9, VideoCodec.h264]);
    });
  });

  group('quality', () {
    test("is yt-dlp's own ranking", () {
      expect(_expression(const PlayerSettings(strategy: PlaybackStrategy.quality)), 'ytdl');
      expect(_expression(const PlayerSettings(strategy: PlaybackStrategy.quality, maxHeight: 480)), 'bestvideo[height<=?480]+bestaudio/best[height<=?480]/best');
    });
  });

  group('disabled codecs', () {
    test('never appear in the order or in any alternative of any strategy', () {
      for (final strategy in PlaybackStrategy.values) {
        for (final disabled in [
          {VideoCodec.av1},
          {VideoCodec.vp9},
          {VideoCodec.h264, VideoCodec.vp8},
          {VideoCodec.av1, VideoCodec.vp9, VideoCodec.vp8},
        ]) {
          for (final height in [0, 720, 2160]) {
            for (final audio in AudioQuality.values) {
              final settings = PlayerSettings(strategy: strategy, disabledCodecs: disabled, maxHeight: height, audioQuality: audio, decoderResults: const {'vp9': _hw, 'av1': _hw});
              expect(_order(settings).toSet().intersection(disabled), isEmpty);
              final expression = _expression(settings);
              for (final alternative in expression.split('/')) {
                if (alternative.contains("vcodec~='")) {
                  for (final codec in disabled) {
                    expect(alternative, isNot(contains(codec.onlyFilter)), reason: '$strategy $expression');
                  }
                } else if (alternative.startsWith('best')) {
                  // Every other alternative drops each disabled codec.
                  for (final codec in disabled) {
                    if (alternative.startsWith('bestaudio')) continue;
                    expect(alternative, contains(codec.excludeFilter), reason: '$strategy $expression');
                  }
                }
              }
            }
          }
        }
      }
    });

    test('quality strategy excludes them too, without the ytdl shortcut', () {
      const settings = PlayerSettings(strategy: PlaybackStrategy.quality, disabledCodecs: {VideoCodec.av1});
      const exclude = '[vcodec!^=av01][vcodec!^=av1]';
      expect(_expression(settings), 'bestvideo$exclude+bestaudio/best$exclude/best$exclude');
    });

    test('the VP9 filter matches vp09 names, which the old vp9 prefix missed', () {
      const settings = PlayerSettings(maxHeight: 2160);
      expect(_expression(settings), contains("[vcodec~='^(vp09|vp9)']"));
      expect(_expression(settings), isNot(contains('[vcodec^=vp9]')));
    });

    test('summary and names list them', () {
      const settings = PlayerSettings(disabledCodecs: {VideoCodec.vp9, VideoCodec.av1});
      expect(FormatPolicy.disabledNames(settings), 'AV1、VP9');
      expect(FormatPolicy.summary(settings), contains('已禁用 AV1、VP9'));
      expect(FormatPolicy.summary(const PlayerSettings()), isNot(contains('已禁用')));
    });
  });

  test('automatic quality caps unverified modern codecs at 1080p', () {
    expect(FormatPolicy.forDisplay(const PlayerSettings(), 1080).maxHeight, 1080);
    expect(FormatPolicy.forDisplay(const PlayerSettings(), 1600).maxHeight, 1080);
    expect(FormatPolicy.forDisplay(const PlayerSettings(), 1440).maxHeight, 1080);
    expect(FormatPolicy.forDisplay(const PlayerSettings(), 0).maxHeight, 1080);
    const hardwareVp9 = PlayerSettings(decoderResults: {'vp9': _hw});
    expect(FormatPolicy.forDisplay(hardwareVp9, 1600).maxHeight, 2160);
    expect(FormatPolicy.forDisplay(hardwareVp9, 0).maxHeight, 0);
    expect(FormatPolicy.forDisplay(const PlayerSettings(maxHeight: 2160), 1080).maxHeight, 2160);
    expect(FormatPolicy.forDisplay(const PlayerSettings(strategy: PlaybackStrategy.quality), 1080).maxHeight, 0);
    expect(FormatPolicy.forDisplay(const PlayerSettings(disabledCodecs: {VideoCodec.h264}), 1600).maxHeight, 0);
  });
}
