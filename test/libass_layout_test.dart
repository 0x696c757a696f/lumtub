import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/libass_layout.dart';
import 'package:lumtub/player_settings.dart';

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

  test('broken lines come out about as long as each other', () {
    final wrapped = LibassLayout.wrap('字' * 12, 10);
    expect(wrapped.split('\n').map((line) => line.runes.length).toList(), [6, 6]);
  });

  test('Thai is broken too, and lines that fit stay as they are', () {
    const thai = 'ภาษาไทยไม่มีการเว้นวรรคระหว่างคำทำให้ต้องตัดบรรทัดเองเมื่อข้อความยาวเกินไป';
    expect(LibassLayout.wrap(thai, 8).contains('\n'), isTrue);
    expect(LibassLayout.wrap(thai, 8).replaceAll('\n', ''), thai);
    expect(LibassLayout.wrap('短句', 10), '短句');
    expect(LibassLayout.wrap('one\ntwo', 10), 'one\ntwo');
  });

  group('second subtitle holding the main one', () {
    Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());
    List<String> events(String ass) => ass.split('\n').where((l) => l.startsWith('Dialogue:')).toList();
    const settings = PlayerSettings();
    final main = (cues: [(start: s(0), end: s(2), text: 'Hello there'), (start: s(2), end: s(5), text: 'General Kenobi')], font: 'Arial', room: 60.0, wrapFont: '');

    test('sits where the main subtitle does, at any size', () {
      expect(LibassLayout.secondaryPosition('Hello\nthere', position: 100, scale: 2, margin: 34, whole: true), 95.2);
      expect(LibassLayout.secondaryPosition('', position: 100, scale: 1, margin: 34, whole: true), 95.2);
      expect(LibassLayout.secondaryPosition('', position: 80, scale: 1, margin: 34, whole: true), lessThan(95.2));
    });

    test('each event holds the main lines shown with it, invisible, at their size', () {
      final ass = secondAss([(start: s(1), end: s(3), text: '你好')], settings.copyWith(subtitleScale: 1.5), outline: 0.1, main: main);
      final lines = events(ass);
      expect(lines, hasLength(2));
      expect(lines[0], startsWith('Dialogue: 0,0:00:01.00,0:00:02.00,'));
      expect(lines[0], endsWith(r'你好\N{\alpha&HFF&\fs3.75}\h\N{\alpha&HFF&}{\fnArial\fs33.51\b0}Hello there'));
      expect(lines[1], startsWith('Dialogue: 0,0:00:02.00,0:00:03.00,'));
      expect(lines[1], endsWith('General Kenobi'));
    });

    test('no event overlaps another, and stretches without main lines show the second alone', () {
      final ass = secondAss([(start: s(4), end: s(7), text: 'a'), (start: s(4.5), end: s(6), text: 'b')], settings, outline: 0, main: main);
      final lines = events(ass);
      expect(lines.map((l) => l.split(',').sublist(1, 3).join('-')), ['0:00:04.00-0:00:04.50', '0:00:04.50-0:00:05.00', '0:00:05.00-0:00:06.00', '0:00:06.00-0:00:07.00']);
      expect(lines[1], contains(r',b\Na\N'));
      expect(lines[2], endsWith(r',b\Na'));
      expect(lines[3], endsWith(',a'));
    });

    test('without main lines it is as before', () {
      final ass = secondAss([(start: s(1), end: s(3), text: 'x')], settings, outline: 0, main: (cues: const [], font: 'Arial', room: 60.0, wrapFont: ''));
      expect(events(ass), ['Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,x']);
    });

    test('is as wide as the picture, so lines wrap where the main one does', () {
      expect(secondAss(const [], settings, outline: 0, aspect: 9 / 16), contains('PlayResX: 405'));
      expect(secondAss(const [], settings, outline: 0), contains('PlayResX: 1280'));
    });

    test('blank lines in the main subtitle are left out, as in its copy', () {
      final ass = secondAss([(start: s(0), end: s(1), text: 'x')], settings, outline: 0, main: (cues: [(start: s(0), end: s(1), text: 'a\n\nb')], font: 'Arial', room: 60.0, wrapFont: ''));
      expect(events(ass).single, endsWith(r'a\Nb'));
    });

    test('thousands of overlapping cues take one pass', () {
      final many = [for (var i = 0; i < 6000; i++) (start: s(i * 1.0), end: s(i + 2.5), text: 'line $i')];
      final watch = Stopwatch()..start();
      final ass = secondAss(many, settings, outline: 0, main: (cues: many, font: 'Arial', room: 60.0, wrapFont: ''));
      expect(watch.elapsedMilliseconds, lessThan(3000));
      final lines = events(ass);
      expect(lines.length, greaterThan(6000));
      // From 10.5 s to 11 s lines 9 and 10 show: the later one on top.
      expect(lines.firstWhere((l) => l.contains('0:00:10.50,0:00:11.00')), contains(r',line 10\Nline 9\N'));
    });
  });
}
