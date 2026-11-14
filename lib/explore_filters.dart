import 'l10n/l10n.dart';
import 'native_core.dart';
import 'scripts.dart';

/// A 类型 or 视角 choice in explore: words added to the zone's search, so it
/// leans the results rather than sorting them exactly.
abstract interface class WordFilter {
  String get label;
  String get words;
}

/// 类型 for every zone but 宗教与信仰, whose own list fits it better.
enum ContentFormat implements WordFilter {
  any('Any', ''),
  tutorial('Tutorials', 'tutorial 教程'),
  lecture('Lectures and courses', 'lecture course 课程'),
  documentary('Documentary', 'documentary 纪录片'),
  interview('Interviews and podcasts', 'interview podcast 访谈'),
  review('Reviews', 'review 评测'),
  analysis('Explainers', 'explained analysis 解析'),
  news('News', 'news 新闻'),
  vlog('Vlog', 'vlog'),
  compilation('Compilations', 'compilation 合集');

  const ContentFormat(this._label, this.words);
  final String _label;
  @override
  String get label => tr(_label);
  @override
  final String words;
}

/// 视角 for every zone but 宗教与信仰.
enum ContentView implements WordFilter {
  any('Any', ''),
  beginner('Beginner-friendly', 'beginner explained 入门'),
  expert('In depth', 'in-depth expert 深度'),
  critical('Critical', 'critique criticism 批评'),
  debate('Comparisons and debates', 'debate versus 对比'),
  experience('First-hand', 'my experience 亲身经历');

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
  any('All regions', ''),
  // East Asia
  cn('Mainland China', 'CN'),
  tw('Taiwan', 'TW'),
  hk('Hong Kong', 'HK'),
  jp('Japan', 'JP'),
  kr('South Korea', 'KR'),
  // Southeast Asia
  sg('Singapore', 'SG'),
  my('Malaysia', 'MY'),
  th('Thailand', 'TH'),
  vn('Vietnam', 'VN'),
  id('Indonesia', 'ID'),
  ph('Philippines', 'PH'),
  kh('Cambodia', 'KH'),
  la('Laos', 'LA'),
  // South and Central Asia
  india('India', 'IN'),
  pk('Pakistan', 'PK'),
  bd('Bangladesh', 'BD'),
  lk('Sri Lanka', 'LK'),
  np('Nepal', 'NP'),
  kz('Kazakhstan', 'KZ'),
  // Middle East
  turkey('Türkiye', 'TR'),
  il('Israel', 'IL'),
  sa('Saudi Arabia', 'SA'),
  ae('United Arab Emirates', 'AE'),
  qa('Qatar', 'QA'),
  kw('Kuwait', 'KW'),
  bh('Bahrain', 'BH'),
  om('Oman', 'OM'),
  jo('Jordan', 'JO'),
  lb('Lebanon', 'LB'),
  iq('Iraq', 'IQ'),
  ye('Yemen', 'YE'),
  // Europe
  gb('United Kingdom', 'GB'),
  ie('Ireland', 'IE'),
  fr('France', 'FR'),
  de('Germany', 'DE'),
  at('Austria', 'AT'),
  ch('Switzerland', 'CH'),
  nl('Netherlands', 'NL'),
  be('Belgium', 'BE'),
  lu('Luxembourg', 'LU'),
  es('Spain', 'ES'),
  pt('Portugal', 'PT'),
  it('Italy', 'IT'),
  mt('Malta', 'MT'),
  gr('Greece', 'GR'),
  cy('Cyprus', 'CY'),
  se('Sweden', 'SE'),
  no('Norway', 'NO'),
  dk('Denmark', 'DK'),
  fi('Finland', 'FI'),
  iceland('Iceland', 'IS'),
  pl('Poland', 'PL'),
  cz('Czechia', 'CZ'),
  sk('Slovakia', 'SK'),
  hu('Hungary', 'HU'),
  ro('Romania', 'RO'),
  bg('Bulgaria', 'BG'),
  hr('Croatia', 'HR'),
  si('Slovenia', 'SI'),
  rs('Serbia', 'RS'),
  ba('Bosnia and Herzegovina', 'BA'),
  me('Montenegro', 'ME'),
  mk('North Macedonia', 'MK'),
  ee('Estonia', 'EE'),
  lv('Latvia', 'LV'),
  lt('Lithuania', 'LT'),
  ua('Ukraine', 'UA'),
  by('Belarus', 'BY'),
  md('Moldova', 'MD'),
  ge('Georgia', 'GE'),
  az('Azerbaijan', 'AZ'),
  ru('Russia', 'RU'),
  // Americas
  us('United States', 'US'),
  ca('Canada', 'CA'),
  mx('Mexico', 'MX'),
  br('Brazil', 'BR'),
  ar('Argentina', 'AR'),
  cl('Chile', 'CL'),
  co('Colombia', 'CO'),
  pe('Peru', 'PE'),
  ve('Venezuela', 'VE'),
  ec('Ecuador', 'EC'),
  bo('Bolivia', 'BO'),
  py('Paraguay', 'PY'),
  uy('Uruguay', 'UY'),
  cr('Costa Rica', 'CR'),
  pa('Panama', 'PA'),
  gt('Guatemala', 'GT'),
  hn('Honduras', 'HN'),
  sv('El Salvador', 'SV'),
  ni('Nicaragua', 'NI'),
  dominican('Dominican Republic', 'DO'),
  pr('Puerto Rico', 'PR'),
  jm('Jamaica', 'JM'),
  // Africa
  eg('Egypt', 'EG'),
  ma('Morocco', 'MA'),
  dz('Algeria', 'DZ'),
  tn('Tunisia', 'TN'),
  ly('Libya', 'LY'),
  ng('Nigeria', 'NG'),
  gh('Ghana', 'GH'),
  sn('Senegal', 'SN'),
  ke('Kenya', 'KE'),
  tz('Tanzania', 'TZ'),
  ug('Uganda', 'UG'),
  za('South Africa', 'ZA'),
  zw('Zimbabwe', 'ZW'),
  // Oceania
  au('Australia', 'AU'),
  nz('New Zealand', 'NZ'),
  pg('Papua New Guinea', 'PG');

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
        'CZ' => ExploreLanguage.cs,
        'SK' => ExploreLanguage.sk,
        'BG' => ExploreLanguage.bg,
        'MK' => ExploreLanguage.mk,
        'EE' => ExploreLanguage.et,
        'LV' => ExploreLanguage.lv,
        'LT' => ExploreLanguage.lt,
        'GE' => ExploreLanguage.ka,
        'AZ' => ExploreLanguage.az,
        'IS' => ExploreLanguage.icelandic,
        'KH' => ExploreLanguage.km,
        'LA' => ExploreLanguage.lo,
        'LK' => ExploreLanguage.si,
        'NP' => ExploreLanguage.ne,
        'TZ' => ExploreLanguage.sw,
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
  any('All languages'),
  zh('Chinese'),
  ja('Japanese'),
  ko('Korean'),
  en('English'),
  es('Spanish'),
  fr('French'),
  de('German'),
  pt('Portuguese'),
  ru('Russian'),
  ar('Arabic'),
  hi('Hindi'),
  th('Thai'),
  vi('Vietnamese'),
  it('Italian'),
  nl('Dutch'),
  turkish('Turkish'),
  id('Indonesian'),
  ms('Malay'),
  tl('Filipino'),
  pl('Polish'),
  uk('Ukrainian'),
  cs('Czech'),
  ro('Romanian'),
  hu('Hungarian'),
  el('Greek'),
  sv('Swedish'),
  no('Norwegian'),
  da('Danish'),
  fi('Finnish'),
  he('Hebrew'),
  fa('Persian'),
  ur('Urdu'),
  bn('Bengali'),
  ta('Tamil'),
  te('Telugu'),
  af('Afrikaans'),
  am('Amharic'),
  az('Azerbaijani'),
  be('Belarusian'),
  bg('Bulgarian'),
  eo('Esperanto'),
  et('Estonian'),
  eu('Basque'),
  gl('Galician'),
  gu('Gujarati'),
  hy('Armenian'),
  icelandic('Icelandic'),
  jv('Javanese'),
  ka('Georgian'),
  km('Khmer'),
  kn('Kannada'),
  la('Latin'),
  lo('Lao'),
  lt('Lithuanian'),
  lv('Latvian'),
  mk('Macedonian'),
  ml('Malayalam'),
  mn('Mongolian'),
  mr('Marathi'),
  my('Burmese'),
  ne('Nepali'),
  pa('Punjabi'),
  si('Sinhala'),
  sk('Slovak'),
  sq('Albanian'),
  su('Sundanese'),
  sw('Swahili'),
  ti('Tigrinya'),
  tk('Turkmen'),
  uz('Uzbek');

