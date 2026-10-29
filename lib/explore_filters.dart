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
  // East Asia
  cn('中国大陆', 'CN'),
  tw('台湾', 'TW'),
  hk('香港', 'HK'),
  jp('日本', 'JP'),
  kr('韩国', 'KR'),
  // Southeast Asia
  sg('新加坡', 'SG'),
  my('马来西亚', 'MY'),
  th('泰国', 'TH'),
  vn('越南', 'VN'),
  id('印度尼西亚', 'ID'),
  ph('菲律宾', 'PH'),
  kh('柬埔寨', 'KH'),
  la('老挝', 'LA'),
  // South and Central Asia
  india('印度', 'IN'),
  pk('巴基斯坦', 'PK'),
  bd('孟加拉国', 'BD'),
  lk('斯里兰卡', 'LK'),
  np('尼泊尔', 'NP'),
  kz('哈萨克斯坦', 'KZ'),
  // Middle East
  turkey('土耳其', 'TR'),
  il('以色列', 'IL'),
  sa('沙特阿拉伯', 'SA'),
  ae('阿联酋', 'AE'),
  qa('卡塔尔', 'QA'),
  kw('科威特', 'KW'),
  bh('巴林', 'BH'),
  om('阿曼', 'OM'),
  jo('约旦', 'JO'),
  lb('黎巴嫩', 'LB'),
  iq('伊拉克', 'IQ'),
  ye('也门', 'YE'),
  // Europe
  gb('英国', 'GB'),
  ie('爱尔兰', 'IE'),
  fr('法国', 'FR'),
  de('德国', 'DE'),
  at('奥地利', 'AT'),
  ch('瑞士', 'CH'),
  nl('荷兰', 'NL'),
  be('比利时', 'BE'),
  lu('卢森堡', 'LU'),
  es('西班牙', 'ES'),
  pt('葡萄牙', 'PT'),
  it('意大利', 'IT'),
  mt('马耳他', 'MT'),
  gr('希腊', 'GR'),
  cy('塞浦路斯', 'CY'),
  se('瑞典', 'SE'),
  no('挪威', 'NO'),
  dk('丹麦', 'DK'),
  fi('芬兰', 'FI'),
  iceland('冰岛', 'IS'),
  pl('波兰', 'PL'),
  cz('捷克', 'CZ'),
  sk('斯洛伐克', 'SK'),
  hu('匈牙利', 'HU'),
  ro('罗马尼亚', 'RO'),
  bg('保加利亚', 'BG'),
  hr('克罗地亚', 'HR'),
  si('斯洛文尼亚', 'SI'),
  rs('塞尔维亚', 'RS'),
  ba('波黑', 'BA'),
  me('黑山', 'ME'),
  mk('北马其顿', 'MK'),
  ee('爱沙尼亚', 'EE'),
  lv('拉脱维亚', 'LV'),
  lt('立陶宛', 'LT'),
  ua('乌克兰', 'UA'),
  by('白俄罗斯', 'BY'),
  md('摩尔多瓦', 'MD'),
  ge('格鲁吉亚', 'GE'),
  az('阿塞拜疆', 'AZ'),
  ru('俄罗斯', 'RU'),
  // Americas
  us('美国', 'US'),
  ca('加拿大', 'CA'),
  mx('墨西哥', 'MX'),
  br('巴西', 'BR'),
  ar('阿根廷', 'AR'),
  cl('智利', 'CL'),
  co('哥伦比亚', 'CO'),
  pe('秘鲁', 'PE'),
  ve('委内瑞拉', 'VE'),
  ec('厄瓜多尔', 'EC'),
  bo('玻利维亚', 'BO'),
  py('巴拉圭', 'PY'),
  uy('乌拉圭', 'UY'),
  cr('哥斯达黎加', 'CR'),
  pa('巴拿马', 'PA'),
  gt('危地马拉', 'GT'),
  hn('洪都拉斯', 'HN'),
  sv('萨尔瓦多', 'SV'),
  ni('尼加拉瓜', 'NI'),
  dominican('多米尼加', 'DO'),
  pr('波多黎各', 'PR'),
  jm('牙买加', 'JM'),
  // Africa
  eg('埃及', 'EG'),
  ma('摩洛哥', 'MA'),
  dz('阿尔及利亚', 'DZ'),
  tn('突尼斯', 'TN'),
  ly('利比亚', 'LY'),
  ng('尼日利亚', 'NG'),
  gh('加纳', 'GH'),
  sn('塞内加尔', 'SN'),
  ke('肯尼亚', 'KE'),
  tz('坦桑尼亚', 'TZ'),
  ug('乌干达', 'UG'),
  za('南非', 'ZA'),
  zw('津巴布韦', 'ZW'),
  // Oceania
  au('澳大利亚', 'AU'),
  nz('新西兰', 'NZ'),
  pg('巴布亚新几内亚', 'PG');

  const ExploreRegion(this._label, this.gl);
  final String _label;
  String get label => tr(_label);
  final String gl;

  static ExploreRegion parse(Object? raw) => values.where((r) => r.name == raw).firstOrNull ?? any;

  /// The language the region searches in, so a zone's words find its own
  /// videos; English where explore offers no language of the region's.
  ExploreLanguage get searchLanguage => switch (gl) {
        '' => ExploreLanguage.any,
        'CN' || 'TW' || 'HK' => ExploreLanguage.zh,
        'JP' => ExploreLanguage.ja,
        'KR' => ExploreLanguage.ko,
        'MY' => ExploreLanguage.ms,
        'TH' => ExploreLanguage.th,
        'VN' => ExploreLanguage.vi,
        'ID' => ExploreLanguage.id,
        'PH' => ExploreLanguage.tl,
        'IN' => ExploreLanguage.hi,
        'PK' => ExploreLanguage.ur,
        'BD' => ExploreLanguage.bn,
        'TR' => ExploreLanguage.turkish,
        'IL' => ExploreLanguage.he,
        'SA' || 'AE' || 'QA' || 'KW' || 'BH' || 'OM' || 'JO' || 'LB' || 'IQ' || 'YE' || 'EG' || 'MA' || 'DZ' || 'TN' || 'LY' => ExploreLanguage.ar,
        'FR' || 'BE' || 'LU' || 'SN' => ExploreLanguage.fr,
        'DE' || 'AT' || 'CH' => ExploreLanguage.de,
        'NL' => ExploreLanguage.nl,
        'ES' || 'MX' || 'AR' || 'CL' || 'CO' || 'PE' || 'VE' || 'EC' || 'BO' || 'PY' || 'UY' || 'CR' || 'PA' || 'GT' || 'HN' || 'SV' || 'NI' || 'DO' || 'PR' => ExploreLanguage.es,
        'PT' || 'BR' => ExploreLanguage.pt,
        'IT' => ExploreLanguage.it,
        'GR' || 'CY' => ExploreLanguage.el,
        'SE' => ExploreLanguage.sv,
        'NO' => ExploreLanguage.no,
        'DK' => ExploreLanguage.da,
        'FI' => ExploreLanguage.fi,
        'PL' => ExploreLanguage.pl,
        'CZ' || 'SK' => ExploreLanguage.cs,
        'HU' => ExploreLanguage.hu,
        'RO' || 'MD' => ExploreLanguage.ro,
        'UA' => ExploreLanguage.uk,
        'RU' || 'BY' || 'KZ' => ExploreLanguage.ru,
        _ => ExploreLanguage.en,
      };
}

