import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/chinese_dictionary.dart';

const _sample = '''
# CC-CEDICT sample
中國 中国 [Zhong1 guo2] /China/
中 中 [zhong1] /middle/center/
國 国 [guo2] /country/
人 人 [ren2] /person/
中國人 中国人 [Zhong1 guo2 ren2] /Chinese person/
我 我 [wo3] /I; me/
是 是 [shi4] /is; are/
學習 学习 [xue2 xi2] /to learn; to study/
學 学 [xue2] /to learn/
習 习 [xi2] /to practice/
綠 绿 [lu:4] /green/
了 了 [liao3] /to finish/
了 了 [le5] /(completed action marker)/
研究 研究 [yan2 jiu1] /research/
研究生 研究生 [yan2 jiu1 sheng1] /graduate student/
生命 生命 [sheng1 ming4] /life/
起源 起源 [qi3 yuan2] /origin/
的 的 [de5] /possessive particle/
''';

void main() {
  final dictionary = ChineseDictionary.parse(_sample);

  test('pinyin gets tone marks', () {
    expect(pinyinMarks('ni3 hao3'), 'nǐ hǎo');
    expect(pinyinMarks('lu:4'), 'lǜ');
    expect(pinyinMarks('Zhong1 guo2'), 'Zhōng guó');
    expect(pinyinMarks('gou3 xiong2'), 'gǒu xióng');
    expect(pinyinMarks('liu2 shui3'), 'liú shuǐ');
    expect(pinyinMarks('le5'), 'le');
  });

  test('both scripts find the same entry', () {
    expect(dictionary.lookup('学习').single.senses, ['to learn; to study']);
    expect(dictionary.lookup('學習').single.simplified, '学习');
    expect(dictionary.lookup('没有'), isEmpty);
  });

  test('a line splits into words with readings', () {
    final tokens = dictionary.segment('我是中国人，学习了。');
    expect(tokens.map((t) => t.text), ['我', '是', '中国人', '，', '学习', '了', '。']);
    expect(tokens[2].reading, 'Zhōng guó rén');
    expect(tokens[5].reading, 'le');
    expect(tokens[3].isWord, isFalse);
  });

  test('the split with fewer pieces wins', () {
    expect(dictionary.segment('研究生命起源').map((t) => t.text), ['研究', '生命', '起源']);
  });

  test('Chinese is told from Japanese', () {
    expect(ChineseDictionary.looksChinese('我是中国人'), isTrue);
    expect(ChineseDictionary.looksChinese('私は日本人です'), isFalse);
    expect(ChineseDictionary.looksChinese('hello'), isFalse);
  });
}
