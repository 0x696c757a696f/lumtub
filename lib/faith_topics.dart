import 'package:flutter/material.dart' show Icons;

import 'explore_filters.dart';
import 'explore_topics.dart';
import 'l10n/l10n.dart';
import 'models.dart';

// The zones of 宗教与信仰, one list per tab. Each is a YouTube search, so a
// channel can turn up under every tradition or theme it speaks to; nothing
// here decides what a channel "is".

/// 宗教传统: the traditions, with Christianity's split a level further. Each
/// tradition has about 8-10 sub-categories; Christianity's are its branches.
const faithTraditionTopics = <ExploreTopic>[
  ExploreTopic('基督宗教', Icons.church_rounded, '基督宗教 Christianity', subs: [
    ExploreSub('天主教', '天主教 Catholic', subs: [
      ExploreSub('教宗讲话', '教宗 讲话 Pope homily'),
      ExploreSub('梵蒂冈新闻', 'Vatican News 梵蒂冈'),
      ExploreSub('圣经研究', 'Catholic Bible study 天主教 圣经'),
      ExploreSub('天主教神学', 'Catholic theology 天主教 神学'),
      ExploreSub('教会历史', 'Catholic Church history 教会历史'),
      ExploreSub('弥撒', 'Holy Mass 弥撒'),
      ExploreSub('圣事', 'Catholic sacraments 圣事'),
      ExploreSub('祈祷', 'Catholic prayer 天主教 祈祷'),
      ExploreSub('圣人传记', 'Catholic saints 圣人'),
      ExploreSub('修会生活', 'Catholic religious life monastery 修会'),
      ExploreSub('教会音乐', 'Gregorian chant Catholic hymns 圣歌'),
    ]),
    ExploreSub('东正教', 'Orthodox Christianity 东正教', subs: [
      ExploreSub('东正教神学', 'Orthodox theology'),
      ExploreSub('拜占庭礼仪', 'Byzantine Divine Liturgy'),
      ExploreSub('圣像艺术', 'Orthodox icons iconography'),
      ExploreSub('教父文献', 'Church Fathers patristics'),
      ExploreSub('修道传统', 'Orthodox monasticism Mount Athos'),
      ExploreSub('圣咏', 'Byzantine chant'),
    ]),
    ExploreSub('新教', 'Protestant 新教', subs: [
      ExploreSub('路德宗', 'Lutheran 路德宗'),
      ExploreSub('改革宗', 'Reformed theology 改革宗'),
      ExploreSub('圣公会', 'Anglican 圣公会'),
      ExploreSub('卫理宗', 'Methodist 卫理公会'),
      ExploreSub('浸信会', 'Baptist 浸信会'),
      ExploreSub('五旬节派', 'Pentecostal 五旬节'),
      ExploreSub('福音派', 'Evangelical 福音派'),
    ]),
    ExploreSub('东方正统教会', 'Oriental Orthodox Church', subs: [
      ExploreSub('科普特教会', 'Coptic Orthodox'),
      ExploreSub('亚美尼亚使徒教会', 'Armenian Apostolic Church'),
      ExploreSub('叙利亚正统教会', 'Syriac Orthodox'),
      ExploreSub('埃塞俄比亚正统教会', 'Ethiopian Orthodox Tewahedo'),
    ]),
    ExploreSub('其他基督宗教', 'Christian denominations 基督教 教派'),
  ]),
  ExploreTopic('伊斯兰教', Icons.mosque_rounded, '伊斯兰教 Islam', subs: [
    ExploreSub('古兰经', 'Quran recitation 古兰经'),
    ExploreSub('伊斯兰讲座', 'Islamic lecture khutbah 伊斯兰 讲座'),
    ExploreSub('先知传记', 'Prophet Muhammad seerah'),
    ExploreSub('逊尼派', 'Sunni Islam'),
    ExploreSub('什叶派', 'Shia Islam'),
    ExploreSub('苏菲派', 'Sufism 苏菲'),
    ExploreSub('伊斯兰历史', 'Islamic history 伊斯兰 历史'),
    ExploreSub('伊斯兰神学', 'Islamic theology'),
    ExploreSub('伊斯兰文化', 'Islamic culture 伊斯兰文化'),
  ]),
  ExploreTopic('佛教', Icons.temple_buddhist_rounded, '佛教 佛法', subs: [
    ExploreSub('汉传佛教', '汉传佛教 法师 开示'),
    ExploreSub('佛经', '佛经 讲解'),
    ExploreSub('禅宗', '禅宗 Zen'),
    ExploreSub('净土宗', '净土宗 念佛'),
    ExploreSub('藏传佛教', '藏传佛教 Tibetan Buddhism'),
    ExploreSub('南传佛教', '南传佛教 Theravada'),
    ExploreSub('佛教哲学', '佛教哲学 中观 唯识 Buddhist philosophy'),
    ExploreSub('禅修', 'Buddhist meditation mindfulness 禅修'),
    ExploreSub('佛教历史', 'Buddhist history 佛教史'),
  ]),
  ExploreTopic('道教与中国传统信仰', Icons.self_improvement_rounded, '道教 文化', subs: [
    ExploreSub('道教经典', '道德经 庄子 讲解'),
    ExploreSub('道教文化', '道教 文化 道观'),
    ExploreSub('道教修行', '道教 修行 内丹 养生'),
    ExploreSub('儒家', '儒家 论语'),
    ExploreSub('易经', '易经 周易 讲解'),
    ExploreSub('民间信仰', '民间信仰 庙会 妈祖'),
    ExploreSub('国学', '国学 传统文化'),
    ExploreSub('神话传说', '中国神话 传说 mythology'),
  ]),
  ExploreTopic('印度教', Icons.temple_hindu_rounded, 'Hinduism 印度教', subs: [
    ExploreSub('经典', 'Bhagavad Gita Upanishads explained'),
    ExploreSub('印度教哲学', 'Hindu philosophy Vedanta'),
    ExploreSub('神祇', 'Hindu gods Shiva Vishnu'),
    ExploreSub('大师讲座', 'Hindu swami lecture'),
    ExploreSub('仪式', 'Hindu puja ritual'),
    ExploreSub('瑜伽与冥想', 'yoga philosophy meditation Hindu'),
    ExploreSub('圣歌', 'bhajan kirtan'),
    ExploreSub('历史', 'Hindu history'),
    ExploreSub('文化', 'Hindu culture festival'),
  ]),
  ExploreTopic('犹太教', Icons.synagogue_rounded, 'Judaism 犹太教', subs: [
    ExploreSub('经典', 'Torah Talmud study'),
    ExploreSub('拉比讲座', 'rabbi lecture'),
    ExploreSub('历史', 'Jewish history'),
    ExploreSub('传统', 'Jewish traditions Shabbat'),
    ExploreSub('节日', 'Jewish holidays'),
    ExploreSub('犹太哲学', 'Jewish philosophy Maimonides'),
    ExploreSub('卡巴拉', 'Kabbalah'),
    ExploreSub('希伯来语', 'Hebrew learning'),
  ]),
  ExploreTopic('其他宗教', Icons.public_rounded, 'world religions', subs: [
    ExploreSub('世界宗教概览', 'world religions explained'),
    ExploreSub('锡克教', 'Sikhism'),
    ExploreSub('耆那教', 'Jainism'),
    ExploreSub('神道教', 'Shinto 神道'),
    ExploreSub('巴哈伊信仰', 'Bahai Faith'),
    ExploreSub('琐罗亚斯德教', 'Zoroastrianism'),
    ExploreSub('原住民宗教', 'indigenous spirituality religion'),
    ExploreSub('古代宗教', 'ancient religions Egypt Greece Rome'),
    ExploreSub('新异教', 'neopaganism Norse paganism'),
  ]),
];