/// The language explore's videos are spoken in. Each video is asked
/// (VideoLanguages); without an answer its title's script and small words
/// decide, which only the first fourteen can be told by.
enum ExploreLanguage {
  // The order is the Rust core's `Language`; new ones go at the end.
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
  vi('越南语'),
  it('意大利语'),
  nl('荷兰语'),
  turkish('土耳其语'),
  id('印尼语'),
  ms('马来语'),
  tl('菲律宾语'),
  pl('波兰语'),
  uk('乌克兰语'),
  cs('捷克语'),
  ro('罗马尼亚语'),
  hu('匈牙利语'),
  el('希腊语'),
  sv('瑞典语'),
  no('挪威语'),
  da('丹麦语'),
  fi('芬兰语'),
  he('希伯来语'),
  fa('波斯语'),
  ur('乌尔都语'),
  bn('孟加拉语'),
  ta('泰米尔语'),
  te('泰卢固语');

  const ExploreLanguage(this._label);
  final String _label;
  String get label => tr(_label);

  static ExploreLanguage parse(Object? raw) => values.where((l) => l.name == raw).firstOrNull ?? any;

  /// Whether [title] reads as this language.
  /// Without the library every title passes.
  bool matches(String title) => this == any || NativeCore.instance == null || titleLanguage(title) == this;

  /// The language's ISO 639-1 code, which translation takes.
  String get code => this == turkish ? 'tr' : name;

  /// The country most of the language's videos come from, searched as
  /// from when no region is picked; null where no one country leads.
  String? get homeCountry => switch (this) {
        any || zh || en || es || ar => null,
        ja => 'JP',
        ko => 'KR',
        fr => 'FR',
        de => 'DE',
        pt => 'BR',
        ru => 'RU',
        hi || ta || te => 'IN',
        th => 'TH',
        vi => 'VN',
        it => 'IT',
        nl => 'NL',
        turkish => 'TR',
        id => 'ID',
        ms => 'MY',
        tl => 'PH',
        pl => 'PL',
        uk => 'UA',
        cs => 'CZ',
        ro => 'RO',
        hu => 'HU',
        el => 'GR',
        sv => 'SE',
        no => 'NO',
        da => 'DK',
        fi => 'FI',
        he => 'IL',
        fa => 'IR',
        ur => 'PK',
        bn => 'BD',
      };
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

/// One search from words translated one by one: each kept once, as
/// "园艺 gardening" translates to the same word twice.
String searchWordsOf(List<String> translated) {
  final seen = <String>{};
  return [
    for (final words in translated)
      if (words.trim().isNotEmpty && seen.add(words.trim().toLowerCase())) words.trim(),
  ].join(' ');
}