  const ExploreLanguage(this._label);
  final String _label;
  String get label => tr(_label);

  static ExploreLanguage parse(Object? raw) => values.where((l) => l.name == raw).firstOrNull ?? any;

  /// Whether [title] reads as this language.
  /// Without the library every title passes.
  bool matches(String title) => this == any || NativeCore.instance == null || titleLanguage(title) == this;

  /// The language's ISO 639-1 code, which translation takes.
  String get code => switch (this) {
        turkish => 'tr',
        icelandic => 'is',
        _ => name,
      };

  /// The country most of the language's videos come from, searched as
  /// from when no region is picked; null where no one country leads.
  String? get homeCountry => switch (this) {
        any || zh || en || es || ar || eo || la || sq || ti || am || hy || mn || my || tk || uz => null,
        ja => 'JP',
        ko => 'KR',
        fr => 'FR',
        de => 'DE',
        pt => 'BR',
        ru => 'RU',
        hi || ta || te || gu || kn || ml || mr || pa => 'IN',
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
        af => 'ZA',
        az => 'AZ',
        be => 'BY',
        bg => 'BG',
        et => 'EE',
        eu || gl => 'ES',
        icelandic => 'IS',
        jv || su => 'ID',
        ka => 'GE',
        km => 'KH',
        lo => 'LA',
        lt => 'LT',
        lv => 'LV',
        mk => 'MK',
        ne => 'NP',
        si => 'LK',
        sk => 'SK',
        sw => 'TZ',
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

/// Whether [phrase] has letters outside the Latin alphabet.
bool isTranslatedPhrase(String phrase) => nonLatinLetter.hasMatch(phrase);

/// Lower-case words a search keeps in every language: titles write them
/// the same everywhere.
const keptSearchWords = {
  'asmr', 'bhajan', 'blender', 'cosplay', 'esports', 'haul', 'hip', 'hop', 'imam', 'indie', 'jazz', 'khutbah', 'kirtan', 'lofi', //
  'macos', 'manga', 'mandala', 'metal', 'mukbang', 'nasheed', 'nijisanji', 'podcast', 'pop', 'puja', 'qawwali', 'rabbi', 'rap', //
  'rock', 'seerah', 'speedrun', 'swami', 'tafsir', 'thangka', 'unboxing', 'vlog', 'vtuber', 'yoga',
};

final _commonWord = RegExp(r"^[a-z][a-z'-]{2,}$");

/// Whether [phrase] of a zone's search is put into [language] before it
/// is searched: words in another script always, and for a language other
/// than English, English words as well. "哲学 philosophy lecture" kept its
/// English half in Italian and found English lectures. A run of names
/// alone (Minecraft, Plato) or of [keptSearchWords] is searched as it is.
bool translatesInto(String phrase, ExploreLanguage language) {
  if (isTranslatedPhrase(phrase)) return true;
  if (language == ExploreLanguage.en || language == ExploreLanguage.any) return false;
  return phrase.split(RegExp(r'\s+')).any((word) => _commonWord.hasMatch(word) && !keptSearchWords.contains(word));
}

/// Search words put the same way in every language, as YouTube titles
/// write them.
const searchGlossary = {'直播': 'live', '实况': 'live', '直播间': 'live'};

/// [query] in the pieces a translation keeps the sense of: each keyword of
/// a script written without spaces (Chinese, Japanese, Thai…) alone, as
/// they are listed apart, and each run of words in a spaced script
/// together, since "stand-up comedy live" word by word is "stare in piedi
/// commedia vivere". Latin words and words to translate run apart.
List<String> searchPhrasesOf(String query) {
  final phrases = <String>[];
  var run = <String>[];
  bool? translated;
  for (final word in query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
    final mine = isTranslatedPhrase(word);
    if (unspacedScript.hasMatch(word)) {
      if (run.isNotEmpty) phrases.add(run.join(' '));
      run = [];
      phrases.add(word);
      continue;
    }
    if (run.isNotEmpty && translated != mine) {
      phrases.add(run.join(' '));
      run = [];
    }
    translated = mine;
    run.add(word);
  }
  if (run.isNotEmpty) phrases.add(run.join(' '));
  return phrases;
}

/// One search from words translated one by one: each kept once, as
/// "园艺 gardening" translates to the same word twice.
String searchWordsOf(List<String> translated) {
  final seen = <String>{};
  return [
    for (final words in translated)
      if (words.trim().isNotEmpty && seen.add(words.trim().toLowerCase())) words.trim(),
  ].join(' ');
}
