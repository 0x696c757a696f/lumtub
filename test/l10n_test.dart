import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/appearance_settings.dart';
import 'package:lumtub/explore_filters.dart';
import 'package:lumtub/explore_topics.dart';
import 'package:lumtub/faith_topics.dart';
import 'package:lumtub/l10n/l10n.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/ui/pages/explore_page.dart';
import 'package:lumtub/ui/pages/settings_page.dart';
import 'package:lumtub/ui/pages/settings_sections.dart';
import 'package:lumtub/ui/subtitle_style.dart';
import 'package:lumtub/ui/theme.dart';

/// The first argument of every tr('…') and tr("…") call in lib/, as the
/// running app passes it.
Set<String> _sourceKeys() {
  final call = RegExp(r"""\btr\((?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""");
  String decode(String s) => s.replaceAllMapped(RegExp(r'\\(.)'), (m) => switch (m[1]) { 'n' => '\n', 't' => '\t', _ => m[1]! });
  return {
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
      for (final m in call.allMatches(file.readAsStringSync())) decode(m[1] ?? m[2]!),
  };
}

final _cjk = RegExp(r'[\u3040-\u30ff\u3400-\u9fff\uff00-\uffef]');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadTranslations);
  tearDown(() => setLanguage(AppLanguage.en));

  test('every translatable string is English and has simplified Chinese text', () {
    final keys = _sourceKeys();
    expect(keys.length, greaterThan(900));
    final chinese = translations['zh-Hans']!;
    expect(keys.where((k) => !chinese.containsKey(k)).toList(), isEmpty, reason: 'add these to assets/l10n/zh-Hans.json');
    // Search words may name things in Chinese as well; text shown may not.
    expect(keys.where((k) => _cjk.hasMatch(k) && !k.startsWith('Falun Gong ')).toList(), isEmpty, reason: 'the source strings are English');
    expect(translations, isNot(contains('en')), reason: 'English is the source and needs no file');
  });

  test('every translation keeps the placeholders and translates only strings simplified Chinese has', () {
    final keys = translations['zh-Hans']!.keys.toSet();
    final placeholder = RegExp(r'\{\d+\}');
    Set<String?> placeholders(String s) => placeholder.allMatches(s).map((m) => m[0]).toSet();
    for (final MapEntry(key: tag, value: strings) in translations.entries) {
      for (final MapEntry(:key, :value) in strings.entries) {
        expect(keys, contains(key), reason: '$tag: not in zh-Hans.json');
        expect(placeholders(value), placeholders(key), reason: '$tag: $key');
      }
    }
  });

  test('only translations covering nine strings in ten are offered', () {
    final source = translations['zh-Hans']!.length;
    for (final MapEntry(key: tag, value: strings) in translations.entries) {
      if (tag == 'zh-Hans') continue;
      final offered = AppLanguage.selectable.any((l) => l.tag == tag);
      expect(offered, strings.length >= source * completeEnough, reason: '$tag: ${strings.length} of $source');
      stdout.writeln('Translation $tag: ${(strings.length * 100 / source).toStringAsFixed(0)}%');
    }
  });

  test('a saved language other than Chinese or English is kept', () {
    for (final language in AppLanguage.selectable) {
      final saved = AppearanceSettings.fromJson(const AppearanceSettings().copyWith(language: language).toJson());
      expect(saved.language, language);
    }
    expect(AppLanguage.selectable.length, greaterThan(60));
  });

  test('translates with placeholders and falls back to the source text', () {
    setLanguage(AppLanguage.en);
    expect(tr('Hidden gems'), 'Hidden gems');
    expect(tr('Text with no translation yet'), 'Text with no translation yet');
    expect(ExploreMode.gems.label, 'Hidden gems');
    expect(formatCount(1234567), '1.2M');
    setLanguage(AppLanguage.zhHans);
    expect(tr('Hidden gems'), '冷门宝藏');
    expect(tr('Current: {0}', ['720p']), '当前：720p');
    expect(trLog('Current: {0}', ['720p']), 'Current: 720p', reason: 'the log is in English whatever the interface language');
    expect(ExploreMode.gems.label, '冷门宝藏');
    expect(formatCount(1234567), '123万');
    setLanguage(const AppLanguage('zh-Hant'));
    expect(tr('Hidden gems'), '冷門寶藏');
    expect(formatCount(1234567), '123萬');
    setLanguage(const AppLanguage('de'));
    expect(tr('Hidden gems'), isNot('Hidden gems'));
    expect(tr('Text with no translation yet'), 'Text with no translation yet');
    setLanguage(const AppLanguage('xx'));
    expect(tr('Hidden gems'), 'Hidden gems', reason: 'a language without the string falls back to English');
  });

  test('translated text that ends up in a log line is written in English', () {
    setLanguage(AppLanguage.zhHans);
    final error = StateError(tr('YouTube returned {0}', [403]));
    final label = ExploreMode.gems.label;
    expect(inEnglish('Comments failed: $error; mode $label'), 'Comments failed: Bad state: YouTube returned 403; mode Hidden gems');
    expect(inEnglish('Search "成都旅行"'), 'Search "成都旅行"', reason: 'what YouTube or the user wrote stays as it is');
  });

  test('traditional Chinese falls back to simplified Chinese, other languages to English', () {
    final simplified = translations['zh-Hans']!;
    final saved = {for (final tag in ['zh-Hant', 'zh-HK', 'de']) tag: translations[tag]!};
    addTearDown(() => translations.addAll(saved));
    // A string each file leaves out.
    for (final MapEntry(key: tag, value: strings) in saved.entries) {
      translations[tag] = {...strings}..remove('Hidden gems');
    }
    for (final tag in ['zh-Hant', 'zh-HK']) {
      setLanguage(AppLanguage(tag));
      expect(tr('Hidden gems'), simplified['Hidden gems'], reason: tag);
      expect(tr('Subtitles'), saved[tag]!['Subtitles'], reason: tag);
    }
    setLanguage(const AppLanguage('de'));
    expect(tr('Hidden gems'), 'Hidden gems');
  });

  test('a font name is never translated, a country of the same name is', () {
    setLanguage(const AppLanguage('de'));
    expect(ExploreRegion.ge.label, 'Georgien');
    expect(subtitleFontLabel('Georgia'), 'Georgia');
  });

  test('custom zones keep their own names and keys in every language', () {
    setLanguage(AppLanguage.zhHans);
    const custom = CustomTopic('额我略圣歌', 'Gregorian chant', ExploreSection.popular);
    expect(custom.topic.label, '额我略圣歌');
    final faith = faithTraditionTopics.first;
    expect(faith.key, 'Christianity');
    expect(faith.label, '基督宗教');
    expect(legacyTopicKeys['基督宗教'], faith.key);
  });

  testWidgets('the explore page lays out in English', (tester) async {
    setLanguage(AppLanguage.en);
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = AppController()..ready = true;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ExplorePage(controller: controller),
    ))));
    await tester.pump();
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Popular'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(popularTopics.singleWhere((t) => t.opens == ExploreSection.faith).label, 'Religion & faith');
    controller.setExplore(section: ExploreSection.faith);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Catholic'));
    await tester.pump();
    expect(find.text('All Catholic'), findsOneWidget);
    expect(find.text('Selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Live').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Upcoming'), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.setExplore(section: ExploreSection.popular, topic: popularTopics.indexWhere((t) => t.opens == ExploreSection.humanities));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.exploreSection, ExploreSection.humanities);
    await tester.tap(find.text('Social sciences'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Psychology'));
    await tester.pump();
    expect(find.text('Clinical psychology'), findsOneWidget);
    expect(controller.exploreMode, ExploreMode.curated);
    expect(tester.takeException(), isNull);
  });

  for (final language in [AppLanguage.en, AppLanguage.zhHans]) {
    testWidgets('every settings group lays out in ${language.tag}', (tester) async {
      setLanguage(language);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = AppController();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(Colors.red, Brightness.light),
        home: Scaffold(body: SettingsPage(controller: controller)),
      ));
      await tester.pump();
      for (final category in SettingsCategory.values) {
        await tester.ensureVisible(find.text(category.title).first);
        await tester.tap(find.text(category.title).first);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: category.title);
      }
      await tester.ensureVisible(find.text(SettingsCategory.style.title).first);
      await tester.tap(find.text(SettingsCategory.style.title).first);
      await tester.pump();
      expect(find.text(tr('Language')), findsOneWidget);
    });
  }

  testWidgets('every offered language lays out the settings, right to left where it reads so', (tester) async {
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final language in AppLanguage.selectable.skip(1)) {
      setLanguage(language);
      final wanted = language.locale!;
      final locale = GlobalMaterialLocalizations.delegate.isSupported(wanted) ? wanted : const Locale('en');
      final controller = AppController();
      await tester.pumpWidget(MaterialApp(
        key: ValueKey(language.tag),
        locale: locale,
        supportedLocales: [locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildAppTheme(Colors.red, Brightness.light),
        home: Scaffold(body: SettingsPage(controller: controller)),
      ));
      await tester.pump();
      final rtl = const {'ar', 'he', 'fa', 'ur'}.contains(wanted.languageCode);
      expect(Directionality.of(tester.element(find.byType(SettingsPage))), rtl ? TextDirection.rtl : TextDirection.ltr, reason: language.tag);
      for (final category in SettingsCategory.values) {
        expect(find.text(category.title), findsWidgets, reason: '${language.tag} ${category.title}');
        await tester.tap(find.text(category.title).first);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '${language.tag} ${category.title}');
      }
    }
  });

  test('the language follows Windows unless English or simplified Chinese was saved', () {
    expect(AppLanguage.parse('en'), AppLanguage.en);
    expect(AppLanguage.parse('zhHans'), AppLanguage.zhHans);
    for (final saved in ['zhHant', 'system', null, 'nonsense']) {
      expect(AppLanguage.parse(saved), AppLanguage.system, reason: '$saved');
    }
    expect(AppLanguage.selectable.take(3), [AppLanguage.system, AppLanguage.zhHans, AppLanguage.en]);
    expect(AppLanguage.parse(AppLanguage.zhHans.tag), AppLanguage.zhHans);
    expect(AppLanguage.selectable, contains(AppLanguage.system.resolved));
    expect(const AppearanceSettings().language, AppLanguage.system);
    expect(AppearanceSettings.fromJson({'language': 'zhHant'}).language, AppLanguage.system);
  });
}
