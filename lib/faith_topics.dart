import 'package:flutter/material.dart' show Icons;

import 'explore_filters.dart';
import 'explore_topics.dart';
import 'l10n/l10n.dart';
import 'models.dart';

// The zones of 宗教与信仰, one list per tab. Each is a YouTube search, so a
// channel can turn up under every tradition or theme it speaks to; nothing
// here decides what a channel "is".

/// 宗教传统: the traditions, with Christianity's split a level further.
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
    ExploreSub('逊尼派', 'Sunni Islam'),
    ExploreSub('什叶派', 'Shia Islam'),
    ExploreSub('古兰经', 'Quran recitation 古兰经'),
    ExploreSub('伊斯兰历史', 'Islamic history 伊斯兰 历史'),
    ExploreSub('伊斯兰神学', 'Islamic theology'),
    ExploreSub('伊斯兰文化', 'Islamic culture 伊斯兰文化'),
  ]),
  ExploreTopic('佛教', Icons.temple_buddhist_rounded, '佛教 佛法', subs: [
    ExploreSub('汉传佛教', '汉传佛教 法师 开示'),
    ExploreSub('藏传佛教', '藏传佛教 Tibetan Buddhism'),
    ExploreSub('南传佛教', '南传佛教 Theravada'),
    ExploreSub('禅宗', '禅宗 Zen'),
    ExploreSub('佛经', '佛经 讲解'),
  ]),
  ExploreTopic('道教与中国传统信仰', Icons.self_improvement_rounded, '道教 文化', subs: [
    ExploreSub('道教经典', '道德经 庄子 讲解'),
    ExploreSub('道教文化', '道教 文化 道观'),
    ExploreSub('民间信仰', '民间信仰 庙会 妈祖'),
    ExploreSub('儒家', '儒家 论语'),
  ]),
  ExploreTopic('印度教', Icons.temple_hindu_rounded, 'Hinduism 印度教', subs: [
    ExploreSub('印度教哲学', 'Hindu philosophy Vedanta'),
    ExploreSub('经典', 'Bhagavad Gita Upanishads explained'),
    ExploreSub('仪式', 'Hindu puja ritual'),
    ExploreSub('文化', 'Hindu culture festival'),
  ]),
  ExploreTopic('犹太教', Icons.synagogue_rounded, 'Judaism 犹太教', subs: [
    ExploreSub('经典', 'Torah Talmud study'),
    ExploreSub('拉比讲座', 'rabbi lecture'),
    ExploreSub('历史', 'Jewish history'),
    ExploreSub('传统', 'Jewish traditions Shabbat'),
  ]),
  ExploreTopic('其他宗教', Icons.public_rounded, 'world religions', subs: [
    ExploreSub('锡克教', 'Sikhism'),
    ExploreSub('耆那教', 'Jainism'),
    ExploreSub('巴哈伊信仰', 'Bahai Faith'),
    ExploreSub('神道教', 'Shinto 神道'),
    ExploreSub('琐罗亚斯德教', 'Zoroastrianism'),
    ExploreSub('原住民宗教', 'indigenous spirituality religion'),
  ]),
];

