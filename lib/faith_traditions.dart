import 'explore_filters.dart';
import 'models.dart';

/// The traditions 宗教与信仰's zones are about, as a tree: a branch of a
/// faith is a child of it. A zone of one tradition searches YouTube, which
/// answers with whatever its words bring up: a search for Catholic Bible
/// study brings Protestant sermons, a search for Orthodox liturgy brings
/// Byzantine Catholic ones. Each tradition lists the words a title, channel
/// name or description says it by, so that a zone keeps to its own.
///
/// [strong] words name the tradition (天主教, Catholic, 东正教); [weak]
/// words lean towards it (弥撒, 牧师, sermon) but are said elsewhere too.
/// In Chinese, 基督教 is what Protestants call themselves, and 天主教 the
/// Catholic Church: 基督教 is a Protestant word here, 基督宗教 the
/// Christian one.
///
/// Nothing here says what a channel or a person believes: the words only
/// sort a search's videos into the zone that searched for them.
enum FaithTradition {
  christianity(
    null,
    strong: ['christ\$', 'christian', 'christianity', 'jesus', 'cristiano\$', 'cristiana\$', 'cristianos\$', 'cristianas\$', 'cristiani\$', 'cristianismo', 'cristianesimo', 'crista\$', 'cristao\$', 'cristaos\$', 'chretien', 'christlich', 'chrzescij', 'kristiyano', 'χριστιαν', 'христиан', 'христос', 'иисус', '基督', '耶稣', '耶穌', 'キリスト', '그리스도', '예수'],
    weak: ['kristen\$', 'bible', 'biblical', 'gospel', 'church', 'chiesa', 'iglesia', 'igreja', 'eglise', 'kirche', 'kosciol', 'церков', '圣经', '聖經', '福音', '教会', '教會', '教堂', '聖書', '성경'],
  ),
  catholic(
    christianity,
    strict: true,
    strong: [
      'catholic', 'catholicism', 'cattolic', 'catolic', 'catholique', 'katho', 'katolick', 'katolik', 'katoliko', 'καθολικ', 'католи',
      'vatican', 'vaticano', 'vatikan', 'watykan', 'pope\$', 'popes\$', 'papal', 'pontifex', 'papa francesco', 'papa francisco', 'papa leone', 'papa leon', 'pope leo', 'pope francis', 'pope benedict', 'papst',
      'latin mass', 'tridentine', 'jesuit', 'gesuit', 'jesuita', 'opus dei', 'ewtn', 'word on fire', 'bishop barron', 'ascension presents', 'catholic answers', 'pints with aquinas', 'radio veritas', 'vatican news',
      '天主教', '天主', '教宗', '梵蒂冈', '梵蒂岡', '思高', '耶稣会', '耶穌會', '光启社', '光啟社', '真理电台', '真理電台', 'カトリック', '천주교', '가톨릭',
    ],
    weak: [
      'holy mass', 'santa messa', 'santa misa', 'santa missa', 'sainte messe', 'heilige messe', 'msza swieta', 'misa\$', 'rosary', 'rosario', 'rosaire', 'rosenkranz', 'rozaniec',
      'eucharistic adoration', 'adorazione eucaristica', 'our lady', 'marian', 'virgen', 'nossa senhora', 'notre dame', 'novena', 'gregorian', 'gregorien', 'gregorianisch', 'liturgy of the hours', 'divine office', 'breviary', 'compline', '额我略', '額我略', '格里高利圣咏', '格列高利', '日课', '日課', 'parish', 'parrocchia', 'parroquia', 'paroquia', 'paroisse', 'parafia', 'pfarrei',
      'diocese', 'diocesi', 'diocesis', 'archdiocese', 'franciscan', 'francescan', 'franciscano', 'dominican order', 'benedictine', 'carmelite', 'carmelitan', 'salesian', 'salesiani', 'magisterium', 'catechism of the catholic church',
      '弥撒', '彌撒', '神父', '圣母', '聖母', '玫瑰经', '玫瑰經', '修女', '圣体', '聖體', '告解', '要理问答', '要理問答', '公教报', '公教報', '教皇', '教区', '教區', '堂区', '堂區', '方济各', '方濟各', '道明会', '道明會', '圣言会', '聖言會', '慈幼会', '慈幼會', 'ミサ', '미사', '신부님', '성당',
    ],
  ),
  easternCatholic(
    catholic,
    strict: true,
    strong: [
      'eastern catholic', 'byzantine catholic', 'greek catholic', 'ukrainian catholic', 'ruthenian', 'ugcc\$', 'maronite', 'melkite', 'chaldean', 'syro malabar', 'syro malankara', 'syriac catholic', 'coptic catholic', 'armenian catholic', 'ethiopian catholic', 'eritrean catholic',
      'greckokatolick', 'грекокатол', 'греко католи', 'cattolica bizantina', 'cattolici di rito orientale', 'italo albanes', 'italo greca',
      '东方礼', '東方禮', '东仪', '東儀', '希腊礼', '希臘禮', '拜占庭礼', '拜占庭禮', '马龙派', '馬龍派', '默基特', '迦勒底礼', '迦勒底禮',
    ],
  ),
  orthodox(
    christianity,
    strict: true,
    strong: [
      'eastern orthodox', 'orthodox church', 'orthodox christian', 'orthodox faith', 'orthodox priest', 'orthodox monk', 'greek orthodox', 'russian orthodox', 'serbian orthodox', 'romanian orthodox', 'bulgarian orthodox', 'georgian orthodox', 'ukrainian orthodox', 'antiochian', 'mount athos', 'athos', '阿索斯', 'ancient faith',
      'ortodoss', 'ortodox', 'orthodoxe', 'prawoslaw', 'православ', 'ορθοδοξ', 'ορθόδοξ', '东正教', '東正教', '正教会', '正教會', '정교회',
    ],
    weak: ['orthodox', 'divine liturgy', 'theotokos', 'hesychasm', 'jesus prayer', 'монастыр', 'батюшк', 'литурги', '神甫', '圣像', '聖像', '事奉圣礼', '事奉聖禮'],
  ),
  orientalOrthodox(
    christianity,
    strict: true,
    strong: [
      'oriental orthodox', 'coptic', 'copt\$', 'copts\$', 'armenian apostolic', 'armenian church', 'syriac orthodox', 'ethiopian orthodox', 'tewahedo', 'eritrean orthodox', 'malankara orthodox', 'indian orthodox',
      'copto', 'copte', 'kopt', 'копт', 'ኦርቶዶክስ', 'ተዋሕዶ', 'հայ առաքելական', '科普特', '亚美尼亚使徒', '亞美尼亞使徒', '叙利亚正教', '敘利亞正教', '埃塞俄比亚正教', '衣索比亚正教', '衣索比亞正教', '东方正统', '東方正統', '东方正教会', '東方正教會',
    ],
    weak: ['pope tawadros', 'pope shenouda', 'abune', 'qurbana', 'kidase'],
  ),
  protestant(
    christianity,
    strict: true,
    strong: [
      'protestan', 'evangelic', 'evangeliq', 'evangelisch', 'ewangelick', 'евангелич', 'reformation', 'adventist', 'avventist', 'adventista', 'mennonite', 'quaker', 'moravian', 'salvation army',
      'desiring god', 'ligonier', 'grace to you', 'gospel coalition', 'hillsong', 'elevation worship', 'elevation church', 'bethel music', 'maverick city', 'saddleback', 'bibleproject', 'bible project',
      '新教', '基督教', '基督新教', '更正教', '复临', '復臨', '救世军', '救世軍', '赞美之泉', '讚美之泉', '小羊诗歌', '小羊詩歌', '灵粮堂', '靈糧堂', '良友电台', '良友電台', '远东广播', '遠東廣播', '宣道会', '宣道會', '中华基督教会', '中華基督教會', '基督徒聚会', '基督徒聚會',
      'プロテスタント', '개신교', '기독교', '복음주의',
    ],
    weak: [
      'pastor\$', 'pastors\$', 'pastores\$', 'pastore\$', 'pasteur\$', 'пастор', 'sermon', 'worship', 'praise and worship', 'megachurch', 'altar call', 'sola scriptura', 'kjv\$', 'niv\$', 'esv\$',
      '牧师', '牧師', '传道人', '傳道人', '讲道', '講道', '证道', '證道', '主日崇拜', '主日信息', '主日学', '主日學', '敬拜', '团契', '團契', '灵修', '靈修', '和合本', '赞美诗', '讚美詩', '上帝', '弟兄姊妹',
      '목사', '설교', '찬양', '예배', '교회',
    ],
  ),
  lutheran(protestant, strict: true, strong: ['lutheran', 'luther', 'luteran', 'lutherien', 'lutherisch', 'лютеран', '路德', '信义', '信義', 'ルーテル', '루터']),
  reformed(protestant, strict: true, strong: ['reformed', 'calvin', 'presbyterian', 'puritan', 'westminster confession', 'heidelberg catechism', 'reformiert', 'riformat', 'reformad', 'kalwin', '改革宗', '归正', '歸正', '长老会', '長老會', '加尔文', '加爾文', '清教徒', '장로', '개혁']),
  anglican(protestant, strict: true, strong: ['anglican', 'episcopal', 'church of england', 'archbishop of canterbury', 'book of common prayer', 'anglikan', 'anglicano', 'англикан', '圣公会', '聖公會', '安立甘', '聖公会', '성공회'], weak: ['evensong', 'choral evensong']),
  methodist(protestant, strict: true, strong: ['methodist', 'wesley', 'metodist', 'methodiste', 'methodistisch', 'методист', '卫理', '衛理', '循道', 'メソジスト', '감리']),
  baptist(protestant, strict: true, strong: ['baptist', 'bautista', 'batista', 'baptiste', 'battista', 'baptyst', 'баптист', '浸信', '浸礼会', '浸禮會', 'バプテスト', '침례']),
  pentecostal(protestant, strict: true, strong: ['pentecostal', 'charismatic', 'assemblies of god', 'assembly of god', 'pentecostale', 'pfingst', 'pentecost church', 'пятидесятн', '五旬节', '五旬節', '灵恩', '靈恩', '神召会', '神召會', '순복음', '오순절']),
  evangelical(protestant, strict: true, strong: ['evangelical', 'evangelikal', 'evangelicals', '福音派', '복음주의']),
  otherChurches(
    christianity,
    strict: true,
    strong: [
      'latter day saint', 'latter day saints', 'mormon', 'book of mormon', 'lds\$', 'jehovahs witness', 'jw.org', 'jw broadcasting', 'watchtower', 'iglesia ni cristo', 'christian science', 'christadelphian', 'unitarian', 'oneness pentecostal', 'true jesus church', 'living stream',
      '摩门', '摩門', '后期圣徒', '後期聖徒', '耶和华见证人', '耶和華見證人', '守望台', '真耶稣教会', '真耶穌教會', '地方召会', '地方召會', '召会', '召會', '水流职事', '水流職事', '基督科学', '基督科學', '一位论', '一位論',
    ],
  ),
  messianic(christianity, strong: ['messianic', 'jews for jesus', 'yeshua', '弥赛亚犹太', '彌賽亞猶太', '弥赛亚信徒', '彌賽亞信徒']),
  islam(
    null,
    strong: ['islam', 'muslim', 'moslem', 'musulman', 'musulmano', 'quran', 'qur an', 'koran', 'coran', 'mosque', 'masjid', 'moschea', 'mezquita', 'khutbah', 'hadith', 'seerah', 'sunnah', 'tafsir', 'الإسلام', 'إسلام', 'القرآن', 'مسجد', 'ислам', 'мусульман', '伊斯兰', '伊斯蘭', '穆斯林', '回教', '古兰经', '古蘭經', '可兰经', '可蘭經', '清真寺', '圣训', '聖訓', 'イスラム', '이슬람'],
    weak: ['allah', 'imam\$', 'sheikh', 'ramadan', 'ramadhan', 'eid\$', 'halal', 'nasheed', 'jumuah', 'jummah', 'dua\$', '真主', '先知穆罕默德', '斋月', '齋月'],
  ),
  sunni(islam, strong: ['sunni', 'ahlus sunnah', 'ahl al sunnah', 'salafi', '逊尼', '遜尼'], weak: ['hanafi', 'maliki', 'shafi', 'hanbali', 'deobandi', 'barelvi']),
  shia(islam, strong: ['shia\$', 'shiite', 'shi a\$', 'ahlul bayt', 'ahl al bayt', 'imam hussain', 'imam husayn', 'imam ali', 'karbala', 'twelver', 'شيعة', 'شيعي', '什叶', '什葉'], weak: ['muharram', 'ashura', 'majlis', 'noha', 'nauha', 'ayatollah']),
  ahmadiyya(islam, strong: ['ahmadiyya', 'ahmadi\$', 'ahmadis\$', 'mta international', 'khalifatul masih', '艾哈迈迪', '艾哈邁迪']),
  buddhism(
    null,
    strong: ['buddhism', 'buddhist', 'buddha', 'budis', 'buddismo', 'budismo', 'bouddh', 'будд', 'พุทธ', 'phat giao', 'phật', '佛教', '佛法', '佛陀', '佛经', '佛經', '佛学', '佛學', '菩萨', '菩薩', '仏教', '불교', '부처'],
    weak: ['dharma', 'sutra', 'sangha', 'bhikkhu', 'bhikkhuni', 'bodhisattva', 'nirvana', 'mantra', '法师', '法師', '开示', '開示', '寺院', '经忏', '經懺', '居士', '念经', '念經', '诵经', '誦經', '禅修', '禪修', '스님'],
  ),
  chineseBuddhism(buddhism, strong: ['chinese buddhism', '汉传', '漢傳', '人间佛教', '人間佛教', '佛光山', '法鼓山', '慈济', '慈濟', '中台禅寺', '中台禪寺']),
  zen(buddhism, strong: ['zen\$', 'chan buddhism', 'soto\$', 'rinzai', 'zazen', '禅宗', '禪宗', '禅师', '禪師', '曹洞', '临济', '臨濟', '坐禅', '坐禪', '公案', '禅寺', '禪寺', '선불교'], weak: ['koan']),
  pureLand(buddhism, strong: ['pure land', 'amitabha', 'amida', 'nembutsu', 'jodo\$', 'jodo shinshu', 'shin buddhism', '净土', '淨土', '念佛', '阿弥陀', '阿彌陀', '浄土', '念仏'], weak: ['往生']),
  tibetanBuddhism(
    buddhism,
    strong: ['tibetan buddhism', 'tibetan buddhist', 'vajrayana', 'rinpoche', 'dalai lama', 'karmapa', 'dzogchen', 'mahamudra', 'nyingma', 'kagyu', 'gelug', 'sakya', '藏传', '藏傳', '仁波切', '喇嘛', '活佛', '达赖', '達賴', '噶玛巴', '噶瑪巴', '金刚乘', '金剛乘', '大圆满', '大圓滿', '格鲁派', '格魯派', '宁玛', '寧瑪', '噶举', '噶舉', '萨迦', '薩迦'],
    weak: ['lama\$', 'tibetan', '密宗', '上师', '上師', '西藏'],
  ),
  theravada(buddhism, strong: ['theravada', 'thai forest', 'ajahn', 'bhante', 'pali canon', 'therav', '南传', '南傳', '上座部', '阿姜'], weak: ['vipassana', 'satipatthana', 'anapanasati', '内观', '內觀', '四念处', '四念處', '巴利']),
  nichiren(buddhism, strong: ['nichiren', 'soka gakkai', 'sgi\$', 'nam myoho', 'daimoku', '日莲', '日蓮', '创价', '創價', '南无妙法莲华经', '南無妙法蓮華經', '創価']),
  chineseReligion(null, strong: ['chinese religion', 'chinese folk religion', '国学', '國學', '易经', '易經', '周易', '中国神话', '中國神話'], weak: ['传统文化', '傳統文化']),
  taoism(chineseReligion, strong: ['taoism', 'taoist', 'daoism', 'daoist', 'tao te ching', 'dao de jing', 'laozi', 'lao tzu', 'zhuangzi', 'chuang tzu', '道教', '道观', '道觀', '道长', '道長', '道德经', '道德經', '庄子', '莊子', '内丹', '內丹', '天师', '天師', '道家'], weak: ['qigong', 'neidan', '炼丹', '煉丹', '符箓', '符籙', '养生', '養生']),
  confucianism(chineseReligion, strong: ['confucian', 'confucius', 'mencius', 'analects', '儒家', '儒学', '儒學', '儒教', '孔子', '孟子', '论语', '論語', '朱熹', '王阳明', '王陽明']),
  folkReligion(chineseReligion, strong: ['mazu', 'matsu', '妈祖', '媽祖', '城隍', '关公', '關公', '关帝', '關帝', '土地公', '庙会', '廟會', '民间信仰', '民間信仰', '绕境', '遶境', '进香', '進香']),
  yiguandao(null, strong: ['yiguandao', 'i kuan tao', '一贯道', '一貫道']),
  hinduism(
    null,
    strong: ['hindu', 'hinduism', 'sanatan', 'vedanta', 'vedic', 'bhagavad', 'gita\$', 'upanishad', 'krishna', 'shiva', 'vishnu', 'iskcon', 'hare krishna', 'ramayana', 'mahabharata', 'mandir', 'puja', 'aarti', 'hindou', 'induis', 'индуи', 'हिन्दू', 'हिंदू', 'सनातन', 'कृष्ण', 'शिव', '印度教', '毗湿奴', '毗濕奴', '湿婆', '濕婆', '薄伽梵歌', '奥义书', '奧義書', 'ヒンドゥー', '힌두'],
    weak: ['swami', 'bhajan', 'mantra', 'yoga', 'guru\$', 'ganesh', 'durga', 'hanuman', 'diwali', 'brahman', 'atman', 'भगवान', '瑜伽'],
  ),
  judaism(
    null,
    strong: ['jewish', 'judaism', 'judaic', 'torah', 'talmud', 'rabbi', 'synagogue', 'shabbat', 'chabad', 'mishnah', 'halacha', 'kabbalah', 'ebraic', 'judio', 'judaismo', 'juif', 'judaique', 'judisch', 'judentum', 'zydow', 'еврей', 'иудаи', 'יהוד', 'תורה', 'רבי', '犹太', '猶太', '妥拉', '塔木德', '拉比', '犹太会堂', '猶太會堂', 'ユダヤ', '유대'],
    weak: ['hebrew', 'kosher', 'passover', 'hanukkah', 'yom kippur', 'rosh hashanah', 'parsha', 'shul\$', 'yiddish', '希伯来', '希伯來', '逾越节', '逾越節'],
  ),
  sikhism(null, strong: ['sikh\$', 'sikhs\$', 'sikhism', 'gurbani', 'waheguru', 'gurdwara', 'gurudwara', 'guru nanak', 'guru granth', 'khalsa', 'ਵਾਹਿਗੁਰੂ', 'ਗੁਰਬਾਣੀ', '锡克', '錫克'], weak: ['kirtan', 'shabad', 'katha']),
  jainism(null, strong: ['jain\$', 'jains\$', 'jainism', 'jaina', 'mahavira', 'tirthankara', 'jinvani', 'जैन', '耆那']),
  shinto(null, strong: ['shinto', 'jinja', 'kami\$', '神道', '神社', '神宮', '神宫'], weak: ['shrine', 'torii', '鳥居', '鸟居']),
  bahai(null, strong: ['bahai', 'bahaullah', 'abdul baha', '巴哈伊', '巴哈欧拉', '巴哈歐拉', 'バハイ']),
  zoroastrianism(null, strong: ['zoroastrian', 'zarathustra', 'zoroaster', 'zarathushtra', 'parsi\$', 'avesta', '琐罗亚斯德', '瑣羅亞斯德', '祆教', '拜火教']);

