import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/word_levels.dart';

void main() {
  test('levels are read by spelling, then lower-cased, and bad lines are skipped', () {
    final levels = WordLevels.parse('学习\t1\n環境\t3\nser\t1\nbad line\nx\t0\ny\t12\n\t2\ncomer\t2\n');
    expect(levels.length, 4);
    expect(levels.of('学习'), 1);
    expect(levels.of('Ser'), 1);
    expect(levels.of('comer'), 2);
    expect(levels.of('x'), isNull);
    expect(levels.of('y'), isNull);
    expect(levels.of('unknown'), isNull);
  });

  test('a Chinese word no list has takes the level of its hardest part', () {
    final levels = WordLevels.parse('这\t1\n个\t1\n经济\t3\n发展\t3\n可\t2\n持续\t5\n');
    expect(levels.ofParts('这个'), 1);
    expect(levels.ofParts('经济发展'), 3);
    expect(levels.ofParts('可持续'), 5);
    expect(levels.ofParts('猫咪'), isNull);
  });

  test('each language has its scale', () {
    expect(LevelScale.of('zh'), LevelScale.hsk);
    expect(LevelScale.of('ja')!.nameOf(1), 'N5');
    expect(LevelScale.of('es')!.nameOf(6), '≈ C2');
    expect(LevelScale.of('en'), isNull);
  });
}
