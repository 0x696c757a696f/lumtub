import 'explore_filters.dart';
import 'explore_topics.dart';
import 'faith_traditions.dart';
import 'l10n/l10n.dart';
import 'models.dart';
import 'native_core.dart';
import 'ui/app_icons.dart';

// The zones of 宗教与信仰, one list per tab. Each is a YouTube search, so a
// channel can turn up under every tradition or theme it speaks to; nothing
// here decides what a channel "is".

/// 宗教传统: the traditions, with Christianity's split a level further. Each
/// tradition has about 8-10 sub-categories; Christianity's are its branches.
final faithTraditionTopics = <ExploreTopic>[
  ExploreTopic('Christianity', AppIcons.church, '基督宗教 Christianity',
      tradition: FaithTradition.christianity,
      subs: [
        const ExploreSub('Catholic', '天主教 Catholic', tradition: FaithTradition.catholic, subs: [
          ExploreSub("The Pope's words", '教宗 讲话 Pope homily'),
          ExploreSub('Vatican news', 'Vatican News 梵蒂冈'),
          ExploreSub('Bible study', 'Catholic Bible study 天主教 圣经'),
          ExploreSub('Catholic theology', 'Catholic theology 天主教 神学'),
          ExploreSub('Church history', 'Catholic Church history 天主教 教会历史'),
          ExploreSub('Mass', 'Holy Mass 天主教 弥撒'),
          ExploreSub('Sacraments', 'Catholic sacraments 天主教 圣事'),
          ExploreSub('Prayer', 'Catholic prayer 天主教 祈祷 玫瑰经'),
          ExploreSub('Lives of the saints', 'Catholic saints 天主教 圣人'),
          ExploreSub('Religious life', 'Catholic religious life monastery 天主教 修会'),
          ExploreSub('Church music', 'Gregorian chant Catholic hymns 天主教 圣歌'),
          ExploreSub('Eastern Catholic', 'Eastern Catholic Byzantine Catholic 东方礼天主教',
              tradition: FaithTradition.easternCatholic),
        ]),
        const ExploreSub('Eastern Orthodox', 'Orthodox Christianity 东正教',
            tradition: FaithTradition.orthodox,
            subs: [
              ExploreSub('Orthodox theology', 'Orthodox theology 东正教 神学'),
              ExploreSub('Byzantine liturgy', 'Orthodox Divine Liturgy 东正教 事奉圣礼'),
              ExploreSub('Icon art', 'Orthodox icons iconography 东正教 圣像'),
              ExploreSub('Church Fathers', 'Orthodox Church Fathers patristics'),
              ExploreSub('Monastic tradition', 'Orthodox monasticism Mount Athos 阿索斯山'),
              ExploreSub('Chant', 'Orthodox Byzantine chant'),
            ]),
        const ExploreSub('Protestant', 'Protestant 新教 基督教 讲道',
            tradition: FaithTradition.protestant,
            subs: [
              ExploreSub('Lutheran', 'Lutheran 路德宗 信义会', tradition: FaithTradition.lutheran),
              ExploreSub('Reformed', 'Reformed theology 改革宗 长老会',
                  tradition: FaithTradition.reformed),
              ExploreSub('Anglican', 'Anglican 圣公会', tradition: FaithTradition.anglican),
              ExploreSub('Methodist', 'Methodist 卫理公会', tradition: FaithTradition.methodist),
              ExploreSub('Baptist', 'Baptist 浸信会', tradition: FaithTradition.baptist),
              ExploreSub('Pentecostal', 'Pentecostal 五旬节 灵恩',
                  tradition: FaithTradition.pentecostal),
              ExploreSub('Evangelical', 'Evangelical 福音派', tradition: FaithTradition.evangelical),
            ]),
        const ExploreSub('Oriental Orthodox', 'Oriental Orthodox Church 东方正统教会',
            tradition: FaithTradition.orientalOrthodox,
            subs: [
              ExploreSub('Coptic', 'Coptic Orthodox 科普特'),
              ExploreSub('Armenian Apostolic', 'Armenian Apostolic Church'),
              ExploreSub('Syriac Orthodox', 'Syriac Orthodox'),
              ExploreSub('Ethiopian Orthodox', 'Ethiopian Orthodox Tewahedo'),
            ]),
        const ExploreSub('Other Christian', 'Christian denominations 基督教 教派'),
      ]),
  ExploreTopic('Islam', AppIcons.mosque, '伊斯兰教 Islam', tradition: FaithTradition.islam, subs: [
    const ExploreSub('Quran', 'Quran recitation 古兰经'),
    const ExploreSub('Islamic lectures', 'Islamic lecture khutbah 伊斯兰 讲座'),
    const ExploreSub('Prophet biographies', 'Prophet Muhammad seerah'),
    const ExploreSub('Sunni', 'Sunni Islam', tradition: FaithTradition.sunni),
    const ExploreSub('Shia', 'Shia Islam', tradition: FaithTradition.shia),
    const ExploreSub('Sufism', 'Sufism 苏菲'),
    const ExploreSub('Islamic history', 'Islamic history 伊斯兰 历史'),
    const ExploreSub('Islamic theology', 'Islamic theology'),
    const ExploreSub('Islamic culture', 'Islamic culture 伊斯兰文化'),
  ]),
  ExploreTopic('Buddhism', AppIcons.buildings, '佛教 佛法', tradition: FaithTradition.buddhism, subs: [
    const ExploreSub('Chinese Buddhism', '汉传佛教 法师 开示', tradition: FaithTradition.chineseBuddhism),
    const ExploreSub('Sutras', '佛经 讲解'),
    const ExploreSub('Zen', '禅宗 Zen', tradition: FaithTradition.zen),
    const ExploreSub('Pure Land Buddhism', '净土宗 念佛', tradition: FaithTradition.pureLand),
    const ExploreSub('Tibetan Buddhism', '藏传佛教 Tibetan Buddhism',
        tradition: FaithTradition.tibetanBuddhism),
    const ExploreSub('Theravada', '南传佛教 Theravada', tradition: FaithTradition.theravada),
    const ExploreSub('Buddhist philosophy', '佛教哲学 中观 唯识 Buddhist philosophy'),
    const ExploreSub('Meditation', 'Buddhist meditation mindfulness 禅修'),
    const ExploreSub('Buddhist history', 'Buddhist history 佛教史'),
  ]),
  ExploreTopic('Taoism & Chinese religion', AppIcons.personSimpleTaiChi, '道教 文化',
      tradition: FaithTradition.chineseReligion,
      subs: [
        const ExploreSub('Taoist classics', '道德经 庄子 讲解', tradition: FaithTradition.taoism),
        const ExploreSub('Taoist culture', '道教 文化 道观', tradition: FaithTradition.taoism),
        const ExploreSub('Taoist practice', '道教 修行 内丹 养生', tradition: FaithTradition.taoism),
        const ExploreSub('Confucianism', '儒家 论语', tradition: FaithTradition.confucianism),
        const ExploreSub('I Ching', '易经 周易 讲解'),
        const ExploreSub('Folk religion', '民间信仰 庙会 妈祖', tradition: FaithTradition.folkReligion),
        const ExploreSub('Chinese classics', '国学 传统文化'),
        const ExploreSub('Myths & legends', '中国神话 传说 mythology'),
      ]),
  ExploreTopic('Hinduism', AppIcons.handsPraying, 'Hinduism 印度教',
      tradition: FaithTradition.hinduism,
      subs: [
        const ExploreSub('Scriptures', 'Bhagavad Gita Upanishads explained'),
        const ExploreSub('Hindu philosophy', 'Hindu philosophy Vedanta'),
        const ExploreSub('Deities', 'Hindu gods Shiva Vishnu'),
        const ExploreSub('Master lectures', 'Hindu swami lecture'),
        const ExploreSub('Rituals', 'Hindu puja ritual'),
        const ExploreSub('Yoga & meditation', 'yoga philosophy meditation Hindu'),
        const ExploreSub('Devotional songs', 'bhajan kirtan Hindu'),
        const ExploreSub('History', 'Hindu history'),
        const ExploreSub('Culture', 'Hindu culture festival'),
      ]),
  ExploreTopic('Judaism', AppIcons.synagogue, 'Judaism 犹太教',
      tradition: FaithTradition.judaism,
      subs: [
        const ExploreSub('Scriptures', 'Torah Talmud study'),
        const ExploreSub('Rabbi lectures', 'rabbi lecture'),
        const ExploreSub('History', 'Jewish history'),
        const ExploreSub('Customs & traditions', 'Jewish traditions Shabbat'),
        const ExploreSub('Holidays', 'Jewish holidays'),
        const ExploreSub('Jewish philosophy', 'Jewish philosophy Maimonides'),
        const ExploreSub('Kabbalah', 'Jewish Kabbalah'),
        const ExploreSub('Hebrew', 'Hebrew learning'),
      ]),
  ExploreTopic('Other religions', AppIcons.globe, 'world religions', subs: [
    const ExploreSub('World religions overview', 'world religions explained'),
    const ExploreSub('Sikhism', 'Sikhism', tradition: FaithTradition.sikhism),
    const ExploreSub('Jainism', 'Jainism', tradition: FaithTradition.jainism),
    const ExploreSub('Shinto', 'Shinto 神道', tradition: FaithTradition.shinto),
    const ExploreSub('Baháʼí Faith', 'Bahai Faith', tradition: FaithTradition.bahai),
    const ExploreSub('Zoroastrianism', 'Zoroastrianism', tradition: FaithTradition.zoroastrianism),
    const ExploreSub('Indigenous religions', 'indigenous spirituality religion'),
    const ExploreSub('Ancient religions', 'ancient religions Egypt Greece Rome'),
    const ExploreSub('Neopaganism', 'neopaganism Norse paganism'),
  ]),
];