  const FaithTradition(this.parent, {this.strict = false, this.strong = const [], this.weak = const []});

  /// The tradition this one is a branch of.
  final FaithTradition? parent;

  /// The zone keeps only videos that say this tradition (or one of its
  /// branches) by name or by its usual words, besides leaving out those
  /// that say another. Set for Christianity's churches, whose videos are
  /// most alike and get mixed up most: a Catholic zone shows no sermon
  /// that says nothing of the Church it comes from. For other traditions
  /// a video that names none is kept, since its search found it.
  final bool strict;

  /// Words that name the tradition. A word ending in `$` is matched as a
  /// whole word only (pope, not Popeye); others also as the start of a
  /// longer word (catholic, catholics, catholicism).
  final List<String> strong;
  final List<String> weak;

  /// The traditions above this one, nearest first.
  Iterable<FaithTradition> get ancestors sync* {
    for (var t = parent; t != null; t = t.parent) {
      yield t;
    }
  }

  /// This tradition and every branch of it, at any depth.
  Iterable<FaithTradition> get family => values.where((t) => t == this || t.ancestors.contains(this));

  /// The branches whose words count against this tradition: every
  /// sibling's family, every ancestor's siblings' families and every other
  /// faith. A tradition's ancestors count neither way: 基督宗教 in a
  /// Catholic video's title says nothing against it.
  List<List<FaithTradition>> get rivals {
    final branches = <List<FaithTradition>>[];
    final line = [this, ...ancestors];
    for (final t in line) {
      for (final other in values.where((o) => o.parent == t.parent && o != t)) {
        branches.add(other.family.toList());
      }
    }
    return branches;
  }