/// 宗教学术: history, philosophy and the study of religion, believing or not.
const faithStudyTopics = <ExploreTopic>[
  ExploreTopic('精选专题', Icons.star_rounded, 'religion documentary 宗教 纪录片', subs: [
    ExploreSub('今日宗教新闻', 'religion news 宗教新闻'),
    ExploreSub('世界宗教纪录片', 'world religions documentary'),
    ExploreSub('宗教历史与考古', 'biblical archaeology religious history'),
    ExploreSub('宗教哲学深度讨论', 'philosophy of religion discussion'),
    ExploreSub('经典与原典研究', 'scripture original language study'),
    ExploreSub('宗教与现代科学', 'religion and science'),
    ExploreSub('宗教改革与思想史', 'Reformation intellectual history'),
    ExploreSub('不同宗教观点比较', 'comparative religion views'),
    ExploreSub('优质宗教教育频道', 'religious studies lecture course'),
  ]),
  ExploreTopic('宗教历史', Icons.history_edu_rounded, 'history of religion 宗教史', subs: [
    ExploreSub('教会史', 'church history 教会史'),
    ExploreSub('宗教改革', 'Protestant Reformation history'),
    ExploreSub('宗教传播', 'spread of religions history'),
    ExploreSub('考古', 'biblical archaeology'),
  ]),
  ExploreTopic('宗教哲学', Icons.psychology_rounded, 'philosophy of religion 宗教哲学', subs: [
    ExploreSub('神学', 'theology lecture 神学'),
    ExploreSub('形而上学', 'metaphysics God argument'),
    ExploreSub('伦理学', 'religious ethics'),
    ExploreSub('宗教哲学', 'philosophy of religion'),
  ]),
  ExploreTopic('比较宗教学', Icons.compare_arrows_rounded, 'comparative religion 比较宗教', subs: [
    ExploreSub('宗教异同', 'comparative religion differences'),
    ExploreSub('学术研究', 'religious studies academic'),
    ExploreSub('宗教社会学', 'sociology of religion'),
  ]),
  ExploreTopic('经典研究', Icons.auto_stories_rounded, 'scripture study 经典', subs: [
    ExploreSub('圣经', 'Bible study 圣经'),
    ExploreSub('古兰经', 'Quran tafsir'),
    ExploreSub('佛经', '佛经 讲解'),
    ExploreSub('道德经', '道德经 讲解'),
    ExploreSub('吠陀与奥义书', 'Vedas Upanishads'),
    ExploreSub('塔木德', 'Talmud study'),
  ]),
  ExploreTopic('宗教与社会', Icons.groups_rounded, 'religion and society', subs: [
    ExploreSub('宗教自由', 'religious freedom'),
    ExploreSub('宗教与政治', 'religion and politics'),
    ExploreSub('宗教与科学', 'religion and science'),
    ExploreSub('宗教新闻', 'religion news'),
  ]),
  ExploreTopic('无神论与宗教批评', Icons.help_outline_rounded, 'atheism religion debate', subs: [
    ExploreSub('无神论', 'atheism'),
    ExploreSub('不可知论', 'agnosticism'),
    ExploreSub('世俗人文主义', 'secular humanism'),
    ExploreSub('宗教批判', 'critique of religion'),
  ]),
  ExploreTopic('宗教对话', Icons.forum_rounded, 'interfaith dialogue 宗教对话', subs: [
    ExploreSub('宗教间对话', 'interfaith dialogue'),
    ExploreSub('教派交流', 'ecumenical dialogue'),
    ExploreSub('信仰与非信仰者', 'believer atheist conversation'),
  ]),
];

/// 文化艺术: art, buildings, music, festivals and faith around the world.
const faithArtsTopics = <ExploreTopic>[
  ExploreTopic('宗教艺术', Icons.palette_rounded, 'sacred art 宗教艺术', subs: [
    ExploreSub('圣乐', 'sacred music 圣乐'),
    ExploreSub('宗教绘画', 'religious painting art history'),
    ExploreSub('圣像', 'icon painting iconography'),
    ExploreSub('宗教电影', 'religious film'),
  ]),
  ExploreTopic('宗教建筑', Icons.account_balance_rounded, 'famous religious buildings 宗教建筑', subs: [
    ExploreSub('教堂', 'cathedral architecture 教堂'),
    ExploreSub('清真寺', 'mosque architecture'),
    ExploreSub('寺庙', 'temple architecture 寺庙'),
    ExploreSub('世界著名宗教建筑', 'famous religious buildings world'),
  ]),
  ExploreTopic('宗教纪录片', Icons.movie_rounded, 'religion documentary 宗教 纪录片', subs: [
    ExploreSub('世界宗教', 'world religions documentary'),
    ExploreSub('修道院生活', 'monastery life documentary'),
    ExploreSub('朝圣之旅', 'pilgrimage documentary'),
  ]),
  ExploreTopic('宗教音乐', Icons.music_note_rounded, 'sacred music', subs: [
    ExploreSub('额我略圣歌', 'Gregorian chant'),
    ExploreSub('拜占庭圣咏', 'Byzantine chant'),
    ExploreSub('赞美诗', 'hymns choir'),
    ExploreSub('佛教音乐', '佛教音乐 梵呗'),
    ExploreSub('苏菲音乐', 'Sufi music qawwali'),
  ]),
  ExploreTopic('节日与习俗', Icons.celebration_rounded, 'religious festivals', subs: [
    ExploreSub('圣诞节', 'Christmas tradition 圣诞'),
    ExploreSub('复活节', 'Easter tradition 复活节'),
    ExploreSub('斋月', 'Ramadan'),
    ExploreSub('卫塞节', 'Vesak'),
    ExploreSub('光明节', 'Hanukkah'),
    ExploreSub('排灯节', 'Diwali'),
  ]),
  ExploreTopic('世界宗教文化', Icons.public_rounded, 'religious culture around the world', subs: [
    ExploreSub('欧洲', 'Europe religious traditions'),
    ExploreSub('亚洲', 'Asia religious culture'),
    ExploreSub('美洲', 'Americas faith traditions'),
    ExploreSub('非洲', 'Africa religion culture'),
    ExploreSub('中东', 'Middle East religious heritage'),
  ]),
];

