import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/explore_topics.dart';
import 'package:lumtub/faith_topics.dart';
import 'package:lumtub/faith_traditions.dart';
import 'package:lumtub/models.dart';

VideoItem video(String title, {String channel = '', String? description}) =>
    VideoItem(id: title, title: title, channel: channel, url: '', description: description);

void main() {
  bool admits(FaithTradition t, String title,
          {String channel = '', String? description, bool? strict}) =>
      t.admits(video(title, channel: channel, description: description),
          strict: strict ?? t.strict);

  test('the Catholic zone leaves out Chinese Protestant videos', () {
    const catholic = FaithTradition.catholic;
    // What 天主教 searches bring: Catholic videos say so, or say 弥撒, 神父, 圣母.
    expect(admits(catholic, '天主教要理讲座 第三讲'), isTrue);
    expect(admits(catholic, '主日弥撒 常年期第三十三主日', channel: '台北总教区'), isTrue);
    expect(admits(catholic, '玫瑰经 光明五端'), isTrue);
    expect(admits(catholic, '聖母無原罪瞻禮 彌撒直播'), isTrue);
    expect(admits(catholic, '教宗良十四世公開接見'), isTrue);
    // Protestant ones say 基督教, 牧师, 讲道, 主日崇拜, 和合本 instead.
    expect(admits(catholic, '基督教 主日崇拜 | 牧师讲道'), isFalse);
    expect(admits(catholic, '罗马书查经 第五课', channel: '基督教灵粮堂'), isFalse);
    expect(admits(catholic, '主日信息：因信称义', description: '欢迎来到我们的团契，经文采用和合本'), isFalse);
    expect(admits(catholic, '赞美之泉 敬拜赞美诗 合集'), isFalse);
    // Saying neither is not enough in a Catholic zone.
    expect(admits(catholic, '约翰福音第三章 查经'), isFalse);
    // A video about both stays.
    expect(admits(catholic, '天主教和基督教的区别是什么？'), isTrue);
  });

  test('Orthodox, Eastern Catholic and Oriental Orthodox keep apart', () {
    expect(admits(FaithTradition.orthodox, '东正教神父谈祈祷'), isTrue);
    expect(admits(FaithTradition.catholic, '东正教神父谈祈祷'), isFalse);
    expect(admits(FaithTradition.orthodox, 'Byzantine Catholic Divine Liturgy'), isFalse);
    expect(admits(FaithTradition.easternCatholic, 'Byzantine Catholic Divine Liturgy'), isTrue);
    expect(admits(FaithTradition.easternCatholic, 'Ukrainian Greek-Catholic Church: a history'),
        isTrue);
    expect(admits(FaithTradition.easternCatholic, 'Latin Mass at St Peter'), isFalse);
    expect(admits(FaithTradition.catholic, 'Byzantine Catholic Divine Liturgy'), isTrue);
    expect(admits(FaithTradition.orthodox, 'Coptic Orthodox Liturgy of St Basil'), isFalse);
    expect(admits(FaithTradition.orientalOrthodox, 'Coptic Orthodox Liturgy of St Basil'), isTrue);
    expect(admits(FaithTradition.orientalOrthodox, 'Coptic Catholic Mass'), isFalse);
    expect(admits(FaithTradition.orthodox, 'Orthodox Jewish wedding', channel: 'Jewish life'),
        isFalse);
    expect(admits(FaithTradition.orthodox, 'Life on Mount Athos'), isTrue);
  });

  test('Protestant branches keep to themselves', () {
    expect(admits(FaithTradition.protestant, 'Sunday sermon', channel: 'First Baptist Church'),
        isTrue);
    expect(
        admits(FaithTradition.baptist, 'Sunday sermon', channel: 'First Baptist Church'), isTrue);
    expect(
        admits(FaithTradition.lutheran, 'Sunday sermon', channel: 'First Baptist Church'), isFalse);
    expect(
        admits(FaithTradition.lutheran, 'Evangelical Lutheran Church in America worship'), isTrue);
    expect(admits(FaithTradition.lutheran, '信义会 主日崇拜'), isTrue);
    expect(admits(FaithTradition.reformed, '长老会 主日讲道'), isTrue);
    expect(admits(FaithTradition.anglican, 'Choral Evensong from Westminster Abbey'), isTrue);
    expect(
        admits(FaithTradition.protestant, 'Holy Mass from St Peter\'s Basilica',
            channel: 'Vatican News'),
        isFalse);
    expect(admits(FaithTradition.protestant, 'Book of Mormon study', channel: 'Latter-day Saints'),
        isFalse);
    expect(
        admits(FaithTradition.catholic, 'Jehovah\'s Witnesses broadcast',
            channel: 'JW Broadcasting'),
        isFalse);
  });

  test('other faiths keep their own zones', () {
    // Not strict: a video naming nothing is kept, one naming another faith is not.
    expect(admits(FaithTradition.buddhism, '心经讲解 第一集'), isTrue);
    expect(admits(FaithTradition.buddhism, '基督教 牧师 见证'), isFalse);
    expect(admits(FaithTradition.pureLand, '净土法门 念佛开示'), isTrue);
    expect(admits(FaithTradition.pureLand, '仁波切 大圆满 开示'), isFalse);
    expect(admits(FaithTradition.tibetanBuddhism, '仁波切 大圆满 开示'), isTrue);
    expect(admits(FaithTradition.zen, '禅宗公案 讲解'), isTrue);
    expect(admits(FaithTradition.zen, 'Zendaya interview'), isTrue,
        reason: 'Zen is a whole word; nothing names a faith');
    expect(admits(FaithTradition.chineseBuddhism, '一贯道 道亲 分享'), isFalse);
    expect(admits(FaithTradition.taoism, '道德经 第一章 讲解'), isTrue);
    expect(admits(FaithTradition.taoism, '佛教 法师 开示'), isFalse);
    expect(admits(FaithTradition.confucianism, '心理学入门'), isTrue,
        reason: '理学 and 心学 are not words to look for');
    expect(admits(FaithTradition.judaism, 'Messianic Jews worship Yeshua'), isFalse);
    expect(admits(FaithTradition.judaism, 'Weekly Torah portion with Rabbi Sacks'), isTrue);
    expect(admits(FaithTradition.islam, 'Islam and Christianity compared'), isTrue,
        reason: 'it is about both');
    expect(admits(FaithTradition.islam, 'Christian pastor reacts to the Quran'), isFalse,
        reason: 'it says more of Christianity');
    expect(admits(FaithTradition.islam, 'Sunday worship with pastor John', channel: 'Grace Church'),
        isFalse);
    expect(admits(FaithTradition.sunni, 'Majlis of Imam Hussain — Muharram night'), isFalse);
    expect(admits(FaithTradition.shia, 'Majlis of Imam Hussain — Muharram night'), isTrue);
    expect(admits(FaithTradition.hinduism, 'Krishna bhajan', channel: 'ISKCON'), isTrue);
    expect(admits(FaithTradition.sikhism, 'Hindu puja aarti'), isFalse);
  });

  test('words match whole words or word starts, after accents and punctuation', () {
    expect(normalizeFaithText("Jehovah's Witnesses — Católico, Greek-Catholic"),
        'jehovahs witnesses   catolico  greek catholic');
    expect(admits(FaithTradition.catholic, 'Santa Messa e Rosario', channel: 'Parrocchia San Pio'),
        isTrue);
    expect(admits(FaithTradition.catholic, 'Misa de hoy', channel: 'Iglesia Católica'), isTrue);
    expect(admits(FaithTradition.catholic, 'Popeye cartoon'), isFalse);
    expect(admits(FaithTradition.christianity, 'Cristiano Ronaldo goals'), isTrue);
    expect(admits(FaithTradition.buddhism, 'Christopher Nolan interview'), isTrue,
        reason: 'Christopher is not Christ');
    expect(admits(FaithTradition.buddhism, 'Cristiano Ronaldo goals'), isFalse,
        reason: 'cristiano is a word for Christian');
    expect(admits(FaithTradition.catholic, '办公教程 Excel 入门', strict: false), isTrue);
  });

  test('every zone of 宗教与信仰 resolves a tradition the way the controller does', () {
    final christianity = faithTraditionTopics.first;
    expect(christianity.tradition, FaithTradition.christianity);
    final catholic = christianity.subs.first;
    expect(catholic.tradition, FaithTradition.catholic);
    // A Catholic leaf without its own tradition keeps the Catholic one.
    final bible = catholic.subs.firstWhere((s) => s.label == 'Bible study');
    expect(FaithTradition.of([bible.tradition, catholic.tradition, christianity.tradition]),
        FaithTradition.catholic);
    final eastern = catholic.subs.firstWhere((s) => s.label == 'Eastern Catholic');
    expect(eastern.tradition, FaithTradition.easternCatholic);
    final protestant = christianity.subs.firstWhere((s) => s.label == 'Protestant');
    expect(protestant.subs.every((s) => s.tradition?.parent == FaithTradition.protestant), isTrue);
    // Christianity's churches are strict, other faiths and Christianity as a whole are not.
    expect(
        [
          for (final t in FaithTradition.values)
            if (t.strict) t.name
        ],
        containsAll([
          'catholic',
          'easternCatholic',
          'orthodox',
          'orientalOrthodox',
          'protestant',
          'lutheran',
          'baptist'
        ]));
    expect(FaithTradition.christianity.strict, isFalse);
    expect(FaithTradition.buddhism.strict, isFalse);
    // Every live zone naming a tradition is a faith zone.
    for (final topic in exploreTopicsOf(ExploreSection.faithLive)) {
      for (final sub in topic.subs) {
        if (sub.tradition == FaithTradition.catholic) {
          expect(sub.query, isNot(contains('基督教')), reason: sub.label);
        }
      }
    }
  });

  test('no word is listed twice for one tradition, and none is empty', () {
    for (final t in FaithTradition.values) {
      final words = [...t.strong, ...t.weak];
      expect(words.toSet(), hasLength(words.length), reason: t.name);
      expect(
          words.every((w) => normalizeFaithText(w.replaceAll(r'$', '')).trim().isNotEmpty), isTrue,
          reason: t.name);
    }
  });
}