  /// Whether [item] belongs in a zone of this tradition: it says this
  /// tradition at least as much as any one other. A strong word counts
  /// two, a weak one one. A video naming none is kept unless [strict].
  ///
  /// "天主教和基督教的区别" says both as much and is kept by both; "东正教神父"
  /// says 神父 (Catholic, weak) and 东正教 (strong) and is kept by
  /// Orthodoxy alone.
  bool admits(VideoItem item, {required bool strict}) => admitsText(textOf(item), strict: strict);

  /// [admits] for text already put through [normalizeFaithText].
  bool admitsText(String text, {required bool strict}) {
    final own = _scoreOf(family, text);
    var rival = 0;
    for (final branch in rivals) {
      final score = _scoreOf(branch, text);
      if (score > rival) rival = score;
    }
    if (own == 0) return rival == 0 && !strict;
    return own >= rival;
  }

  /// What a video says of itself: title, channel and the description's
  /// start, as [normalizeFaithText] writes it.
  static String textOf(VideoItem item) => normalizeFaithText('${item.title}\n${item.channel}\n${item.description ?? ''}');

  /// The tradition a zone keeps to: its own, else its parent's. Null for a
  /// zone about no one tradition, as world religions.
  static FaithTradition? of(Iterable<FaithTradition?> nearestFirst) {
    for (final t in nearestFirst) {
      if (t != null) return t;
    }
    return null;
  }