/// 宗教学术: history, philosophy and the study of religion, believing or not.
/// 精选专题 holds a few entry points; the topics they touch have their own
/// zones, so it is kept short.
final faithStudyTopics = <ExploreTopic>[
  const ExploreTopic('Featured', AppIcons.starFill, 'religion documentary 宗教 纪录片', subs: [
    ExploreSub('Religion news today', 'religion news 宗教新闻'),
    ExploreSub('World religion documentaries', 'world religions documentary'),
    ExploreSub('History and archaeology', 'biblical archaeology religious history'),
    ExploreSub('Philosophy of religion in depth', 'philosophy of religion discussion'),
    ExploreSub('Religion and modern science', 'religion and science'),
    ExploreSub('Religious education channels', 'religious studies lecture course'),
  ]),
  ExploreTopic('Religious history', AppIcons.scroll, 'history of religion 宗教史', subs: [
    const ExploreSub('Church history', 'church history 教会史'),
    const ExploreSub('Early Christianity', 'early Christianity history'),
    const ExploreSub('Reformation', 'Protestant Reformation history'),
    const ExploreSub('Medieval religion', 'medieval religion crusades'),
    const ExploreSub('Spread of religions', 'spread of religions history'),
    const ExploreSub('Archaeology', 'biblical archaeology'),
    const ExploreSub('Islamic Golden Age', 'Islamic Golden Age'),
    const ExploreSub('Ancient Near East', 'ancient Near East religion'),
  ]),
  ExploreTopic('Philosophy of religion', AppIcons.brain, 'philosophy of religion 宗教哲学', subs: [
    const ExploreSub('Philosophy of religion', 'philosophy of religion'),
    const ExploreSub('Theology', 'theology lecture 神学'),
    const ExploreSub('Metaphysics', 'metaphysics God argument'),
    const ExploreSub('Faith and reason', 'faith and reason'),
    const ExploreSub('The problem of evil', 'problem of evil theodicy'),
    const ExploreSub('Mysticism', 'mysticism religious experience'),
    const ExploreSub('Ethics', 'religious ethics'),
    const ExploreSub('Apologetics', 'apologetics'),
  ]),
  ExploreTopic('Comparative religion', AppIcons.arrowsHorizontal, 'comparative religion 比较宗教',
      subs: [
        const ExploreSub('Intro to world religions', 'introduction to world religions course'),
        const ExploreSub('Similarities and differences', 'comparative religion differences'),
        const ExploreSub('Scholarship', 'religious studies academic'),
        const ExploreSub('Sociology of religion', 'sociology of religion'),
        const ExploreSub('Psychology of religion', 'psychology of religion'),
        const ExploreSub('Religious anthropology', 'anthropology of religion'),
        const ExploreSub('Mythology', 'comparative mythology'),
        const ExploreSub('Ritual studies', 'ritual studies religion'),
      ]),
  ExploreTopic('Scripture study', AppIcons.bookOpenText, 'scripture study 经典', subs: [
    const ExploreSub('Bible', 'Bible study 圣经'),
    const ExploreSub('Old Testament', 'Hebrew Bible Old Testament scholarship'),
    const ExploreSub('New Testament', 'New Testament scholarship'),
    const ExploreSub('Quran', 'Quran tafsir'),
    const ExploreSub('Sutras', '佛经 讲解'),
    const ExploreSub('Tao Te Ching', '道德经 讲解'),
    const ExploreSub('Vedas and Upanishads', 'Vedas Upanishads'),
    const ExploreSub('Talmud', 'Talmud study'),
    const ExploreSub('Dead Sea Scrolls & apocrypha', 'Dead Sea Scrolls apocrypha'),
  ]),
  ExploreTopic('Religion and society', AppIcons.usersThree, 'religion and society', subs: [
    const ExploreSub('Religious freedom', 'religious freedom'),
    const ExploreSub('Religion and politics', 'religion and politics'),
    const ExploreSub('Secularization', 'secularization'),
    const ExploreSub('Religion & gender', 'religion and gender'),
    const ExploreSub('Religion & conflict', 'religion and conflict violence'),
    const ExploreSub('Religion & bioethics', 'religion bioethics'),
    const ExploreSub('Religious demographics', 'religious demographics trends'),
  ]),
  ExploreTopic('Atheism and critique', AppIcons.question, 'atheism religion debate', subs: [
    const ExploreSub('Atheism', 'atheism'),
    const ExploreSub('Agnosticism', 'agnosticism'),
    const ExploreSub('Secular humanism', 'secular humanism'),
    const ExploreSub('Critique of religion', 'critique of religion'),
    const ExploreSub('Former believer stories', 'ex-believer deconversion story'),
    const ExploreSub('Biblical criticism', 'biblical criticism historical critical'),
  ]),
  const ExploreTopic('Dialogue', AppIcons.chatsFill, 'interfaith dialogue 宗教对话', subs: [
    ExploreSub('Interfaith dialogue', 'interfaith dialogue'),
    ExploreSub('Ecumenical exchange', 'ecumenical dialogue'),
    ExploreSub('Believers and non-believers', 'believer atheist conversation'),
    ExploreSub('Theology debates', 'theology debate'),
    ExploreSub('Roundtable discussion', 'religion roundtable panel'),
    ExploreSub('Religious leader interviews', 'religious leader interview'),
  ]),
];