/// 宗教学术: history, philosophy and the study of religion, believing or not.
/// 精选专题 holds a few entry points; the topics they touch have their own
/// zones, so it is kept short.
const faithStudyTopics = <ExploreTopic>[
  ExploreTopic('精选专题', Icons.star_rounded, 'religion documentary 宗教 纪录片', subs: [
    ExploreSub('今日宗教新闻', 'religion news 宗教新闻'),
    ExploreSub('世界宗教纪录片', 'world religions documentary'),
    ExploreSub('宗教历史与考古', 'biblical archaeology religious history'),
    ExploreSub('宗教哲学深度讨论', 'philosophy of religion discussion'),
    ExploreSub('宗教与现代科学', 'religion and science'),
    ExploreSub('优质宗教教育频道', 'religious studies lecture course'),
  ]),
  ExploreTopic('宗教历史', Icons.history_edu_rounded, 'history of religion 宗教史', subs: [
    ExploreSub('教会史', 'church history 教会史'),
    ExploreSub('早期基督教', 'early Christianity history'),
    ExploreSub('宗教改革', 'Protestant Reformation history'),
    ExploreSub('中世纪宗教', 'medieval religion crusades'),
    ExploreSub('宗教传播', 'spread of religions history'),
    ExploreSub('考古', 'biblical archaeology'),
    ExploreSub('伊斯兰黄金时代', 'Islamic Golden Age'),
    ExploreSub('古代近东', 'ancient Near East religion'),
  ]),
  ExploreTopic('宗教哲学', Icons.psychology_rounded, 'philosophy of religion 宗教哲学', subs: [
    ExploreSub('宗教哲学', 'philosophy of religion'),
    ExploreSub('神学', 'theology lecture 神学'),
    ExploreSub('形而上学', 'metaphysics God argument'),
    ExploreSub('信仰与理性', 'faith and reason'),
    ExploreSub('恶的问题', 'problem of evil theodicy'),
    ExploreSub('神秘主义', 'mysticism religious experience'),
    ExploreSub('伦理学', 'religious ethics'),
    ExploreSub('护教学', 'apologetics'),
  ]),
  ExploreTopic('比较宗教学', Icons.compare_arrows_rounded, 'comparative religion 比较宗教', subs: [
    ExploreSub('世界宗教入门', 'introduction to world religions course'),
    ExploreSub('宗教异同', 'comparative religion differences'),
    ExploreSub('学术研究', 'religious studies academic'),
    ExploreSub('宗教社会学', 'sociology of religion'),
    ExploreSub('宗教心理学', 'psychology of religion'),
    ExploreSub('宗教人类学', 'anthropology of religion'),
    ExploreSub('神话学', 'comparative mythology'),
    ExploreSub('仪式研究', 'ritual studies religion'),
  ]),
  ExploreTopic('经典研究', Icons.auto_stories_rounded, 'scripture study 经典', subs: [
    ExploreSub('圣经', 'Bible study 圣经'),
    ExploreSub('旧约', 'Hebrew Bible Old Testament scholarship'),
    ExploreSub('新约', 'New Testament scholarship'),
    ExploreSub('古兰经', 'Quran tafsir'),
    ExploreSub('佛经', '佛经 讲解'),
    ExploreSub('道德经', '道德经 讲解'),
    ExploreSub('吠陀与奥义书', 'Vedas Upanishads'),
    ExploreSub('塔木德', 'Talmud study'),
    ExploreSub('死海古卷与次经', 'Dead Sea Scrolls apocrypha'),
  ]),
  ExploreTopic('宗教与社会', Icons.groups_rounded, 'religion and society', subs: [
    ExploreSub('宗教自由', 'religious freedom'),
    ExploreSub('宗教与政治', 'religion and politics'),
    ExploreSub('世俗化', 'secularization'),
    ExploreSub('宗教与性别', 'religion and gender'),
    ExploreSub('宗教与冲突', 'religion and conflict violence'),
    ExploreSub('宗教与生命伦理', 'religion bioethics'),
    ExploreSub('宗教人口趋势', 'religious demographics trends'),
  ]),
  ExploreTopic('无神论与宗教批评', Icons.help_outline_rounded, 'atheism religion debate', subs: [
    ExploreSub('无神论', 'atheism'),
    ExploreSub('不可知论', 'agnosticism'),
    ExploreSub('世俗人文主义', 'secular humanism'),
    ExploreSub('宗教批判', 'critique of religion'),
    ExploreSub('前信徒经历', 'ex-believer deconversion story'),
    ExploreSub('圣经批判研究', 'biblical criticism historical critical'),
  ]),
  ExploreTopic('宗教对话', Icons.forum_rounded, 'interfaith dialogue 宗教对话', subs: [
    ExploreSub('宗教间对话', 'interfaith dialogue'),
    ExploreSub('教派交流', 'ecumenical dialogue'),
    ExploreSub('信仰与非信仰者', 'believer atheist conversation'),
    ExploreSub('神学辩论', 'theology debate'),
    ExploreSub('圆桌座谈', 'religion roundtable panel'),
    ExploreSub('宗教领袖访谈', 'religious leader interview'),
  ]),
];