  static int _scoreOf(Iterable<FaithTradition> traditions, String text) {
    var score = 0;
    for (final t in traditions) {
      for (final word in _markers[t.index].strong) {
        if (word.foundIn(text)) score += 2;
      }
      for (final word in _markers[t.index].weak) {
        if (word.foundIn(text)) score += 1;
      }
    }
    return score;
  }

  /// Each tradition's words, without those another of its words already
  /// finds: "christianity" is found by "christian", "lutheran" by
  /// "luther", so a title saying it once counts once.
  static final _markers = [
    for (final t in values)
      () {
        final strong = t.strong.map(_Marker.new).toList();
        final weak = t.weak.map(_Marker.new).toList();
        bool covered(_Marker m, List<_Marker> by) => by.any((o) => !identical(o, m) && o.covers(m));
        return (
          strong: [for (final m in strong) if (!covered(m, strong)) m],
          weak: [for (final m in weak) if (!covered(m, [...strong, ...weak])) m],
        );
      }(),
  ];
}

/// The explore languages the words are written for. In another language
/// a video naming nothing cannot be told from one naming something not
/// listed, so no zone there keeps only the videos that name it.
const faithMarkerLanguages = {
  ExploreLanguage.any,
  ExploreLanguage.zh,
  ExploreLanguage.ja,
  ExploreLanguage.ko,
  ExploreLanguage.en,
  ExploreLanguage.es,
  ExploreLanguage.fr,
  ExploreLanguage.de,
  ExploreLanguage.pt,
  ExploreLanguage.ru,
  ExploreLanguage.it,
  ExploreLanguage.pl,
  ExploreLanguage.uk,
  ExploreLanguage.el,
};