/// 文化艺术: art, buildings, music, festivals and faith around the world.
final faithArtsTopics = <ExploreTopic>[
  const ExploreTopic('Sacred art', AppIcons.paletteFill, 'sacred art 宗教艺术', subs: [
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
    const ExploreSub('Famous religious buildings', 'famous religious buildings world'),
    const ExploreSub('Churches', 'cathedral architecture 教堂'),
    const ExploreSub('Mosques', 'mosque architecture'),
    const ExploreSub('Temples', 'temple architecture 寺庙'),
    const ExploreSub('Hindu temples', 'Hindu temple architecture'),
    const ExploreSub('Taoist temples', '道观 Taoist temple'),
    const ExploreSub('Synagogues', 'synagogue architecture'),
    const ExploreSub('Monasteries', 'monastery architecture'),
  ]),
  const ExploreTopic('Documentaries', AppIcons.filmSlateFill, 'religion documentary 宗教 纪录片', subs: [
    ExploreSub('World religions', 'world religions documentary'),
    ExploreSub('Monastery life', 'monastery life documentary'),
    ExploreSub('Pilgrimages', 'pilgrimage documentary'),
    ExploreSub('Holy site visits', 'holy land documentary'),
    ExploreSub('Biographies', 'religious figure biography documentary'),
    ExploreSub('Daily life of believers', 'daily life of believers documentary'),
  ]),
  const ExploreTopic('Sacred music', AppIcons.musicNoteFill, 'sacred music', subs: [
    ExploreSub('Hymns', 'hymns choir'),
    ExploreSub('Worship music', 'worship music'),
    ExploreSub('Gregorian chant', 'Gregorian chant', tradition: FaithTradition.catholic),
    ExploreSub('Byzantine chant', 'Byzantine chant'),
    ExploreSub('Sacred choral music', 'sacred choral music'),
    ExploreSub('Pipe organ', 'church pipe organ'),
    ExploreSub('Buddhist music', '佛教音乐 梵呗'),
    ExploreSub('Sufi music', 'Sufi music qawwali'),
    ExploreSub('Islamic chants', 'nasheed'),
    ExploreSub('Indian devotional songs', 'kirtan bhajan'),
  ]),
  ExploreTopic('Festivals & customs', AppIcons.confetti, 'religious festivals', subs: [
    const ExploreSub('Christmas', 'Christmas tradition 圣诞'),
    const ExploreSub('Easter', 'Easter tradition 复活节'),
    const ExploreSub('Holy Week', 'Holy Week processions'),
    const ExploreSub('Ramadan', 'Ramadan'),
    const ExploreSub('Eid al-Fitr & Eid al-Adha', 'Eid al-Fitr Eid al-Adha'),
    const ExploreSub('Diwali', 'Diwali'),
    const ExploreSub('Vesak', 'Vesak'),
    const ExploreSub('Hanukkah', 'Hanukkah'),
    const ExploreSub('Life rituals', 'religious wedding funeral rites'),
  ]),
  ExploreTopic('Faith around the world', AppIcons.globe, 'religious culture around the world',
      subs: [
        const ExploreSub('China', 'China religious culture 中国 宗教文化'),
        const ExploreSub('Japan & Korea', 'Japan Korea religious culture'),
        const ExploreSub('South Asia', 'South Asia religious culture'),
        const ExploreSub('Southeast Asia', 'Southeast Asia religious culture'),
        const ExploreSub('Middle East', 'Middle East religious heritage'),
        const ExploreSub('Europe', 'Europe religious traditions'),
        const ExploreSub('Americas', 'Americas faith traditions'),
        const ExploreSub('Africa', 'Africa religion culture'),
      ]),
];

