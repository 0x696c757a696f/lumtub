import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/libass_layout.dart';

void main() {
  test('one main line: the second subtitle sits a line and a small gap above', () {
    expect(LibassLayout.secondaryPosition('Hello there', position: 100, scale: 1), 93.4);
    expect(LibassLayout.secondaryPosition('', position: 100, scale: 1), 93.4);
  });

  test('two main lines leave no empty line between the subtitles', () {
    // Measured on the Windows libmpv: lines 43 px apart in an 808 px picture,
    // the main subtitle's bottom at 770 px with sub-margin-y 34. Position
    // 87.8 puts the second subtitle's bottom at 676 px, 8 px above the top
    // of the main one's first line (770 - 2 * 43 = 684).
    const italian = 'è visibile già alla periferia di Hanoi,\nin particolare a Ninh Hiệp, uno dei più';
    final position = LibassLayout.secondaryPosition(italian, position: 100, scale: 1);
    expect(position, 87.8);
    final bottom = 770 * position / 100;
    expect(684 - bottom, inInclusiveRange(4, 12));
  });

  test('zero-width marks take no line', () {
    expect(LibassLayout.lineCount('Ciao\n\u200B\nA tutti\u200E', scale: 1), 2);
  });

  test('two main lines move the second subtitle up a line', () {
    final one = LibassLayout.secondaryPosition('I think it was', position: 100, scale: 1);
    final two = LibassLayout.secondaryPosition('I think it was\nthe first time we met', position: 100, scale: 1);
    expect(two, lessThanOrEqualTo(one - 5));
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

  test('text without spaces is broken where it would run past the edges', () {
    final wrapped = LibassLayout.wrap('字' * 25, 10);
    expect(wrapped.split('\n').length, greaterThanOrEqualTo(3));
    expect(wrapped.replaceAll('\n', ''), '字' * 25);
    for (final line in wrapped.split('\n')) {
      expect(line.runes.length, lessThanOrEqualTo(10));
    }
  });

  test('Thai is broken too, and lines that fit stay as they are', () {
    const thai = 'ภาษาไทยไม่มีการเว้นวรรคระหว่างคำทำให้ต้องตัดบรรทัดเองเมื่อข้อความยาวเกินไป';
    expect(LibassLayout.wrap(thai, 8).contains('\n'), isTrue);
    expect(LibassLayout.wrap(thai, 8).replaceAll('\n', ''), thai);
    expect(LibassLayout.wrap('短句', 10), '短句');
    expect(LibassLayout.wrap('one\ntwo', 10), 'one\ntwo');
  });
}
