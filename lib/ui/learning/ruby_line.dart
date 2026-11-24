import 'package:material_ui/material_ui.dart';

import '../../learning/word_token.dart';

/// A line as words, each with its reading (pinyin) above it when
/// [pinyin] is on. Tapping a word calls [onWord]; on the video, where the controls
/// lie above the line, [hits] keeps where each word is instead.
class ChineseRubyLine extends StatelessWidget {
  const ChineseRubyLine({
    super.key,
    required this.tokens,
    required this.style,
    this.pinyin = true,
    this.onWord,
    this.textScaler,
    this.outline = 0,
    this.alignment = WrapAlignment.start,
    this.hits,
    this.highlight,
    this.hard,
    this.hardColor = const Color(0xFFFFC23D),
    this.known,
  });

  final List<WordToken> tokens;
  final TextStyle style;
  final bool pinyin;
  final ValueChanged<WordToken>? onWord;
  final TextScaler? textScaler;
  final double outline;
  final WrapAlignment alignment;
  final RubyHits? hits;

  /// A word drawn marked, such as one in the vocabulary book.
  final bool Function(WordToken token)? highlight;

  /// Words above the learner's level, drawn in [hardColor].
  final bool Function(WordToken token)? hard;
  final Color hardColor;

  /// Words the learner knows: no reading above them.
  final bool Function(WordToken token)? known;

  @override
  Widget build(BuildContext context) {
    hits?.clear(tokens);
    // A subtitle background goes once behind the whole line, not behind
    // each word as a box of its own.
    final back = this.style.backgroundColor ?? this.style.background?.color;
    final clear = Paint()..color = const Color(0x00000000);
    final style = back == null ? this.style : (this.style.background != null ? this.style.copyWith(background: clear) : this.style.copyWith(backgroundColor: const Color(0x00000000)));
    final size = style.fontSize ?? 14;
    // Half the line's size, but never too small to read in a list.
    final rubyStyle = style.copyWith(fontSize: size * 0.5 < 9 ? (size < 9 ? size : 9.0) : size * 0.5, height: 1.1, fontWeight: FontWeight.normal);
    final children = <Widget>[];
    bool ruby(int i) => i >= 0 && i < tokens.length && tokens[i].isWord && pinyin && tokens[i].reading != null && !(known?.call(tokens[i]) ?? false);
    for (final (i, token) in tokens.indexed) {
      if (!token.isWord) {
        // Text between words wraps at its spaces.
        // A caption's line break is a space here: the words stand in one row.
        for (final piece in RegExp(r'\S+\s*|\s+').allMatches(token.text.replaceAll(RegExp(r'\s*\n\s*'), ' '))) {
          children.add(_text(piece[0]!, style));
        }
        continue;
      }
      final marked = highlight?.call(token) ?? false;
      var wordStyle = (hard?.call(token) ?? false) ? style.copyWith(color: hardColor.withValues(alpha: style.color?.a ?? 1)) : style;
      if (marked) wordStyle = wordStyle.copyWith(decoration: TextDecoration.underline, decorationColor: wordStyle.color, decorationThickness: 2);
      // Japanese is written without spaces: its words stand close, and a
      // reading longer than its word (しょうぎょう over 商業) reaches over a
      // neighbour that has none, else is set smaller, as furigana is.
      final japanese = token.language == 'ja';
      Widget block = Column(mainAxisSize: MainAxisSize.min, children: [
        if (ruby(i))
          japanese ? _furigana(token.text, wordStyle, token.reading!, rubyStyle, left: !ruby(i - 1), right: !ruby(i + 1)) : _text(token.reading!, rubyStyle, outlineScale: 0.6),
        _text(token.text, wordStyle),
      ]);
      if (hits?.chosen(i) ?? false) {
        block = DecoratedBox(decoration: BoxDecoration(color: const Color(0x993B82F6), borderRadius: BorderRadius.circular(size * 0.12)), child: block);
      }
      if (hits != null) {
        final key = GlobalKey();
        hits!._add(key, i);
        block = KeyedSubtree(key: key, child: block);
      }
      if (onWord != null) {
        block = MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => onWord!(token), child: block),
        );
      }
      // The outline reaches past the letters; the room keeps the space between words.
      // Room for the outline, but not beside a space, which already
      // keeps words apart (with it, words on the video stood far apart).
      final room = (japanese ? 0 : 1) + outline / 2;
      bool spaced(int j) => j >= 0 && j < tokens.length && !tokens[j].isWord && RegExp(j < i ? r'\s$' : r'^\s').hasMatch(tokens[j].text);
      children.add(Padding(padding: EdgeInsetsDirectional.only(start: spaced(i - 1) ? 0 : room, end: spaced(i + 1) ? 0 : room), child: block));
    }
    final line = Wrap(alignment: alignment, crossAxisAlignment: WrapCrossAlignment.end, children: children);
    if (back == null || back.a == 0) return line;
    return DecoratedBox(
      decoration: BoxDecoration(color: back, borderRadius: BorderRadius.circular(size * 0.12)),
      child: Padding(padding: EdgeInsets.symmetric(horizontal: size * 0.25, vertical: size * 0.05), child: line),
    );
  }

  /// [reading] over [word], as wide as the word and, on a side with no
  /// reading next to it, up to half a letter more; shrunk when longer.
  Widget _furigana(String word, TextStyle wordStyle, String reading, TextStyle style, {required bool left, required bool right}) {
    final scaler = textScaler ?? TextScaler.noScaling;
    (double, double) measure(String text, TextStyle s) {
      final painter = TextPainter(text: TextSpan(text: text, style: s), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
      final size = (painter.width, painter.height);
      painter.dispose();
      return size;
    }

    final (width, _) = measure(word, wordStyle);
    final (needed, height) = measure(reading, style);
    // Centred over the word when it fits; past it only when it must be.
    final reach = needed <= width ? 0.0 : (wordStyle.fontSize ?? 14) * scaler.scale(1) * 0.5;
    final before = left ? reach : 0.0;
    final after = right ? reach : 0.0;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: -before,
          width: width + before + after,
          top: 0,
          height: height,
          child: FittedBox(fit: BoxFit.scaleDown, child: _text(reading, style, outlineScale: 0.6)),
        ),
      ]),
    );
  }

  Widget _text(String text, TextStyle style, {double outlineScale = 1}) {
    final letters = Text(text, style: style, textScaler: textScaler, softWrap: false);
    if (outline <= 0) return letters;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = outline * 2 * outlineScale
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF000000).withValues(alpha: style.color?.a ?? 1);
    return Stack(children: [
      Text(text, style: style.copyWith(foreground: stroke, shadows: const [], decoration: TextDecoration.none), textScaler: textScaler, softWrap: false),
      letters,
    ]);
  }
}

