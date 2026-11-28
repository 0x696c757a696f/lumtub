import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/church_wording.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/native_core.dart';

void main() {
  test('Eastern Catholic videos are of the Byzantine rite, others of the Latin', () {
    expect(ChurchWording.riteOf('Divine Liturgy | Ukrainian Greek Catholic Church'),
        ChurchRite.byzantine);
    expect(ChurchWording.riteOf('Byzantine Catholic Vespers'), ChurchRite.byzantine);
    expect(ChurchWording.riteOf('Santa Messa presieduta da Papa Leone XIV'), ChurchRite.latin);
    expect(ChurchWording.riteOf('Greek Orthodox Vespers'), isNull);
  });

  test('Catholic videos in any language are Catholic, Eastern Catholic ones too', () {
    for (final text in [
      'Santa Messa presieduta da Papa Leone XIV',
      'Catholic Answers: Why do Catholics pray the Rosary?',
      'Divine Liturgy | Ukrainian Greek Catholic Church',
      'Byzantine Catholic Vespers',
      '天主教主日弥撒',
      'Msza Święta na żywo z parafii katolickiej',
    ]) {
      expect(ChurchWording.isCatholicText(text), isTrue, reason: text);
    }
  });

  test('Orthodox, Protestant and other videos are not', () {
    for (final text in [
      'Divine Liturgy at the Russian Orthodox Cathedral',
      'Greek Orthodox Vespers',
      '东正教圣事',
      'Sunday sermon with Pastor John | Baptist church',
      '基督教主日崇拜',
      'How to cook pasta',
      '',
    ]) {
      expect(ChurchWording.isCatholicText(text), isFalse, reason: text);
    }
  });

  test('the Pope in any language is Catholic', () {
    for (final text in [
      'Le pape Léon XIV en Turquie',
      'Papież Leon XIV w Turcji',
      'O Papa Leão XIV na Turquia',
      'Il Papa in Turchia',
      'Leo XIV: first year',
      'La Santa Sede risponde'
    ]) {
      expect(ChurchWording.isCatholicText(text), isTrue, reason: text);
    }
    expect(ChurchWording.isCatholicText('La papa es una verdura'), isFalse);
  });

  test("a Catholic channel's videos are Catholic though their titles say nothing", () {
    VideoItem item(String id, String title, String channel) => VideoItem(
        id: id,
        title: title,
        channel: channel,
        channelId: channel,
        url: 'https://www.youtube.com/watch?v=$id');
    expect(ChurchWording.riteOfVideo(item('a', 'My morning routine', 'UCnoted')), isNull);
    ChurchWording.noteChannel('UCnoted', ChurchRite.latin);
    expect(ChurchWording.riteOfVideo(item('a', 'My morning routine', 'UCnoted')), ChurchRite.latin);
    // Three Catholic videos of eight seen make a channel Catholic.
    for (final (i, title) in [
      'Praying the rosary',
      'Why I go to Holy Mass',
      'Day 1',
      'Day 2',
      'Day 3',
      'Day 4',
      'Day 5',
      'Day 6'
    ].indexed) {
      ChurchWording.riteOfVideo(item('t$i', title, 'UCseen'));
    }
    expect(ChurchWording.riteOfChannel('UCseen'), isNull);
    ChurchWording.riteOfVideo(item('t8', 'Our Lady of Fatima', 'UCseen'));
    // Shown again, a video is not counted again.
    ChurchWording.riteOfVideo(item('t8', 'Our Lady of Fatima', 'UCseen'));
    expect(ChurchWording.riteOfChannel('UCseen'), ChurchRite.latin);
    expect(ChurchWording.riteOfVideo(item('t9', 'Day 7', 'UCseen')), ChurchRite.latin);
    expect(ChurchWording.riteOfChannel('UCother'), isNull);
  });

  test('a video counts its channel and description', () {
    VideoItem item(String channel) => VideoItem(
        id: 'x',
        title: 'Sunday homily',
        channel: channel,
        url: 'https://www.youtube.com/watch?v=x');
    expect(ChurchWording.isCatholicVideo(item('Vatican News')), isTrue);
    expect(ChurchWording.isCatholicVideo(item('Daily Talks')), isFalse);
    expect(
        ChurchWording.isCatholicVideo(item('Daily Talks'),
            description: 'From the Archdiocese of Milan'),
        isTrue);
  });

  test('only Chinese translations of Catholic text change', () {
    // Without lumtub_core nothing changes, and other targets never do.
    expect(ChurchWording.apply('God bless', 'en', rite: ChurchRite.latin), 'God bless');
    expect(ChurchWording.apply('上帝保佑', 'zh-CN', rite: null), '上帝保佑');
  });

  test('with lumtub_core, Catholic Chinese translations take the Church\'s words', () {
    if (NativeCore.instance == null) return markTestSkipped('needs lumtub_core');
    const latin = ChurchRite.latin;
    expect(ChurchWording.apply('西门彼得对约翰说：上帝的弥赛亚来了', 'zh-CN', rite: latin), '西满伯多禄对若望说：天主的默西亚来了');
    expect(ChurchWording.apply('他行了神迹，神父来了', 'zh-CN', rite: latin), '他行了神迹，神父来了');
    expect(ChurchWording.apply('上帝的弥赛亚', 'ja', rite: latin), '上帝的弥赛亚');
    expect(
        ChurchWording.apply('圣父抵达罗马', 'zh-CN',
            rite: latin, original: 'Il Santo Padre arriva a Roma'),
        '教宗抵达罗马');
    expect(ChurchWording.apply('我们向圣父祈祷', 'zh-CN', rite: latin, original: 'Preghiamo il Padre'),
        '我们向圣父祈祷');
    expect(ChurchWording.apply('四旬期', 'zh-CN', rite: ChurchRite.byzantine, original: 'Great Lent'),
        '大斋期');
    ChurchWording.hongKong = () => false;
    expect(ChurchWording.apply('那位牧師在主持彌撒。阿門', 'zh-TW', rite: latin), '那位神父在主持彌撒。阿們');
    ChurchWording.hongKong = () => true;
    expect(ChurchWording.apply('那位牧師在主持彌撒。阿門', 'zh-TW', rite: latin), '那位神父在主持彌撒。亞孟');
    expect(ChurchWording.apply('和好聖事', 'zh-HK', rite: latin), '修和聖事');
  });
}
