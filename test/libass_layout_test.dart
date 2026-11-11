import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/libass_layout.dart';

void main() {
  test('one main line keeps the old place', () {
    expect(LibassLayout.secondaryPosition('Hello there', position: 100, scale: 1), 92);
    expect(LibassLayout.secondaryPosition('', position: 100, scale: 1), 92);
  });

  test('two main lines move the second subtitle up a line', () {
    final one = LibassLayout.secondaryPosition('I think it was', position: 100, scale: 1);
    final two = LibassLayout.secondaryPosition('I think it was\nthe first time we met', position: 100, scale: 1);
    expect(two, lessThanOrEqualTo(one - 6));
  });

  test('long lines count as wrapped', () {
    final long = List.filled(30, 'subtitle').join(' ');
    expect(LibassLayout.lineCount(long, scale: 1), greaterThanOrEqualTo(2));
    expect(LibassLayout.lineCount('字' * 40, scale: 1), 2);
    expect(LibassLayout.lineCount('字' * 20, scale: 1), 1);
  });

  test('bigger text moves it further', () {
    expect(LibassLayout.secondaryPosition('a\nb', position: 100, scale: 1.5), lessThan(LibassLayout.secondaryPosition('a\nb', position: 100, scale: 1)));
  });

  test('stays on screen', () {
    expect(LibassLayout.secondaryPosition('a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\nm\nn\no\np', position: 50, scale: 2), 0);
  });

  test('a line of ordinary Latin text that fits is counted as one', () {
    expect(LibassLayout.lineCount('Was kam danach?\nJa, die Leute müssen verstehen, was es', scale: 1.5), 2);
    expect(LibassLayout.lineCount('gute Erkennisse mit Manuel [musik]\nOstermann ungeskriptet.', scale: 1.5), 2);
    expect(LibassLayout.lineCount('mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm', scale: 1), 2);
  });
}
