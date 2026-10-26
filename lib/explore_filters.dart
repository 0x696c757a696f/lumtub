import 'l10n/l10n.dart';
import 'native_core.dart';

/// A 类型 or 视角 choice in explore: words added to the zone's search, so it
/// leans the results rather than sorting them exactly.
abstract interface class WordFilter {
  String get label;
  String get words;
}

/// 类型 for every zone but 宗教与信仰, whose own list fits it better.
enum ContentFormat implements WordFilter {
  any('不限', ''),
  tutorial('教程', 'tutorial 教程'),
  lecture('讲座课程', 'lecture course 课程'),
  documentary('纪录片', 'documentary 纪录片'),
  interview('访谈播客', 'interview podcast 访谈'),
  review('评测', 'review 评测'),
  analysis('解说分析', 'explained analysis 解析'),
  news('新闻', 'news 新闻'),
  vlog('Vlog', 'vlog'),
  compilation('合集', 'compilation 合集');

  const ContentFormat(this._label, this.words);
  final String _label;
  @override
  String get label => tr(_label);
  @override
  final String words;
}

/// 视角 for every zone but 宗教与信仰.
enum ContentView implements WordFilter {
  any('不限', ''),
  beginner('入门科普', 'beginner explained 入门'),
  expert('专业深度', 'in-depth expert 深度'),
  critical('批判讨论', 'critique criticism 批评'),
  debate('对比辩论', 'debate versus 对比'),
  experience('亲身体验', 'my experience 亲身经历');

  const ContentView(this._label, this.words);
  final String _label;
  @override
  String get label => tr(_label);
  @override
  final String words;
}

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
  /// Without the library every title passes.
  bool matches(String title) => this == any || NativeCore.instance == null || titleLanguage(title) == this;
}

/// The language [title] is most likely in, or [ExploreLanguage.any] when
/// it gives nothing to go by: by its script, and for Latin letters by its
/// small words (native/lumtub_core/src/filter.rs). Without the library
/// every title passes.
/// Explore filters every list again on each pass, so answers are kept.
ExploreLanguage titleLanguage(String title) {
  final core = NativeCore.instance;
  if (core == null) return ExploreLanguage.any;
  if (_languages[title] case final known?) return known;
  final index = core.withText(title, core.titleLanguage);
  final language = index < ExploreLanguage.values.length ? ExploreLanguage.values[index] : ExploreLanguage.any;
  if (_languages.length >= 4000) _languages.remove(_languages.keys.first);
  return _languages[title] = language;
}

final _languages = <String, ExploreLanguage>{};
