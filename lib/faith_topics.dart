
import 'explore_filters.dart';
import 'explore_topics.dart';
import 'l10n/l10n.dart';
import 'models.dart';
import 'native_core.dart';
import 'ui/app_icons.dart';

// The zones of 宗教与信仰, one list per tab. Each is a YouTube search, so a
// channel can turn up under every tradition or theme it speaks to; nothing
// here decides what a channel "is".

/// 宗教传统: the traditions, with Christianity's split a level further. Each
/// tradition has about 8-10 sub-categories; Christianity's are its branches.
const faithTraditionTopics = <ExploreTopic>[
  ExploreTopic('Christianity', AppIcons.church, '基督宗教 Christianity', subs: [
    ExploreSub('Catholic', '天主教 Catholic', subs: [
      ExploreSub("The Pope's words", '教宗 讲话 Pope homily'),
      ExploreSub('Vatican news', 'Vatican News 梵蒂冈'),
      ExploreSub('Bible study', 'Catholic Bible study 天主教 圣经'),
      ExploreSub('Catholic theology', 'Catholic theology 天主教 神学'),
      ExploreSub('Church history', 'Catholic Church history 教会历史'),
      ExploreSub('Mass', 'Holy Mass 弥撒'),
      ExploreSub('Sacraments', 'Catholic sacraments 圣事'),
      ExploreSub('Prayer', 'Catholic prayer 天主教 祈祷'),
      ExploreSub('Lives of the saints', 'Catholic saints 圣人'),
      ExploreSub('Religious life', 'Catholic religious life monastery 修会'),
      ExploreSub('Church music', 'Gregorian chant Catholic hymns 圣歌'),
    ]),
    ExploreSub('Eastern Orthodox', 'Orthodox Christianity 东正教', subs: [
      ExploreSub('Orthodox theology', 'Orthodox theology'),
      ExploreSub('Byzantine liturgy', 'Byzantine Divine Liturgy'),
      ExploreSub('Icon art', 'Orthodox icons iconography'),
      ExploreSub('Church Fathers', 'Church Fathers patristics'),
      ExploreSub('Monastic tradition', 'Orthodox monasticism Mount Athos'),
      ExploreSub('Chant', 'Byzantine chant'),
    ]),
    ExploreSub('Protestant', 'Protestant 新教', subs: [
      ExploreSub('Lutheran', 'Lutheran 路德宗'),
      ExploreSub('Reformed', 'Reformed theology 改革宗'),
      ExploreSub('Anglican', 'Anglican 圣公会'),
      ExploreSub('Methodist', 'Methodist 卫理公会'),
      ExploreSub('Baptist', 'Baptist 浸信会'),
      ExploreSub('Pentecostal', 'Pentecostal 五旬节'),
      ExploreSub('Evangelical', 'Evangelical 福音派'),
    ]),
    ExploreSub('Oriental Orthodox', 'Oriental Orthodox Church', subs: [
      ExploreSub('Coptic', 'Coptic Orthodox'),
      ExploreSub('Armenian Apostolic', 'Armenian Apostolic Church'),
      ExploreSub('Syriac Orthodox', 'Syriac Orthodox'),
      ExploreSub('Ethiopian Orthodox', 'Ethiopian Orthodox Tewahedo'),
    ]),
    ExploreSub('Other Christian', 'Christian denominations 基督教 教派'),
  ]),
  ExploreTopic('Islam', AppIcons.mosque, '伊斯兰教 Islam', subs: [
    ExploreSub('Quran', 'Quran recitation 古兰经'),
    ExploreSub('Islamic lectures', 'Islamic lecture khutbah 伊斯兰 讲座'),
    ExploreSub('Prophet biographies', 'Prophet Muhammad seerah'),
    ExploreSub('Sunni', 'Sunni Islam'),
    ExploreSub('Shia', 'Shia Islam'),
    ExploreSub('Sufism', 'Sufism 苏菲'),
    ExploreSub('Islamic history', 'Islamic history 伊斯兰 历史'),
    ExploreSub('Islamic theology', 'Islamic theology'),
    ExploreSub('Islamic culture', 'Islamic culture 伊斯兰文化'),
  ]),
  ExploreTopic('Buddhism', AppIcons.buildings, '佛教 佛法', subs: [
    ExploreSub('Chinese Buddhism', '汉传佛教 法师 开示'),
    ExploreSub('Sutras', '佛经 讲解'),
    ExploreSub('Zen', '禅宗 Zen'),
    ExploreSub('Pure Land Buddhism', '净土宗 念佛'),
    ExploreSub('Tibetan Buddhism', '藏传佛教 Tibetan Buddhism'),
    ExploreSub('Theravada', '南传佛教 Theravada'),
    ExploreSub('Buddhist philosophy', '佛教哲学 中观 唯识 Buddhist philosophy'),
    ExploreSub('Meditation', 'Buddhist meditation mindfulness 禅修'),
    ExploreSub('Buddhist history', 'Buddhist history 佛教史'),
  ]),
  ExploreTopic('Taoism & Chinese religion', AppIcons.personSimpleTaiChi, '道教 文化', subs: [
    ExploreSub('Taoist classics', '道德经 庄子 讲解'),
    ExploreSub('Taoist culture', '道教 文化 道观'),
    ExploreSub('Taoist practice', '道教 修行 内丹 养生'),
    ExploreSub('Confucianism', '儒家 论语'),
    ExploreSub('I Ching', '易经 周易 讲解'),
    ExploreSub('Folk religion', '民间信仰 庙会 妈祖'),
    ExploreSub('Chinese classics', '国学 传统文化'),
    ExploreSub('Myths & legends', '中国神话 传说 mythology'),
  ]),
  ExploreTopic('Hinduism', AppIcons.handsPraying, 'Hinduism 印度教', subs: [
    ExploreSub('Scriptures', 'Bhagavad Gita Upanishads explained'),
    ExploreSub('Hindu philosophy', 'Hindu philosophy Vedanta'),
    ExploreSub('Deities', 'Hindu gods Shiva Vishnu'),
    ExploreSub('Master lectures', 'Hindu swami lecture'),
    ExploreSub('Rituals', 'Hindu puja ritual'),
    ExploreSub('Yoga & meditation', 'yoga philosophy meditation Hindu'),
    ExploreSub('Devotional songs', 'bhajan kirtan'),
    ExploreSub('History', 'Hindu history'),
    ExploreSub('Culture', 'Hindu culture festival'),
  ]),
  ExploreTopic('Judaism', AppIcons.synagogue, 'Judaism 犹太教', subs: [
    ExploreSub('Scriptures', 'Torah Talmud study'),
    ExploreSub('Rabbi lectures', 'rabbi lecture'),
    ExploreSub('History', 'Jewish history'),
    ExploreSub('Customs & traditions', 'Jewish traditions Shabbat'),
    ExploreSub('Holidays', 'Jewish holidays'),
    ExploreSub('Jewish philosophy', 'Jewish philosophy Maimonides'),
    ExploreSub('Kabbalah', 'Kabbalah'),
    ExploreSub('Hebrew', 'Hebrew learning'),
  ]),
  ExploreTopic('Other religions', AppIcons.globe, 'world religions', subs: [
    ExploreSub('World religions overview', 'world religions explained'),
    ExploreSub('Sikhism', 'Sikhism'),
    ExploreSub('Jainism', 'Jainism'),
    ExploreSub('Shinto', 'Shinto 神道'),
    ExploreSub('Baháʼí Faith', 'Bahai Faith'),
    ExploreSub('Zoroastrianism', 'Zoroastrianism'),
    ExploreSub('Indigenous religions', 'indigenous spirituality religion'),
    ExploreSub('Ancient religions', 'ancient religions Egypt Greece Rome'),
    ExploreSub('Neopaganism', 'neopaganism Norse paganism'),
  ]),
];