/// Where each word of a [ChineseRubyLine] is, to find the one under a
/// pointer that something above it took, and the words a press drawn
/// across the line has chosen.
class RubyHits {
  final _words = <(GlobalKey, int)>[];
  var _tokens = const <WordToken>[];

  /// The line the words are from.
  String line = '';

  /// The words chosen, first and last index into the line's tokens, while
  /// a press is drawn across them.
  final selection = ValueNotifier<(int, int)?>(null);
  int? _anchor;

  void clear(List<WordToken> tokens) {
    _words.clear();
    _tokens = tokens;
    line = tokens.map((t) => t.text).join();
  }

  void _add(GlobalKey key, int index) => _words.add((key, index));

  int? _indexAt(Offset global) {
    for (final (key, index) in _words) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final rect = (box.localToGlobal(Offset.zero) & box.size).inflate(2);
      if (rect.contains(global)) return index;
    }
    return null;
  }

  /// The word at [global], with a little room around each.
  WordToken? wordAt(Offset global) {
    final index = _indexAt(global);
    return index == null ? null : _tokens[index];
  }

  /// Whether the token at [index] is among those chosen.
  bool chosen(int index) {
    final range = selection.value;
    return range != null && index >= range.$1 && index <= range.$2;
  }

  /// Follows a press drawn across the line: [from] is where it began,
  /// [to] where the finger is. Lifted, it answers the words chosen as one
  /// token to look up (a single word as it is), and the choice clears.
  WordToken? select(Offset from, Offset to, {required bool done}) {
    if (!done) {
      _anchor ??= _indexAt(from);
      final end = _indexAt(to);
      final anchor = _anchor;
      if (anchor != null && end != null) selection.value = anchor <= end ? (anchor, end) : (end, anchor);
      return null;
    }
    final range = selection.value;
    _anchor = null;
    selection.value = null;
    // The line may have moved on under the finger.
    return range == null || range.$2 >= _tokens.length ? null : phrase(range.$1, range.$2);
  }

  /// Tokens [first] to [last] of the line as one, with what stands between
  /// them, such as spaces, kept; one word comes back as it is.
  WordToken phrase(int first, int last) {
    if (first == last) return _tokens[first];
    final parts = _tokens.sublist(first, last + 1);
    final text = parts.map((t) => t.text).join().replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = parts.any((t) => t.lookup != null);
    return WordToken(text, null, isWord: true, lookup: lower ? text.toLowerCase() : null, language: parts.first.language);
  }
}
