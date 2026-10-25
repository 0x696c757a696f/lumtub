import 'dart:convert';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/services.dart' show AssetBundle, AssetManifest, rootBundle;

/// A language the interface can be shown in. The source strings are
/// simplified Chinese, each wrapped in a tr call; every other
/// language is a file in assets/l10n named by its language tag, mapping
/// each source string to its translation. English (en.json) is the one
/// translators start from.
class AppLanguage {
  const AppLanguage(this.tag);

  /// The language Windows uses, or English when Lumtub has no good
  /// translation for it.
  static const system = AppLanguage('system');
  static const zhHans = AppLanguage('zh-Hans');
  static const en = AppLanguage('en');

  /// The language tag, the file's name without .json.
  final String tag;

  /// The language's own name, the same in every language.
  String get nativeName => _nativeNames[tag] ?? tag;
  String get label => this == system ? tr('跟随系统') : nativeName;
  Locale? get locale => this == system ? null : Locale.fromSubtags(languageCode: tag.split('-').first, scriptCode: _script(tag), countryCode: _country(tag));
  bool get isChinese => tag.startsWith('zh');

  /// [system] as one of [selectable]: the Windows language when it is one,
  /// simplified Chinese for any other Chinese, English otherwise.
  AppLanguage get resolved {
    if (this != system) return this;
    final locale = PlatformDispatcher.instance.locale;
    final offered = selectable.where((l) => l != system).toList();
    for (final candidate in [
      locale.toLanguageTag(),
      if (locale.scriptCode != null) '${locale.languageCode}-${locale.scriptCode}',
      if (locale.languageCode == 'zh' && const {'TW', 'HK', 'MO'}.contains(locale.countryCode)) 'zh-Hant',
      locale.languageCode
    ]) {
      if (offered.where((l) => l.tag == candidate).firstOrNull case final match?) return match;
    }
    return locale.languageCode == 'zh' ? zhHans : en;
  }

  /// What can be chosen in settings: the source language, and every
  /// translation that covers at least [completeEnough] of the strings.
  static List<AppLanguage> get selectable => [system, zhHans, en, for (final tag in _complete) AppLanguage(tag)];

  static AppLanguage parse(Object? raw) {
    final tag = switch (raw) { 'zhHans' => 'zh-Hans', final String s => s, _ => null };
    return selectable.where((l) => l.tag == tag).firstOrNull ?? system;
  }

  @override
  bool operator ==(Object other) => other is AppLanguage && other.tag == tag;

  @override
  int get hashCode => tag.hashCode;

  @override
  String toString() => tag;
}

/// The share of strings a translation needs before it is offered, so the
/// interface never shows a mix of languages.
const completeEnough = 0.9;

AppLanguage _current = AppLanguage.zhHans; // source language, until main() calls setLanguage
Map<String, String> _strings = const {};
Map<String, String> _english = const {};
final _translations = <String, Map<String, String>>{};
var _complete = <String>[];

/// Reads the translations in assets/l10n. Call before [setLanguage].
Future<void> loadTranslations([AssetBundle? bundle]) async {
  bundle ??= rootBundle;
  final manifest = await AssetManifest.loadFromAssetBundle(bundle);
  _translations.clear();
  for (final path in manifest.listAssets().where((p) => p.startsWith('assets/l10n/') && p.endsWith('.json'))) {
    // Weblate may name a file zh_Hant as well as zh-Hant.
    final tag = path.substring('assets/l10n/'.length, path.length - '.json'.length).replaceAll('_', '-');
    // Simplified Chinese is the source text in the code; a file for it is not a translation.
    if (tag == AppLanguage.zhHans.tag) continue;
    final map = (jsonDecode(await bundle.loadString(path)) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
    _translations[tag] = {
      for (final e in map.entries)
        if (e.value.isNotEmpty) e.key: e.value
    };
  }
  _english = _translations['en'] ?? const {};
  _complete = [
    for (final MapEntry(:key, :value) in _translations.entries)
      if (key != 'en' && _english.isNotEmpty && value.keys.where(_english.containsKey).length >= _english.length * completeEnough) key,
  ]..sort();
}

/// The translations read by [loadTranslations], by language tag.
Map<String, Map<String, String>> get translations => _translations;

/// The language the interface is shown in, chosen when Lumtub starts.
AppLanguage get currentLanguage => _current;

/// Shows the interface in [language] from now on. Text already on screen
/// changes after a restart. A string a translation leaves out is shown in
/// English, or for Chinese in simplified Chinese.
void setLanguage(AppLanguage language) {
  _current = language.resolved;
  _strings = switch (_current) {
    AppLanguage.zhHans => const {},
    AppLanguage.en => _english,
    final l when l.isChinese => _translations[l.tag] ?? const {},
    final l => {..._english, ...?_translations[l.tag]},
  };
}

/// The `hl` YouTube is asked in, so titles, dates, comment counts, community
/// posts and comments come in it where YouTube has them translated.
String get youtubeHl => switch (_current.tag) {
      'zh-Hans' => 'zh-CN',
      'zh-Hant' => 'zh-TW',
      final tag => tag,
    };

/// `Accept-Language` to go with [youtubeHl].
String get youtubeAcceptLanguage => switch (_current.tag) {
      'en' => 'en-US,en;q=0.9',
      _ when _current.isChinese => '$youtubeHl,zh;q=0.9,en;q=0.8',
      final tag => '$tag,${tag.split('-').first};q=0.9,en;q=0.8',
    };

/// [zh] in the current language, with `{0}`, `{1}`… replaced by [args].
/// Text with no translation stays as written.
String tr(String zh, [List<Object?> args = const []]) => _fill(_strings[zh] ?? zh, args);

/// [zh] in English whatever the interface language, for the log.
String trLog(String zh, [List<Object?> args = const []]) => _fill(_english[zh] ?? zh, args);

String _fill(String text, List<Object?> args) {
  if (args.isEmpty) return text;
  return text.replaceAllMapped(_placeholder, (m) {
    final i = int.parse(m.group(1)!);
    return i < args.length ? '${args[i]}' : m.group(0)!;
  });
}

final _placeholder = RegExp(r'\{(\d+)\}');

String? _script(String tag) => tag.split('-').skip(1).where((p) => p.length == 4).firstOrNull;
String? _country(String tag) => tag.split('-').skip(1).where((p) => p.length == 2 || p.length == 3 && int.tryParse(p) != null).firstOrNull;

/// Names of languages a translation may be added for, each in itself.
const _nativeNames = {
  'zh-Hans': '简体中文',
  'zh-Hant': '繁體中文',
  'en': 'English',
  'ar': 'العربية',
  'cs': 'Čeština',
  'da': 'Dansk',
  'de': 'Deutsch',
  'el': 'Ελληνικά',
  'es': 'Español',
  'fa': 'فارسی',
  'fi': 'Suomi',
  'fr': 'Français',
  'he': 'עברית',
  'hi': 'हिन्दी',
  'hu': 'Magyar',
  'id': 'Bahasa Indonesia',
  'it': 'Italiano',
  'ja': '日本語',
  'ko': '한국어',
  'ms': 'Bahasa Melayu',
  'nb': 'Norsk bokmål',
  'nl': 'Nederlands',
  'pl': 'Polski',
  'pt': 'Português',
  'pt-BR': 'Português (Brasil)',
  'ro': 'Română',
  'ru': 'Русский',
  'sv': 'Svenska',
  'th': 'ไทย',
  'tr': 'Türkçe',
  'uk': 'Українська',
  'vi': 'Tiếng Việt',
};