/// 文化艺术: art, buildings, music, festivals and faith around the world.
const faithArtsTopics = <ExploreTopic>[
  ExploreTopic('宗教艺术', Icons.palette_rounded, 'sacred art 宗教艺术', subs: [
    ExploreSub('宗教绘画', 'religious painting art history'),
    ExploreSub('圣像', 'icon painting iconography'),
    ExploreSub('宗教雕塑', 'religious sculpture'),
    ExploreSub('彩绘玻璃', 'stained glass'),
    ExploreSub('手抄本', 'illuminated manuscripts'),
    ExploreSub('伊斯兰书法与几何', 'Islamic calligraphy geometric art'),
    ExploreSub('唐卡与曼荼罗', 'thangka mandala'),
    ExploreSub('宗教电影', 'religious film'),
  ]),
  ExploreTopic('宗教建筑', Icons.account_balance_rounded, 'famous religious buildings 宗教建筑', subs: [
    ExploreSub('世界著名宗教建筑', 'famous religious buildings world'),
    ExploreSub('教堂', 'cathedral architecture 教堂'),
    ExploreSub('清真寺', 'mosque architecture'),
    ExploreSub('寺庙', 'temple architecture 寺庙'),
    ExploreSub('印度教神庙', 'Hindu temple architecture'),
    ExploreSub('道观', '道观 Taoist temple'),
    ExploreSub('犹太会堂', 'synagogue architecture'),
    ExploreSub('修道院', 'monastery architecture'),
  ]),
  ExploreTopic('宗教纪录片', Icons.movie_rounded, 'religion documentary 宗教 纪录片', subs: [
    ExploreSub('世界宗教', 'world religions documentary'),
    ExploreSub('修道院生活', 'monastery life documentary'),
    ExploreSub('朝圣之旅', 'pilgrimage documentary'),
    ExploreSub('圣地探访', 'holy land documentary'),
    ExploreSub('人物传记', 'religious figure biography documentary'),
    ExploreSub('信徒日常', 'daily life of believers documentary'),
  ]),
  ExploreTopic('宗教音乐', Icons.music_note_rounded, 'sacred music', subs: [
    ExploreSub('赞美诗', 'hymns choir'),
    ExploreSub('敬拜音乐', 'worship music'),
    ExploreSub('额我略圣歌', 'Gregorian chant'),
    ExploreSub('拜占庭圣咏', 'Byzantine chant'),
    ExploreSub('圣乐合唱', 'sacred choral music'),
    ExploreSub('管风琴', 'church pipe organ'),
    ExploreSub('佛教音乐', '佛教音乐 梵呗'),
    ExploreSub('苏菲音乐', 'Sufi music qawwali'),
    ExploreSub('伊斯兰颂歌', 'nasheed'),
    ExploreSub('印度圣歌', 'kirtan bhajan'),
  ]),
  ExploreTopic('节日与习俗', Icons.celebration_rounded, 'religious festivals', subs: [
    ExploreSub('圣诞节', 'Christmas tradition 圣诞'),
    ExploreSub('复活节', 'Easter tradition 复活节'),
    ExploreSub('圣周', 'Holy Week processions'),
    ExploreSub('斋月', 'Ramadan'),
    ExploreSub('开斋节与宰牲节', 'Eid al-Fitr Eid al-Adha'),
    ExploreSub('排灯节', 'Diwali'),
    ExploreSub('卫塞节', 'Vesak'),
    ExploreSub('光明节', 'Hanukkah'),
    ExploreSub('人生礼仪', 'religious wedding funeral rites'),
  ]),
  ExploreTopic('世界宗教文化', Icons.public_rounded, 'religious culture around the world', subs: [
    ExploreSub('中国', 'China religious culture 中国 宗教文化'),
    ExploreSub('日本与韩国', 'Japan Korea religious culture'),
    ExploreSub('南亚', 'South Asia religious culture'),
    ExploreSub('东南亚', 'Southeast Asia religious culture'),
    ExploreSub('中东', 'Middle East religious heritage'),
    ExploreSub('欧洲', 'Europe religious traditions'),
    ExploreSub('美洲', 'Americas faith traditions'),
    ExploreSub('非洲', 'Africa religion culture'),
  ]),
];