/// 宗教直播: services, prayer, talks and holy places, now or coming up.
final faithLiveTopics = <ExploreTopic>[
  ExploreTopic('Liturgy', AppIcons.church, 'Holy Mass live 弥撒 直播', subs: [
    const ExploreSub('Sunday service', 'Sunday church service live 主日崇拜',
        tradition: FaithTradition.protestant),
    const ExploreSub('Mass', 'Holy Mass live 弥撒', tradition: FaithTradition.catholic),
    const ExploreSub('Communion services', 'Holy Communion service live'),
    const ExploreSub('Orthodox Divine Liturgy', 'Orthodox Divine Liturgy live',
        tradition: FaithTradition.orthodox),
    const ExploreSub('Anglican evensong', 'Evensong live', tradition: FaithTradition.anglican),
    const ExploreSub("Friday Jumu'ah prayer", "Friday prayer Jumu'ah live",
        tradition: FaithTradition.islam),
    const ExploreSub('Shabbat', 'Shabbat service live', tradition: FaithTradition.judaism),
    const ExploreSub('Buddhist ceremonies', '佛教 法会 直播', tradition: FaithTradition.buddhism),
    const ExploreSub('Hindu rituals', 'Hindu puja aarti live', tradition: FaithTradition.hinduism),
  ]),
  ExploreTopic('Prayer & meditation', AppIcons.personSimpleTaiChi, 'prayer live 祈祷', subs: [
    const ExploreSub('Prayer', 'prayer live 祈祷 直播'),
    const ExploreSub('Rosary', 'rosary live 玫瑰经', tradition: FaithTradition.catholic),
    const ExploreSub('Liturgy of the Hours', 'Liturgy of the Hours live',
        tradition: FaithTradition.catholic),
    const ExploreSub('Eucharistic adoration', 'Eucharistic adoration live',
        tradition: FaithTradition.catholic),
    const ExploreSub('Taizé prayer', 'Taize prayer live'),
    const ExploreSub('Meditation', 'meditation live 禅修'),
    const ExploreSub('Chanting', '佛教 诵经 直播', tradition: FaithTradition.buddhism),
    const ExploreSub('Quran recitation', 'Quran recitation live', tradition: FaithTradition.islam),
  ]),
  const ExploreTopic('Sermons', AppIcons.userSoundFill, 'sermon live', subs: [
    ExploreSub("Pastors' sermons", 'church sermon live 讲道', tradition: FaithTradition.protestant),
    ExploreSub('Homilies', 'Catholic homily live', tradition: FaithTradition.catholic),
    ExploreSub('Dharma talks', '法师 开示 直播', tradition: FaithTradition.buddhism),
    ExploreSub('Imam lectures', 'imam khutbah live', tradition: FaithTradition.islam),
    ExploreSub('Rabbi teachings', 'rabbi Torah class live', tradition: FaithTradition.judaism),
    ExploreSub('Religious lectures', 'religious lecture live'),
    ExploreSub('Spiritual reflections', 'devotional live'),
  ]),
  const ExploreTopic('Sacred music', AppIcons.musicNoteFill, 'sacred music live', subs: [
    ExploreSub('Worship & praise', 'worship praise live'),
    ExploreSub('Choirs', 'church choir live'),
    ExploreSub('Chant', 'chant live'),
    ExploreSub('Organ performance', 'organ recital live'),
    ExploreSub('Sacred concerts', 'sacred music concert live'),
    ExploreSub('Sufism & devotional songs', 'qawwali nasheed live'),
  ]),
  ExploreTopic('Religious education', AppIcons.graduationCap, 'theology class live', subs: [
    const ExploreSub('Scripture reading', 'Bible study live'),
    const ExploreSub('Theology courses', 'theology course live'),
    const ExploreSub('Catechism', 'catechism class live'),
    const ExploreSub('Buddhist courses', 'Buddhist teaching class live 佛学',
        tradition: FaithTradition.buddhism),
    const ExploreSub('Quran classes', 'Quran class live', tradition: FaithTradition.islam),
    const ExploreSub('Talmud classes', 'Talmud class live', tradition: FaithTradition.judaism),
    const ExploreSub('Online teaching', 'religious education live'),
  ]),
  ExploreTopic('Religion news', AppIcons.newspaper, 'Vatican live', subs: [
    const ExploreSub('Religion news', 'religion news live'),
    const ExploreSub('Papacy & Vatican', 'Pope Vatican live', tradition: FaithTradition.catholic),
    const ExploreSub('Synods and councils', 'synod live'),
    const ExploreSub('Major religious events', 'religious event live'),
    const ExploreSub('Religious leader interviews', 'religious leader interview live'),
  ]),
  ExploreTopic('Religious festivals', AppIcons.confetti, 'religious festival live', subs: [
    const ExploreSub('Christmas', 'Christmas Mass live'),
    const ExploreSub('Easter', 'Easter Vigil live'),
    const ExploreSub('Holy Week processions', 'Holy Week procession live'),
    const ExploreSub('Ramadan', 'Ramadan live'),
    const ExploreSub('Eid al-Fitr', 'Eid prayer live'),
    const ExploreSub('Vesak', 'Vesak live'),
    const ExploreSub('Diwali', 'Diwali live'),
  ]),
  const ExploreTopic('Dialogue', AppIcons.chatsFill, 'interfaith dialogue live', subs: [
    ExploreSub('Theology debates', 'theology debate live'),
    ExploreSub('Interfaith discussion', 'interfaith discussion live'),
    ExploreSub('Roundtable discussion', 'religion panel roundtable live'),
    ExploreSub('Public Q&A', 'religious Q&A live'),
    ExploreSub('Faith interviews', 'faith interview live'),
  ]),
  ExploreTopic('Holy places live', AppIcons.videoCamera, 'shrine live cam', subs: [
    const ExploreSub('Mecca', 'Makkah live'),
    const ExploreSub('Medina', 'Madinah live'),
    const ExploreSub("St Peter's Square", "St Peter's Square live"),
    const ExploreSub('Jerusalem', 'Jerusalem live'),
    const ExploreSub('Western Wall', 'Western Wall live'),
    const ExploreSub('Lourdes', 'Lourdes live'),
    const ExploreSub('Fátima', 'Fatima live'),
    const ExploreSub('Ganges', 'Ganga Aarti Varanasi live'),
    const ExploreSub('Buddhist temples', 'Buddhist temple live cam'),
    const ExploreSub('Churches', 'church live cam'),
  ]),
  ExploreTopic('Religious radio', AppIcons.radio, 'Catholic radio 24/7 live', subs: [
    const ExploreSub('Sermon radio', 'sermon radio 24/7'),
    const ExploreSub('Sacred music radio', 'sacred music radio 24/7'),
    const ExploreSub('Prayer radio', 'prayer radio live'),
    const ExploreSub('Catholic radio', 'Catholic radio 24/7', tradition: FaithTradition.catholic),
    const ExploreSub('Quran radio', 'Quran radio 24/7', tradition: FaithTradition.islam),
    const ExploreSub('Buddhist chanting radio', '佛教 念佛 24小时 chanting 24/7',
        tradition: FaithTradition.buddhism),
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
