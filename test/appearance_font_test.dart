import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/appearance_settings.dart';

void main() {
  tearDown(() => systemFitsBundledFont = () => true);

  test('the bundled font is the default only on a Chinese system', () {
    systemFitsBundledFont = () => true;
    expect(const AppearanceSettings().font, bundledFont);
    systemFitsBundledFont = () => false;
    expect(const AppearanceSettings().font, isNull);
  });

  test('older saved defaults become automatic, chosen fonts stay', () {
    systemFitsBundledFont = () => false;
    expect(AppearanceSettings.fromJson({'fontFamily': bundledFont}).fontFamily, autoFont);
    expect(AppearanceSettings.fromJson({}).fontFamily, autoFont);
    expect(AppearanceSettings.fromJson({'fontFamily': 'system'}).font, isNull);
    final chosen = AppearanceSettings.fromJson(const AppearanceSettings(fontFamily: bundledFont).toJson());
    expect(chosen.font, bundledFont);
    expect(AppearanceSettings.fromJson({'fontFamily': 'Segoe UI'}).font, 'Segoe UI');
  });

  test('only simplified Chinese counts', () {
    expect(isSimplifiedChinese(const Locale('zh', 'CN')), isTrue);
    expect(isSimplifiedChinese(const Locale('zh', 'SG')), isTrue);
    expect(isSimplifiedChinese(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'HK')), isTrue);
    expect(isSimplifiedChinese(const Locale('zh', 'TW')), isFalse);
    expect(isSimplifiedChinese(const Locale('zh', 'HK')), isFalse);
    expect(isSimplifiedChinese(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')), isFalse);
    expect(isSimplifiedChinese(const Locale('ja', 'JP')), isFalse);
  });
}
