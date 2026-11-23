import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/appearance_settings.dart';

void main() {
  test('Inter is the default font in every language', () {
    expect(const AppearanceSettings().font, interFont);
  });

  test('older saved defaults become automatic, chosen fonts stay', () {
    expect(AppearanceSettings.fromJson({'fontFamily': bundledFont}).fontFamily, autoFont);
    expect(AppearanceSettings.fromJson({}).fontFamily, autoFont);
    expect(AppearanceSettings.fromJson({'fontFamily': 'system'}).font, isNull);
    final chosen = AppearanceSettings.fromJson(const AppearanceSettings(fontFamily: bundledFont).toJson());
    expect(chosen.font, bundledFont);
    expect(AppearanceSettings.fromJson({'fontFamily': 'Segoe UI'}).font, 'Segoe UI');
    expect(AppearanceSettings.fromJson(const AppearanceSettings(fontFamily: interFont).toJson()).font, interFont);
  });

  test('Japanese, Korean and traditional Chinese keep their own character forms', () {
    for (final tag in ['ja', 'ko', 'zh-Hant']) {
      expect(fontFallback(interFont, tag), isNot(contains(bundledFont)), reason: tag);
      expect(fontFallback(null, tag), isNot(contains(bundledFont)), reason: tag);
    }
    for (final tag in ['zh-Hans', 'en', 'ru', 'fr']) {
      expect(fontFallback(interFont, tag).first, bundledFont, reason: tag);
    }
    expect(fontFallback(bundledFont, 'ja'), contains(bundledFont));
  });
}
