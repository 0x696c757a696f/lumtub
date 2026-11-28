import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/appearance_settings.dart';
import 'package:lumtub/player_settings.dart';

void main() {
  test('Inter is the default font in every language', () {
    expect(const AppearanceSettings().font, interFont);
  });

  test('older saved defaults become automatic, chosen fonts stay', () {
    expect(AppearanceSettings.fromJson({'fontFamily': bundledFont}).fontFamily, autoFont);
    expect(AppearanceSettings.fromJson({}).fontFamily, autoFont);
    expect(AppearanceSettings.fromJson({'fontFamily': 'system'}).font, isNull);
    final chosen =
        AppearanceSettings.fromJson(const AppearanceSettings(fontFamily: bundledFont).toJson());
    expect(chosen.font, bundledFont);
    expect(AppearanceSettings.fromJson({'fontFamily': 'Segoe UI'}).font, 'Segoe UI');
    expect(
        AppearanceSettings.fromJson(const AppearanceSettings(fontFamily: interFont).toJson()).font,
        interFont);
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

  test('language tags map to their character forms', () {
    for (final tag in ['ja', 'ja-JP', 'jpn']) {
      expect(cjkFormOf(tag), 'ja', reason: tag);
    }
    for (final tag in ['ko', 'ko-KR', 'kor']) {
      expect(cjkFormOf(tag), 'ko', reason: tag);
    }
    for (final tag in ['zh-Hant', 'zh-TW', 'zh-HK', 'zh_Hant', 'yue']) {
      expect(cjkFormOf(tag), 'zh-Hant', reason: tag);
    }
    for (final tag in ['zh', 'zh-Hans', 'zh-CN', 'en', '', 'fr']) {
      expect(cjkFormOf(tag), isNull, reason: tag);
    }
  });

  test('text in a known language keeps its forms whatever the interface language', () {
    expect(languageStyle('ja')!.locale, const Locale('ja'));
    expect(languageStyle('ja')!.fontFamilyFallback, isNot(contains(bundledFont)));
    expect(languageStyle('zh-TW')!.locale,
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'));
    // Chinese being learned in a Japanese interface stays simplified.
    expect(languageStyle('zh')!.fontFamilyFallback!.first, bundledFont);
    expect(languageStyle('zh')!.locale,
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'));
    expect(languageStyle(''), isNull);
    expect(languageStyle(null), isNull);
    downloadedCjkFamilies['ja'] = 'Noto Sans JP';
    addTearDown(downloadedCjkFamilies.clear);
    expect(languageStyle('ja')!.fontFamilyFallback!.first, 'Noto Sans JP');
    expect(fontFallback(interFont, 'ja').first, 'Noto Sans JP');
  });

  test('the default subtitle font follows the subtitle language', () {
    expect(PlayerSettings.defaultFontOn('windows', null), PlayerSettings.defaultSubtitleFont);
    expect(PlayerSettings.defaultFontOn('windows', 'ja'), 'Yu Gothic UI');
    expect(PlayerSettings.defaultFontOn('windows', 'ko'), 'Malgun Gothic');
    expect(PlayerSettings.defaultFontOn('windows', 'zh-Hant'), 'Microsoft JhengHei');
    expect(PlayerSettings.defaultFontOn('macos', 'ja'), 'Hiragino Sans');
    expect(PlayerSettings.defaultFontOn('macos', null), 'PingFang SC');
    expect(PlayerSettings.defaultFontOn('linux', 'ja'), 'Noto Sans CJK JP');
    expect(PlayerSettings.defaultFontOn('linux', null), 'Noto Sans CJK SC');
    expect(PlayerSettings.defaultFontOn('linux', 'ja', downloaded: {'ja': 'Noto Sans JP'}),
        'Noto Sans JP');
  });
}
