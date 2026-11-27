import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/church_wording.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/native_core.dart';

void main() {
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

  test('a video counts its channel and description', () {
    VideoItem item(String channel) => VideoItem(id: 'x', title: 'Sunday homily', channel: channel, url: 'https://www.youtube.com/watch?v=x');
    expect(ChurchWording.isCatholicVideo(item('Vatican News')), isTrue);
    expect(ChurchWording.isCatholicVideo(item('Daily Talks')), isFalse);
    expect(ChurchWording.isCatholicVideo(item('Daily Talks'), description: 'From the Archdiocese of Milan'), isTrue);
  });

  test('only Chinese translations of Catholic text change', () {
    // Without lumtub_core nothing changes, and other targets never do.
    expect(ChurchWording.apply('God bless', 'en', catholic: true), 'God bless');
    expect(ChurchWording.apply('上帝保佑', 'zh-CN', catholic: false), '上帝保佑');
  });

  test('with lumtub_core, Catholic Chinese translations take the Church\'s words', () {
    if (NativeCore.instance == null) return markTestSkipped('needs lumtub_core');
    expect(ChurchWording.apply('西门彼得对约翰说：上帝的弥赛亚来了', 'zh-CN', catholic: true), '西满伯多禄对若望说：天主的默西亚来了');
    expect(ChurchWording.apply('那位牧師在主持彌撒，聖靈降臨', 'zh-TW', catholic: true), '那位神父在主持彌撒，聖神降臨');
    expect(ChurchWording.apply('他行了神迹，神父来了', 'zh-CN', catholic: true), '他行了神迹，神父来了');
    expect(ChurchWording.apply('上帝的弥赛亚', 'ja', catholic: true), '上帝的弥赛亚');
  });
}