/// [text] in lower case, without Latin accents and apostrophes, with
/// hyphens and other punctuation as spaces: "Greek-Catholic" and "greek
/// catholic", "Jehovah's" and "jehovahs", "católico" and "catolico" read
/// alike.
String normalizeFaithText(String text) {
  final out = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    if (_apostrophes.contains(char)) continue;
    final plain = _plain[char];
    if (plain != null) {
      out.write(plain);
    } else if (_spaces.contains(char)) {
      out.write(' ');
    } else {
      out.write(char);
    }
  }
  return out.toString();
}

const _apostrophes = {"'", '’', '‘', 'ʼ', 'ʻ', '`', '´'};
const _spaces = {'-', '–', '—', '_', '/', '|', '·', '・', ':', ',', '.', '!', '?', '(', ')', '[', ']', '"', '“', '”', '«', '»', '#'};
const _plain = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ą': 'a', 'ă': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ę': 'e', 'ě': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ů': 'u',
  'ñ': 'n', 'ń': 'n', 'ç': 'c', 'ć': 'c', 'č': 'c', 'ł': 'l', 'ś': 's', 'š': 's', 'ș': 's', 'ş': 's', 'ź': 'z', 'ż': 'z', 'ž': 'z', 'ț': 't', 'ţ': 't', 'ý': 'y', 'ř': 'r', 'đ': 'd',
};