/// 宗教学术: history, philosophy and the study of religion, believing or not.
/// 精选专题 holds a few entry points; the topics they touch have their own
/// zones, so it is kept short.
const faithStudyTopics = <ExploreTopic>[
  ExploreTopic('Featured', AppIcons.starFill, 'religion documentary 宗教 纪录片', subs: [
    ExploreSub('Religion news today', 'religion news 宗教新闻'),
    ExploreSub('World religion documentaries', 'world religions documentary'),
    ExploreSub('History and archaeology', 'biblical archaeology religious history'),
    ExploreSub('Philosophy of religion in depth', 'philosophy of religion discussion'),
    ExploreSub('Religion and modern science', 'religion and science'),
    ExploreSub('Religious education channels', 'religious studies lecture course'),
  ]),
  ExploreTopic('Religious history', AppIcons.scroll, 'history of religion 宗教史', subs: [
    ExploreSub('Church history', 'church history 教会史'),
    ExploreSub('Early Christianity', 'early Christianity history'),
    ExploreSub('Reformation', 'Protestant Reformation history'),
    ExploreSub('Medieval religion', 'medieval religion crusades'),
    ExploreSub('Spread of religions', 'spread of religions history'),
    ExploreSub('Archaeology', 'biblical archaeology'),
    ExploreSub('Islamic Golden Age', 'Islamic Golden Age'),
    ExploreSub('Ancient Near East', 'ancient Near East religion'),
  ]),
  ExploreTopic('Philosophy of religion', AppIcons.brain, 'philosophy of religion 宗教哲学', subs: [
    ExploreSub('Philosophy of religion', 'philosophy of religion'),
    ExploreSub('Theology', 'theology lecture 神学'),
    ExploreSub('Metaphysics', 'metaphysics God argument'),
    ExploreSub('Faith and reason', 'faith and reason'),
    ExploreSub('The problem of evil', 'problem of evil theodicy'),
    ExploreSub('Mysticism', 'mysticism religious experience'),
    ExploreSub('Ethics', 'religious ethics'),
    ExploreSub('Apologetics', 'apologetics'),
  ]),
  ExploreTopic('Comparative religion', AppIcons.arrowsHorizontal, 'comparative religion 比较宗教', subs: [
    ExploreSub('Intro to world religions', 'introduction to world religions course'),
    ExploreSub('Similarities and differences', 'comparative religion differences'),
    ExploreSub('Scholarship', 'religious studies academic'),
    ExploreSub('Sociology of religion', 'sociology of religion'),
    ExploreSub('Psychology of religion', 'psychology of religion'),
    ExploreSub('Religious anthropology', 'anthropology of religion'),
    ExploreSub('Mythology', 'comparative mythology'),
    ExploreSub('Ritual studies', 'ritual studies religion'),
  ]),
  ExploreTopic('Scripture study', AppIcons.bookOpenText, 'scripture study 经典', subs: [
    ExploreSub('Bible', 'Bible study 圣经'),
    ExploreSub('Old Testament', 'Hebrew Bible Old Testament scholarship'),
    ExploreSub('New Testament', 'New Testament scholarship'),
    ExploreSub('Quran', 'Quran tafsir'),
    ExploreSub('Sutras', '佛经 讲解'),
    ExploreSub('Tao Te Ching', '道德经 讲解'),
    ExploreSub('Vedas and Upanishads', 'Vedas Upanishads'),
    ExploreSub('Talmud', 'Talmud study'),
    ExploreSub('Dead Sea Scrolls & apocrypha', 'Dead Sea Scrolls apocrypha'),
  ]),
  ExploreTopic('Religion and society', AppIcons.usersThree, 'religion and society', subs: [
    ExploreSub('Religious freedom', 'religious freedom'),
    ExploreSub('Religion and politics', 'religion and politics'),
    ExploreSub('Secularization', 'secularization'),
    ExploreSub('Religion & gender', 'religion and gender'),
    ExploreSub('Religion & conflict', 'religion and conflict violence'),
    ExploreSub('Religion & bioethics', 'religion bioethics'),
    ExploreSub('Religious demographics', 'religious demographics trends'),
  ]),
  ExploreTopic('Atheism and critique', AppIcons.question, 'atheism religion debate', subs: [
    ExploreSub('Atheism', 'atheism'),
    ExploreSub('Agnosticism', 'agnosticism'),
    ExploreSub('Secular humanism', 'secular humanism'),
    ExploreSub('Critique of religion', 'critique of religion'),
    ExploreSub('Former believer stories', 'ex-believer deconversion story'),
    ExploreSub('Biblical criticism', 'biblical criticism historical critical'),
  ]),
  ExploreTopic('Dialogue', AppIcons.chatsFill, 'interfaith dialogue 宗教对话', subs: [
    ExploreSub('Interfaith dialogue', 'interfaith dialogue'),
    ExploreSub('Ecumenical exchange', 'ecumenical dialogue'),
    ExploreSub('Believers and non-believers', 'believer atheist conversation'),
    ExploreSub('Theology debates', 'theology debate'),
    ExploreSub('Roundtable discussion', 'religion roundtable panel'),
    ExploreSub('Religious leader interviews', 'religious leader interview'),
  ]),
];