/// 宗教直播: services, prayer, talks and holy places, now or coming up.
const faithLiveTopics = <ExploreTopic>[
  ExploreTopic('宗教礼仪', Icons.church_rounded, 'Holy Mass live 弥撒 直播', subs: [
    ExploreSub('主日礼拜', 'Sunday church service live 主日崇拜'),
    ExploreSub('弥撒', 'Holy Mass live 弥撒'),
    ExploreSub('圣餐礼', 'Holy Communion service live'),
    ExploreSub('东正教神圣礼仪', 'Divine Liturgy live'),
    ExploreSub('圣公会晚祷', 'Evensong live'),
    ExploreSub('主麻聚礼', "Friday prayer Jumu'ah live"),
    ExploreSub('犹太安息日', 'Shabbat service live'),
    ExploreSub('佛教法会', '法会 直播'),
    ExploreSub('印度教祭仪', 'Hindu puja aarti live'),
  ]),
  ExploreTopic('祈祷与冥想', Icons.self_improvement_rounded, 'prayer live 祈祷', subs: [
    ExploreSub('祈祷', 'prayer live 祈祷 直播'),
    ExploreSub('玫瑰经', 'rosary live 玫瑰经'),
    ExploreSub('日课', 'Liturgy of the Hours live'),
    ExploreSub('朝拜圣体', 'Eucharistic adoration live'),
    ExploreSub('泰泽祈祷', 'Taize prayer live'),
    ExploreSub('禅修', 'meditation live 禅修'),
    ExploreSub('诵经', '诵经 直播'),
    ExploreSub('古兰经诵读', 'Quran recitation live'),
  ]),
  ExploreTopic('宗教讲道', Icons.record_voice_over_rounded, 'sermon live', subs: [
    ExploreSub('牧师讲道', 'church sermon live'),
    ExploreSub('神父讲道', 'Catholic homily live'),
    ExploreSub('法师开示', '法师 开示 直播'),
    ExploreSub('伊玛目演讲', 'imam khutbah live'),
    ExploreSub('拉比讲授', 'rabbi Torah class live'),
    ExploreSub('宗教讲座', 'religious lecture live'),
    ExploreSub('灵修分享', 'devotional live'),
  ]),
  ExploreTopic('宗教音乐', Icons.music_note_rounded, 'sacred music live', subs: [
    ExploreSub('敬拜赞美', 'worship praise live'),
    ExploreSub('唱诗班', 'church choir live'),
    ExploreSub('圣咏', 'chant live'),
    ExploreSub('管风琴演奏', 'organ recital live'),
    ExploreSub('宗教音乐会', 'sacred music concert live'),
    ExploreSub('苏菲与颂歌', 'qawwali nasheed live'),
  ]),
  ExploreTopic('宗教教育', Icons.school_rounded, 'theology class live', subs: [
    ExploreSub('经典研读', 'Bible study live'),
    ExploreSub('神学课程', 'theology course live'),
    ExploreSub('教理问答', 'catechism class live'),
    ExploreSub('佛学课程', 'Buddhist teaching class live 佛学'),
    ExploreSub('古兰经课堂', 'Quran class live'),
    ExploreSub('塔木德课', 'Talmud class live'),
    ExploreSub('在线教学', 'religious education live'),
  ]),
  ExploreTopic('宗教新闻', Icons.newspaper_rounded, 'Vatican live', subs: [
    ExploreSub('宗教新闻', 'religion news live'),
    ExploreSub('教宗与梵蒂冈', 'Pope Vatican live'),
    ExploreSub('宗教会议', 'synod live'),
    ExploreSub('重要宗教事件', 'religious event live'),
    ExploreSub('宗教领袖访谈', 'religious leader interview live'),
  ]),
  ExploreTopic('宗教节庆', Icons.celebration_rounded, 'religious festival live', subs: [
    ExploreSub('圣诞节', 'Christmas Mass live'),
    ExploreSub('复活节', 'Easter Vigil live'),
    ExploreSub('圣周游行', 'Holy Week procession live'),
    ExploreSub('斋月', 'Ramadan live'),
    ExploreSub('开斋节', 'Eid prayer live'),
    ExploreSub('卫塞节', 'Vesak live'),
    ExploreSub('排灯节', 'Diwali live'),
  ]),
  ExploreTopic('宗教对话', Icons.forum_rounded, 'interfaith dialogue live', subs: [
    ExploreSub('神学辩论', 'theology debate live'),
    ExploreSub('跨宗教讨论', 'interfaith discussion live'),
    ExploreSub('圆桌座谈', 'religion panel roundtable live'),
    ExploreSub('公开问答', 'religious Q&A live'),
    ExploreSub('信仰访谈', 'faith interview live'),
  ]),
  ExploreTopic('圣地实况', Icons.videocam_rounded, 'shrine live cam', subs: [
    ExploreSub('麦加', 'Makkah live'),
    ExploreSub('麦地那', 'Madinah live'),
    ExploreSub('圣伯多禄广场', "St Peter's Square live"),
    ExploreSub('耶路撒冷', 'Jerusalem live'),
    ExploreSub('哭墙', 'Western Wall live'),
    ExploreSub('卢尔德', 'Lourdes live'),
    ExploreSub('法蒂玛', 'Fatima live'),
    ExploreSub('恒河', 'Ganga Aarti Varanasi live'),
    ExploreSub('佛寺', 'Buddhist temple live cam'),
    ExploreSub('教堂', 'church live cam'),
  ]),
  ExploreTopic('宗教电台', Icons.radio_rounded, 'Catholic radio 24/7 live', subs: [
    ExploreSub('讲道电台', 'sermon radio 24/7'),
    ExploreSub('宗教音乐电台', 'sacred music radio 24/7'),
    ExploreSub('祈祷电台', 'prayer radio live'),
    ExploreSub('天主教电台', 'Catholic radio 24/7'),
    ExploreSub('古兰经电台', 'Quran radio 24/7'),
    ExploreSub('佛号电台', '佛教 念佛 24小时 chanting 24/7'),
  ]),
];