/// One word of [FaithTradition]: written in a script that leaves spaces
/// between words, it must start a word; ending in `$`, it must be one.
/// In Chinese, Japanese and Korean it may stand anywhere.
class _Marker {
  _Marker(String written)
      : whole = written.endsWith(r'$'),
        word = normalizeFaithText(written.endsWith(r'$') ? written.substring(0, written.length - 1) : written),
        anywhere = _unspaced.hasMatch(written);

  final String word;
  final bool whole;
  final bool anywhere;

  static final _unspaced = RegExp(r'[぀-ヿ㐀-鿿豈-﫿가-힯]');
  static final _letter = RegExp(r'[\p{L}\p{N}\p{M}]', unicode: true);

  /// Whether every text this marker finds, [other] finds as well.
  bool covers(_Marker other) {
    if (whole) return false;
    return anywhere ? other.word.contains(word) : other.word.startsWith(word) && !other.anywhere;
  }

  bool foundIn(String text) {
    if (anywhere) return text.contains(word);
    for (var at = text.indexOf(word); at >= 0; at = text.indexOf(word, at + 1)) {
      if (at > 0 && _letter.hasMatch(text[at - 1])) continue;
      final end = at + word.length;
      if (whole && end < text.length && _letter.hasMatch(text[end])) continue;
      return true;
    }
    return false;
  }
}