/// 文化艺术: art, buildings, music, festivals and faith around the world.
const faithArtsTopics = <ExploreTopic>[
  ExploreTopic('Sacred art', AppIcons.paletteFill, 'sacred art 宗教艺术', subs: [
    ExploreSub('Religious painting', 'religious painting art history'),
    ExploreSub('Icons', 'icon painting iconography'),
    ExploreSub('Religious sculpture', 'religious sculpture'),
    ExploreSub('Stained glass', 'stained glass'),
    ExploreSub('Manuscripts', 'illuminated manuscripts'),
    ExploreSub('Islamic calligraphy & geometry', 'Islamic calligraphy geometric art'),
    ExploreSub('Thangka & mandala', 'thangka mandala'),
    ExploreSub('Religious films', 'religious film'),
  ]),
  ExploreTopic('Religious architecture', AppIcons.bank, 'famous religious buildings 宗教建筑', subs: [
    ExploreSub('Famous religious buildings', 'famous religious buildings world'),
    ExploreSub('Churches', 'cathedral architecture 教堂'),
    ExploreSub('Mosques', 'mosque architecture'),
    ExploreSub('Temples', 'temple architecture 寺庙'),
    ExploreSub('Hindu temples', 'Hindu temple architecture'),
    ExploreSub('Taoist temples', '道观 Taoist temple'),
    ExploreSub('Synagogues', 'synagogue architecture'),
    ExploreSub('Monasteries', 'monastery architecture'),
  ]),
  ExploreTopic('Documentaries', AppIcons.filmSlateFill, 'religion documentary 宗教 纪录片', subs: [
    ExploreSub('World religions', 'world religions documentary'),
    ExploreSub('Monastery life', 'monastery life documentary'),
    ExploreSub('Pilgrimages', 'pilgrimage documentary'),
    ExploreSub('Holy site visits', 'holy land documentary'),
    ExploreSub('Biographies', 'religious figure biography documentary'),
    ExploreSub('Daily life of believers', 'daily life of believers documentary'),
  ]),
  ExploreTopic('Sacred music', AppIcons.musicNoteFill, 'sacred music', subs: [
    ExploreSub('Hymns', 'hymns choir'),
    ExploreSub('Worship music', 'worship music'),
    ExploreSub('Gregorian chant', 'Gregorian chant'),
    ExploreSub('Byzantine chant', 'Byzantine chant'),
    ExploreSub('Sacred choral music', 'sacred choral music'),
    ExploreSub('Pipe organ', 'church pipe organ'),
    ExploreSub('Buddhist music', '佛教音乐 梵呗'),
    ExploreSub('Sufi music', 'Sufi music qawwali'),
    ExploreSub('Islamic chants', 'nasheed'),
    ExploreSub('Indian devotional songs', 'kirtan bhajan'),
  ]),
  ExploreTopic('Festivals & customs', AppIcons.confetti, 'religious festivals', subs: [
    ExploreSub('Christmas', 'Christmas tradition 圣诞'),
    ExploreSub('Easter', 'Easter tradition 复活节'),
    ExploreSub('Holy Week', 'Holy Week processions'),
    ExploreSub('Ramadan', 'Ramadan'),
    ExploreSub('Eid al-Fitr & Eid al-Adha', 'Eid al-Fitr Eid al-Adha'),
    ExploreSub('Diwali', 'Diwali'),
    ExploreSub('Vesak', 'Vesak'),
    ExploreSub('Hanukkah', 'Hanukkah'),
    ExploreSub('Life rituals', 'religious wedding funeral rites'),
  ]),
  ExploreTopic('Faith around the world', AppIcons.globe, 'religious culture around the world', subs: [
    ExploreSub('China', 'China religious culture 中国 宗教文化'),
    ExploreSub('Japan & Korea', 'Japan Korea religious culture'),
    ExploreSub('South Asia', 'South Asia religious culture'),
    ExploreSub('Southeast Asia', 'Southeast Asia religious culture'),
    ExploreSub('Middle East', 'Middle East religious heritage'),
    ExploreSub('Europe', 'Europe religious traditions'),
    ExploreSub('Americas', 'Americas faith traditions'),
    ExploreSub('Africa', 'Africa religion culture'),
  ]),
];