/// 宗教与信仰's 类型 filter: words added to the zone's search.
enum FaithFormat implements WordFilter {
  any('不限', ''),
  lecture('讲座', 'lecture 讲座'),
  documentary('纪录片', 'documentary 纪录片'),
  liturgy('礼仪', 'liturgy 礼仪'),
  interview('访谈', 'interview 访谈'),
  debate('辩论', 'debate 辩论'),
  music('音乐', 'music 音乐'),
  news('新闻', 'news 新闻');

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
  any('不限', ''),
  inside('信仰内部视角', 'sermon testimony 信仰分享'),
  academic('学术中立研究', 'academic lecture university'),
  critical('批判性讨论', 'critique criticism'),
  dialogue('宗教间对话', 'interfaith dialogue');

  const FaithView(this._label, this.words);
  final String _label;
  @override
  String get label => tr(_label);
  @override
  final String words;
}

final _baitWords = RegExp(
  r'震惊|炸裂|吊打|打脸|怒怼|惊呆|毁三观|跪了|destroy|owned|exposed|humiliat|wreck|shocking|obliterat|demolish|you won.t believe|triggered',
  caseSensitive: false,
);

/// Whether [title] reads like bait: three or more exclamation marks, a
/// title mostly in capitals, or words such as "destroys" and 吊打. Such
/// videos are left out of 宗教与信仰, where they tend to crowd out the rest.
bool looksLikeBait(String title) {
  if ('!'.allMatches(title).length + '！'.allMatches(title).length >= 3) return true;
  if (_baitWords.hasMatch(title)) return true;
  final letters = title.replaceAll(RegExp(r'[^A-Za-z]'), '');
  return letters.length >= 12 && letters.replaceAll(RegExp('[^A-Z]'), '').length > letters.length * 0.7;
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
