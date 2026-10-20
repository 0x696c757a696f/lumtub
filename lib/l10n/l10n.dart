import 'dart:ui' show Locale, PlatformDispatcher;

import 'strings_en.dart';
import 'strings_zh_hant.dart';

/// The languages YTPlus is written in. The source strings are simplified
/// Chinese; the other languages translate them.
enum AppLanguage {
  system('跟随系统', null),
  zhHans('简体中文', Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')),
  zhHant('繁體中文', Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')),
  en('English', Locale('en'));

  const AppLanguage(this.nativeName, this.locale);
  /// The language's own name, the same in every language.
  final String nativeName;
  String get label => this == system ? tr(nativeName) : nativeName;
  final Locale? locale;

  /// [system] as the language Windows uses: traditional Chinese for Taiwan,
  /// Hong Kong and Macau, simplified for other Chinese, English otherwise.
  AppLanguage get resolved {
    if (this != system) return this;
    final locale = PlatformDispatcher.instance.locale;
    if (locale.languageCode != 'zh') return en;
    final traditional = locale.scriptCode == 'Hant' || const {'TW', 'HK', 'MO'}.contains(locale.countryCode);
    return traditional ? zhHant : zhHans;
  }

  static AppLanguage parse(Object? raw) => values.where((l) => l.name == raw).firstOrNull ?? system;
}

AppLanguage _current = AppLanguage.zhHans;
Map<String, String> _strings = const {};

/// The language the interface is shown in, chosen when YTPlus starts.
AppLanguage get currentLanguage => _current;

/// Shows the interface in [language] from now on. Text already on screen
/// changes after a restart.
void setLanguage(AppLanguage language) {
  _current = language.resolved;
  _strings = switch (_current) {
    AppLanguage.en => stringsEn,
    AppLanguage.zhHant => stringsZhHant,
    _ => const {},
  };
}

/// [zh] in the current language, with `{0}`, `{1}`… replaced by [args].
/// Text with no translation stays as written.
String tr(String zh, [List<Object?> args = const []]) {
  final text = _strings[zh] ?? zh;
  if (args.isEmpty) return text;
  return text.replaceAllMapped(_placeholder, (m) {
    final i = int.parse(m.group(1)!);
    return i < args.length ? '${args[i]}' : m.group(0)!;
  });
}

final _placeholder = RegExp(r'\{(\d+)\}');