/// 宗教直播: services, prayer, talks and holy places, now or coming up.
const faithLiveTopics = <ExploreTopic>[
  ExploreTopic('Liturgy', AppIcons.church, 'Holy Mass live 弥撒 直播', subs: [
    ExploreSub('Sunday service', 'Sunday church service live 主日崇拜'),
    ExploreSub('Mass', 'Holy Mass live 弥撒'),
    ExploreSub('Communion services', 'Holy Communion service live'),
    ExploreSub('Orthodox Divine Liturgy', 'Divine Liturgy live'),
    ExploreSub('Anglican evensong', 'Evensong live'),
    ExploreSub("Friday Jumu'ah prayer", "Friday prayer Jumu'ah live"),
    ExploreSub('Shabbat', 'Shabbat service live'),
    ExploreSub('Buddhist ceremonies', '法会 直播'),
    ExploreSub('Hindu rituals', 'Hindu puja aarti live'),
  ]),
  ExploreTopic('Prayer & meditation', AppIcons.personSimpleTaiChi, 'prayer live 祈祷', subs: [
    ExploreSub('Prayer', 'prayer live 祈祷 直播'),
    ExploreSub('Rosary', 'rosary live 玫瑰经'),
    ExploreSub('Liturgy of the Hours', 'Liturgy of the Hours live'),
    ExploreSub('Eucharistic adoration', 'Eucharistic adoration live'),
    ExploreSub('Taizé prayer', 'Taize prayer live'),
    ExploreSub('Meditation', 'meditation live 禅修'),
    ExploreSub('Chanting', '诵经 直播'),
    ExploreSub('Quran recitation', 'Quran recitation live'),
  ]),
  ExploreTopic('Sermons', AppIcons.userSoundFill, 'sermon live', subs: [
    ExploreSub("Pastors' sermons", 'church sermon live'),
    ExploreSub('Homilies', 'Catholic homily live'),
    ExploreSub('Dharma talks', '法师 开示 直播'),
    ExploreSub('Imam lectures', 'imam khutbah live'),
    ExploreSub('Rabbi teachings', 'rabbi Torah class live'),
    ExploreSub('Religious lectures', 'religious lecture live'),
    ExploreSub('Spiritual reflections', 'devotional live'),
  ]),
  ExploreTopic('Sacred music', AppIcons.musicNoteFill, 'sacred music live', subs: [
    ExploreSub('Worship & praise', 'worship praise live'),
    ExploreSub('Choirs', 'church choir live'),
    ExploreSub('Chant', 'chant live'),
    ExploreSub('Organ performance', 'organ recital live'),
    ExploreSub('Sacred concerts', 'sacred music concert live'),
    ExploreSub('Sufism & devotional songs', 'qawwali nasheed live'),
  ]),
  ExploreTopic('Religious education', AppIcons.graduationCap, 'theology class live', subs: [
    ExploreSub('Scripture reading', 'Bible study live'),
    ExploreSub('Theology courses', 'theology course live'),
    ExploreSub('Catechism', 'catechism class live'),
    ExploreSub('Buddhist courses', 'Buddhist teaching class live 佛学'),
    ExploreSub('Quran classes', 'Quran class live'),
    ExploreSub('Talmud classes', 'Talmud class live'),
    ExploreSub('Online teaching', 'religious education live'),
  ]),
  ExploreTopic('Religion news', AppIcons.newspaper, 'Vatican live', subs: [
    ExploreSub('Religion news', 'religion news live'),
    ExploreSub('Papacy & Vatican', 'Pope Vatican live'),
    ExploreSub('Synods and councils', 'synod live'),
    ExploreSub('Major religious events', 'religious event live'),
    ExploreSub('Religious leader interviews', 'religious leader interview live'),
  ]),
  ExploreTopic('Religious festivals', AppIcons.confetti, 'religious festival live', subs: [
    ExploreSub('Christmas', 'Christmas Mass live'),
    ExploreSub('Easter', 'Easter Vigil live'),
    ExploreSub('Holy Week processions', 'Holy Week procession live'),
    ExploreSub('Ramadan', 'Ramadan live'),
    ExploreSub('Eid al-Fitr', 'Eid prayer live'),
    ExploreSub('Vesak', 'Vesak live'),
    ExploreSub('Diwali', 'Diwali live'),
  ]),
  ExploreTopic('Dialogue', AppIcons.chatsFill, 'interfaith dialogue live', subs: [
    ExploreSub('Theology debates', 'theology debate live'),
    ExploreSub('Interfaith discussion', 'interfaith discussion live'),
    ExploreSub('Roundtable discussion', 'religion panel roundtable live'),
    ExploreSub('Public Q&A', 'religious Q&A live'),
    ExploreSub('Faith interviews', 'faith interview live'),
  ]),
  ExploreTopic('Holy places live', AppIcons.videoCamera, 'shrine live cam', subs: [
    ExploreSub('Mecca', 'Makkah live'),
    ExploreSub('Medina', 'Madinah live'),
    ExploreSub("St Peter's Square", "St Peter's Square live"),
    ExploreSub('Jerusalem', 'Jerusalem live'),
    ExploreSub('Western Wall', 'Western Wall live'),
    ExploreSub('Lourdes', 'Lourdes live'),
    ExploreSub('Fátima', 'Fatima live'),
    ExploreSub('Ganges', 'Ganga Aarti Varanasi live'),
    ExploreSub('Buddhist temples', 'Buddhist temple live cam'),
    ExploreSub('Churches', 'church live cam'),
  ]),
  ExploreTopic('Religious radio', AppIcons.radio, 'Catholic radio 24/7 live', subs: [
    ExploreSub('Sermon radio', 'sermon radio 24/7'),
    ExploreSub('Sacred music radio', 'sacred music radio 24/7'),
    ExploreSub('Prayer radio', 'prayer radio live'),
    ExploreSub('Catholic radio', 'Catholic radio 24/7'),
    ExploreSub('Quran radio', 'Quran radio 24/7'),
    ExploreSub('Buddhist chanting radio', '佛教 念佛 24小时 chanting 24/7'),
  ]),
];

