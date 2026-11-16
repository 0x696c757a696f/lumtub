import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/player_settings.dart';
import 'package:lumtub/ui/pages/watch_page.dart';

void main() {
  test('small windows get subtitles in proportion, readable and not oversized', () {
    double px(double width, double height) => 32 * smallSubtitleScale(Size(width, height));
    expect(px(320, 180), 13, reason: 'a tiny window keeps a readable size');
    expect(px(640, 360), closeTo(19.8, 0.01));
    expect(px(1280, 720), 32, reason: 'never past the full-size text');
    expect(px(1920, 1080), 32);
  });

  test('Android sizes subtitles by the player height, as ExoPlayer does', () {
    double px(double width, double height, [double system = 1]) => 32 * androidSubtitleScale(Size(width, height), system);
    expect(px(393, 221), 12, reason: 'the upright phone player keeps 12 px, not the 9 px scaling by area gives');
    expect(px(852, 393), closeTo(20.9, 0.1), reason: 'full screen sideways');
    expect(px(1920, 1080), closeTo(57.6, 0.1), reason: 'a TV, read from afar');
    expect(px(852, 393, 1.5), closeTo(31.4, 0.1), reason: "Android's caption size setting counts");
  });

  test("Android's picture in picture keeps the player's share of the height", () {
    double px(double width, double height) => 32 * androidSubtitleScale(Size(width, height), 1, true);
    expect(px(244, 137), closeTo(7.3, 0.1), reason: 'not the 12 px floor, which took two lines over half the window');
    expect(px(120, 68), 6, reason: 'never under 6 px');
    final view = subtitleViewFor(const PlayerSettings(), smallWindow: const Size(244, 137), byHeight: true);
    expect(view.scaleFor?.call(const Size(244, 137)), TextScaler.linear(137 * 0.0533 / 32));
  });

  test('subtitles in picture in picture and the mini player are on until turned off', () {
    const settings = PlayerSettings();
    expect(settings.pipSubtitles, isTrue);
    expect(settings.miniPlayerSubtitles, isTrue);
    final off = PlayerSettings.fromJson(settings.copyWith(pipSubtitles: false, miniPlayerSubtitles: false).toJson());
    expect(off.pipSubtitles, isFalse);
    expect(off.miniPlayerSubtitles, isFalse);
  });

  testWidgets('the watch page passes the height rule to the subtitle view', (tester) async {
    final view = subtitleViewFor(const PlayerSettings(), byHeight: true);
    expect(view.scaleFor?.call(const Size(852, 393)), TextScaler.linear(393 * 0.0533 / 32));
    expect(subtitleViewFor(const PlayerSettings()).scaleFor, isNull);
  });
}
