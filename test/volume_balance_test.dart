import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/player_settings.dart';
import 'package:lumtub/volume_balance.dart';

void main() {
  test('a loud video is lowered and a quiet one raised, within limits', () {
    expect(VolumeBalance.gainFor(6), -6);
    expect(VolumeBalance.gainFor(-4), 4);
    expect(VolumeBalance.gainFor(30), -VolumeBalance.maxCut);
    expect(VolumeBalance.gainFor(-30), VolumeBalance.maxBoost);
  });

  test('the chain: gain for the video, then the normaliser, then a limiter', () {
    final chain = VolumeBalance.filter(50, loudnessDb: 6);
    expect(chain, startsWith('@${VolumeBalance.label}:lavfi=['));
    expect(chain, contains('alimiter=level_in=0.501:limit=1:level=0,dynaudnorm=f=400:'));
    expect(chain, endsWith(',alimiter=limit=0.95:level=0:attack=5:release=60]'));
  });

  test('no gain stage when the loudness is unknown or already near the reference', () {
    expect(VolumeBalance.filter(50), isNot(contains('level_in')));
    expect(VolumeBalance.filter(50, loudnessDb: 0.2), isNot(contains('level_in')));
  });

  test('stronger follows faster and may raise further; live follows faster still', () {
    String part(String chain, String key) => RegExp('$key=([0-9.]+)').firstMatch(chain)![1]!;
    final gentle = VolumeBalance.filter(10), strong = VolumeBalance.filter(100);
    expect(int.parse(part(gentle, ':g')), greaterThan(int.parse(part(strong, ':g'))));
    expect(int.parse(part(strong, ':g')).isOdd, isTrue);
    expect(double.parse(part(gentle, ':m')), lessThan(double.parse(part(strong, ':m'))));
    expect(int.parse(part(VolumeBalance.filter(50, live: true), 'f')), lessThan(int.parse(part(VolumeBalance.filter(50), 'f'))));
  });

  test('without limiters only the normaliser is left', () {
    expect(VolumeBalance.filter(50, loudnessDb: 6, withLimiters: false), '@${VolumeBalance.label}:lavfi=[dynaudnorm=f=400:g=37:m=5.5:p=0.95:r=0.2]');
  });

  test("YouTube's loudness is read from a /player answer", () {
    expect(VolumeBalance.loudnessIn('{"playerConfig":{"audioConfig":{"loudnessDb":-3.0100002,"perceptualLoudnessDb":-17.01}}}'), closeTo(-3.01, 1e-6));
    expect(VolumeBalance.loudnessIn('{"playerConfig":{"audioConfig":{"loudnessDb": 7}}}'), 7);
    expect(VolumeBalance.loudnessIn('{"playabilityStatus":{"status":"LOGIN_REQUIRED"}}'), isNull);
  });

  test('the strength is saved, off by default, and kept within 0 to 100', () {
    expect(const PlayerSettings().volumeBalance, 0);
    final json = const PlayerSettings().copyWith(volumeBalance: 40).toJson();
    expect(PlayerSettings.fromJson(json).volumeBalance, 40);
    expect(PlayerSettings.fromJson({...json, 'volumeBalance': 250}).volumeBalance, 100);
  });
}
