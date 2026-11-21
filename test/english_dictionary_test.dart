import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/english_dictionary.dart';

const _sample = 'run\trʌn\tn. 跑\\nvi. 跑, 奔跑\tp:ran/i:running/d:run/0:run/1:d/3:runs/s:runs\n'
    'look\tluk\tv. 看\tp:looked/d:looked/i:looking/3:looks\n'
    'Paris\t\tn. 巴黎\t\n'
    "don't\t\tabbr. 不要\t\n"
    'cat\tkæt\tn. 猫\ts:cats\n';

void main() {
  final d = EnglishDictionary.parse(_sample);

  test('a form finds its word', () {
    expect(d.lookup('ran').single.word, 'run');
    expect(d.lookup('Running').single.word, 'run');
    expect(d.lookup('cats').single.meanings, ['n. 猫']);
    expect(d.lookup('run').single.meanings, ['n. 跑', 'vi. 跑, 奔跑']);
    expect(d.lookup('PARIS').single.word, 'Paris');
    expect(d.lookup('cat\'s').single.word, 'cat');
    expect(d.lookup('zzz'), isEmpty);
  });

  test('a line splits into words, keeping contractions', () {
    final tokens = d.segment('Don’t run, cats!');
    expect(tokens.where((t) => t.isWord).map((t) => t.key), ["Don't", 'run', 'cats']);
    expect(tokens.map((t) => t.text).join(), 'Don’t run, cats!');
    expect(d.lookup(tokens.first.key).single.word, "don't");
  });

  test('Latin text is told from Chinese', () {
    expect(EnglishDictionary.looksLatin('Hello there'), isTrue);
    expect(EnglishDictionary.looksLatin('你好 OK'), isFalse);
    expect(EnglishDictionary.looksLatin('123'), isFalse);
  });

  test('forms are named', () {
    expect(d.lookup('run').single.namedForms.first, ('Past', 'ran'));
  });

  test('words have levels from exam lists, then from how common they are', () {
    final levels = EnglishDictionary.parse('add\tæd\tv. 加\tp:added/d:added/i:adding/3:adds\tzk gk cet4 ky\t5\t330\n'
        'ubiquitous\tju:\ta. 无所不在的\t\tgre\t1\t8148\n'
        'abruptly\t\tad. 突然地\t\t\t0\t7000\n'
        'aaron\t\tn. 亚伦\t\t\t0\t15000\n'
        'zymurgy\t\tn. 酿造学\t\t\t0\t40000\n');
    expect(levels.lookup('add').single.tags, [EnglishLevel.middleSchool, EnglishLevel.highSchool, EnglishLevel.cet4, EnglishLevel.postgraduate]);
    expect(levels.lookup('add').single.collins, 5);
    expect(levels.levelOf('added'), EnglishLevel.middleSchool.index);
    expect(levels.levelOf('ubiquitous'), EnglishLevel.gre.index);
    expect(levels.levelOf('abruptly'), EnglishLevel.postgraduate.index);
    expect(levels.levelOf('zymurgy'), EnglishLevel.beyond.index);
    expect(levels.levelOf('aaron'), EnglishLevel.gre.index);
    expect(levels.levelOf('Aaron'), isNull);
    expect(levels.levelOf('Ubiquitous'), EnglishLevel.gre.index);
    expect(levels.levelOf('Zymurgy'), isNull);
    expect(levels.levelOf('nothing'), isNull);
    // Packs without the level columns still read, with no levels.
    expect(d.levelOf('run'), isNull);
    expect(d.lookup('ran').single.forms, contains('p:ran'));
  });

  test('English meanings come from the eighth column', () {
    final d = EnglishDictionary.parse('run\trʌn\tv. 跑\tp:ran\t\t5\t100\tv. To move swiftly on foot.\\nn. An act of running.\n'
        'walk\twɔ:k\tv. 走\t\t\t5\t200\n');
    expect(d.lookup('run').single.english, ['v. To move swiftly on foot.', 'n. An act of running.']);
    expect(d.lookup('run').single.meanings, ['v. 跑']);
    expect(d.lookup('walk').single.english, isEmpty);
  });

  test('a short form or a compound is as hard as its full form or parts', () {
    final d = EnglishDictionary.parse('vocabulary\t\tn. 词汇\t\tgk cet4\t1\t4802\n'
        'vocab\t\tn. 词汇\t\t\t0\t37221\n'
        'skin\t\tn. 皮肤\t\tgk cet4\t4\t1019\n'
        'care\t\tn. 照料\t\tzk gk\t5\t434\n'
        'skincare\t\tn. 护肤\t\t\t0\t47645\n'
        'zymurgy\t\tn. 酿造学\t\t\t0\t40000\n');
    expect(d.levelOf('vocab'), EnglishLevel.highSchool.index);
    expect(d.levelOf('skincare'), EnglishLevel.highSchool.index);
    expect(d.levelOf('zymurgy'), EnglishLevel.beyond.index);
  });

  test('with CEFR preferred, a listed level comes from CEFR-J', () {
    final d = EnglishDictionary.parse('clause\t\tn. 条款\t\tky toefl ielts gre\t2\t1871\t\tB2\n'
        'regimen\t\tn. 养生法\t\ttoefl\t0\t7909\t\t\n');
    addTearDown(() => EnglishEntry.preferCefr = false);
    expect(d.lookup('clause').single.cefr, 'B2');
    expect(d.levelOf('clause'), EnglishLevel.postgraduate.index);
    EnglishEntry.preferCefr = true;
    final again = EnglishDictionary.parse('clause\t\tn. 条款\t\tky toefl ielts gre\t2\t1871\t\tB2\n'
        'regimen\t\tn. 养生法\t\ttoefl\t0\t7909\t\t\n');
    expect(again.levelOf('clause'), EnglishLevel.cet6.index);
    expect(again.levelOf('regimen'), EnglishLevel.toeflIelts.index);
  });

  test('WikDict meanings are marked as a reference; a word without Chinese keeps its English', () {
    final d = EnglishDictionary.parse('bank\tbaŋk\tn. 银行；岸\t\tcet4\t0\t900\tn. An institution\t\tw\n'
        'zymurgy\t\tn. 酿造学\t\t\t0\t40000\t\t\td\n'
        'quark\t\t\t\t\t0\t30000\tn. A particle\t\t\n');
    expect(d.lookup('bank').single.chineseReference, isFalse);
    expect(d.lookup('zymurgy').single.chineseReference, isTrue);
    final quark = d.lookup('quark').single;
    expect(quark.meanings, isEmpty);
    expect(quark.english, ['n. A particle']);
  });
}