/// 宗教直播: services, prayer, talks and holy places, now or coming up.
const faithLiveTopics = <ExploreTopic>[
  ExploreTopic('宗教礼仪', Icons.church_rounded, 'Holy Mass live 弥撒 直播', subs: [
    ExploreSub('弥撒', 'Holy Mass live 弥撒'),
    ExploreSub('圣餐礼', 'Holy Communion service live'),
    ExploreSub('东正教神圣礼仪', 'Divine Liturgy live'),
    ExploreSub('佛教法会', '法会 直播'),
  ]),
  ExploreTopic('祈祷与冥想', Icons.self_improvement_rounded, 'prayer live 祈祷', subs: [
    ExploreSub('玫瑰经', 'rosary live 玫瑰经'),
    ExploreSub('日课', 'Liturgy of the Hours live'),
    ExploreSub('朝拜圣体', 'Eucharistic adoration live'),
    ExploreSub('禅修', 'meditation live 禅修'),
    ExploreSub('诵经', '诵经 直播'),
  ]),
  ExploreTopic('宗教讲道', Icons.record_voice_over_rounded, 'sermon live', subs: [
    ExploreSub('神父讲道', 'Catholic homily live'),
    ExploreSub('牧师讲道', 'church sermon live'),
    ExploreSub('宗教讲座', 'religious lecture live'),
  ]),
  ExploreTopic('宗教音乐', Icons.music_note_rounded, 'sacred music live', subs: [
    ExploreSub('圣咏', 'chant live'),
    ExploreSub('唱诗班', 'church choir live'),
    ExploreSub('宗教音乐会', 'sacred music concert live'),
  ]),
  ExploreTopic('宗教教育', Icons.school_rounded, 'theology class live', subs: [
    ExploreSub('神学课程', 'theology course live'),
    ExploreSub('经典研读', 'Bible study live'),
    ExploreSub('在线教学', 'religious education live'),
  ]),
  ExploreTopic('宗教新闻', Icons.newspaper_rounded, 'Vatican live', subs: [
    ExploreSub('梵蒂冈活动', 'Vatican live'),
    ExploreSub('宗教会议', 'synod live'),
    ExploreSub('重要宗教事件', 'religious event live'),
  ]),
  ExploreTopic('宗教节庆', Icons.celebration_rounded, 'religious festival live', subs: [
    ExploreSub('圣诞节', 'Christmas Mass live'),
    ExploreSub('复活节', 'Easter Vigil live'),
    ExploreSub('斋月', 'Ramadan live'),
    ExploreSub('卫塞节', 'Vesak live'),
  ]),
  ExploreTopic('宗教对话', Icons.forum_rounded, 'interfaith dialogue live', subs: [
    ExploreSub('神学辩论', 'theology debate live'),
    ExploreSub('跨宗教讨论', 'interfaith discussion live'),
  ]),
  ExploreTopic('圣地实况', Icons.videocam_rounded, 'shrine live cam', subs: [
    ExploreSub('圣伯多禄广场', "St Peter's Square live"),
    ExploreSub('卢尔德', 'Lourdes live'),
    ExploreSub('法蒂玛', 'Fatima live'),
    ExploreSub('哭墙', 'Western Wall live'),
    ExploreSub('麦加', 'Makkah live'),
    ExploreSub('教堂', 'church live cam'),
  ]),
  ExploreTopic('宗教电台', Icons.radio_rounded, 'Catholic radio 24/7 live', subs: [
    ExploreSub('讲道电台', 'sermon radio 24/7'),
    ExploreSub('宗教音乐电台', 'sacred music radio 24/7'),
    ExploreSub('祈祷电台', 'prayer radio live'),
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
