import 'l10n/l10n.dart';

/// Where explore's videos are popular: YouTube's own country setting,
/// `gl`, which it reads from the PREF cookie. [any] leaves it to YouTube,
/// which goes by the connection's address.
enum ExploreRegion {
  any('全部地区', ''),
  cn('中国大陆', 'CN'),
  tw('台湾', 'TW'),
  hk('香港', 'HK'),
  sg('新加坡', 'SG'),
  my('马来西亚', 'MY'),
  jp('日本', 'JP'),
  kr('韩国', 'KR'),
  us('美国', 'US'),
  gb('英国', 'GB'),
  ca('加拿大', 'CA'),
  au('澳大利亚', 'AU'),
  de('德国', 'DE'),
  fr('法国', 'FR'),
  es('西班牙', 'ES'),
  it('意大利', 'IT'),
  ru('俄罗斯', 'RU'),
  br('巴西', 'BR'),
  mx('墨西哥', 'MX'),
  india('印度', 'IN'),
  th('泰国', 'TH'),
  vn('越南', 'VN'),
  id('印度尼西亚', 'ID'),
  ph('菲律宾', 'PH');

  const ExploreRegion(this._label, this.gl);
  final String _label;
  String get label => tr(_label);
  final String gl;

  static ExploreRegion parse(Object? raw) => values.where((r) => r.name == raw).firstOrNull ?? any;
}

/// The language of explore's videos, told from the title's script and,
/// for languages written in Latin letters, its small words. YouTube's
/// listings do not say a video's language, hence the guess.
enum ExploreLanguage {
  any('全部语言'),
  zh('中文'),
  ja('日语'),
  ko('韩语'),
  en('英语'),
  es('西班牙语'),
  fr('法语'),
  de('德语'),
  pt('葡萄牙语'),
  ru('俄语'),
  ar('阿拉伯语'),
  hi('印地语'),
  th('泰语'),
  vi('越南语');

  const ExploreLanguage(this._label);
  final String _label;
  String get label => tr(_label);

  static ExploreLanguage parse(Object? raw) => values.where((l) => l.name == raw).firstOrNull ?? any;

  /// Whether [title] reads as this language.
  bool matches(String title) => this == any || titleLanguage(title) == this;
}

final _kana = RegExp(r'[぀-ヿ]');
final _hangul = RegExp(r'[가-힯ᄀ-ᇿ]');
final _han = RegExp(r'[一-鿿㐀-䶿]');
final _cyrillic = RegExp(r'[Ѐ-ӿ]');
final _arabic = RegExp(r'[؀-ۿ]');
final _devanagari = RegExp(r'[ऀ-ॿ]');
final _thai = RegExp(r'[฀-๿]');
final _vietnamese = RegExp(r'[ăâđêôơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ]', caseSensitive: false);
final _latin = RegExp(r'[a-zA-Z]');
final _word = RegExp(r"[\p{L}']+", unicode: true);

/// Small words that mark a Latin-script language, and letters only it uses.
const _latinWords = <ExploreLanguage, Set<String>>{
  ExploreLanguage.en: {'the', 'and', 'of', 'to', 'in', 'is', 'for', 'with', 'how', 'what', 'why', 'you', 'my', 'this', 'your', 'from', 'on', 'are', 'i', 'we', 'best', 'vs'},
  ExploreLanguage.es: {'el', 'los', 'las', 'del', 'y', 'que', 'con', 'una', 'por', 'para', 'es', 'como', 'mi', 'más', 'qué', 'cómo', 'muy', 'pero', 'su'},
  ExploreLanguage.fr: {'le', 'les', 'des', 'et', 'du', 'est', 'une', 'pour', 'dans', 'avec', 'sur', 'pas', 'qui', 'mon', 'ce', 'je', 'au', 'aux', "c'est", 'vous'},
  ExploreLanguage.de: {'der', 'die', 'das', 'und', 'ist', 'mit', 'ein', 'eine', 'nicht', 'für', 'auf', 'den', 'ich', 'wie', 'was', 'zu', 'im', 'von', 'auch', 'wir'},
  ExploreLanguage.pt: {'o', 'os', 'do', 'da', 'dos', 'das', 'e', 'que', 'com', 'um', 'uma', 'para', 'não', 'é', 'em', 'no', 'na', 'mais', 'você', 'como'},
};
final _latinLetters = <ExploreLanguage, RegExp>{
  ExploreLanguage.es: RegExp('[ñ¿¡]', caseSensitive: false),
  ExploreLanguage.fr: RegExp('[œçèùû]', caseSensitive: false),
  ExploreLanguage.de: RegExp('[äöüß]', caseSensitive: false),
  ExploreLanguage.pt: RegExp('[ãõ]|ção', caseSensitive: false),
};

/// The language [title] is most likely in, or [ExploreLanguage.any] when
/// it gives nothing to go by.
ExploreLanguage titleLanguage(String title) {
  if (_kana.hasMatch(title)) return ExploreLanguage.ja;
  if (_hangul.hasMatch(title)) return ExploreLanguage.ko;
  if (_han.hasMatch(title)) return ExploreLanguage.zh;
  if (_thai.hasMatch(title)) return ExploreLanguage.th;
  if (_devanagari.hasMatch(title)) return ExploreLanguage.hi;
  if (_arabic.hasMatch(title)) return ExploreLanguage.ar;
  if (_cyrillic.hasMatch(title)) return ExploreLanguage.ru;
  if (_vietnamese.hasMatch(title)) return ExploreLanguage.vi;
  if (!_latin.hasMatch(title)) return ExploreLanguage.any;
  final words = _word.allMatches(title.toLowerCase()).map((m) => m.group(0)!).toList();
  var best = ExploreLanguage.en;
  var bestScore = 0.0;
  for (final MapEntry(key: language, value: small) in _latinWords.entries) {
    var score = words.where(small.contains).length.toDouble();
    if (_latinLetters[language]?.hasMatch(title) ?? false) score += 1.5;
    if (score > bestScore) (best, bestScore) = (language, score);
  }
  // A title with no small words at all, such as "Minecraft Speedrun", is
  // taken as English, the usual language of such titles.
  return best;
}