/// 宗教与信仰's 类型 filter: words added to the zone's search.
enum FaithFormat implements WordFilter {
  any('Any', ''),
  lecture('Lecture', 'lecture 讲座'),
  documentary('Documentary', 'documentary 纪录片'),
  liturgy('Liturgy', 'liturgy 礼仪'),
  interview('Interview', 'interview 访谈'),
  debate('Debate', 'debate 辩论'),
  music('Music', 'music 音乐'),
  news('News', 'news 新闻');

  const FaithFormat(this._label, this.words);
  final String _label;
  @override
  String get label => tr(_label);
  @override
  final String words;
}

/// 宗教与信仰's 视角 filter: from inside a faith, from the study of it, from
/// its critics or between faiths. Like [FaithFormat], words added to the
/// search, so it leans the results rather than sorting them exactly.
enum FaithView implements WordFilter {
  any('Any', ''),
  inside('From within a faith', 'sermon testimony 信仰分享'),
  academic('Neutral scholarship', 'academic lecture university'),
  critical('Critical discussion', 'critique criticism'),
  dialogue('Interfaith dialogue', 'interfaith dialogue');

  const FaithView(this._label, this.words);
  final String _label;
  @override
  String get label => tr(_label);
  @override
  final String words;
}

/// Whether [title] reads like bait: three or more exclamation marks, a
/// title mostly in capitals, or words such as "destroys" and 吊打. Such
/// videos are left out of 宗教与信仰, where they tend to crowd out the rest.
bool looksLikeBait(String title) {
  final core = NativeCore.instance;
  return core != null && core.withText(title, core.looksLikeBait);
}

/// At most this many videos of one channel in a 宗教与信仰 listing, so that
/// several voices show.
const faithPerChannel = 3;

/// A test for one 宗教与信仰 listing's videos, asked once for each video that
/// would show: no bait, and no more than [faithPerChannel] of a channel.
bool Function(VideoItem item) faithFilter() {
  final perChannel = <String, int>{};
  return (item) {
    if (looksLikeBait(item.title)) return false;
    final channel = item.channelId ?? item.channel;
    if (channel.isEmpty) return true;
    final count = perChannel[channel] ?? 0;
    if (count >= faithPerChannel) return false;
    perChannel[channel] = count + 1;
    return true;
  };
}
