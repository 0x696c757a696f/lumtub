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
}
