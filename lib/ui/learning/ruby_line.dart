import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    hits?.clear(tokens.map((t) => t.text).join());
    final size = style.fontSize ?? 14;
    // Half the line's size, but never too small to read in a list.
    final rubyStyle = style.copyWith(fontSize: size * 0.5 < 9 ? (size < 9 ? size : 9.0) : size * 0.5, height: 1.1, fontWeight: FontWeight.normal);
    final children = <Widget>[];
    bool ruby(int i) => i >= 0 && i < tokens.length && tokens[i].isWord && pinyin && tokens[i].reading != null;
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
        if (pinyin && token.reading != null)
          japanese ? _furigana(token.text, wordStyle, token.reading!, rubyStyle, left: !ruby(i - 1), right: !ruby(i + 1)) : _text(token.reading!, rubyStyle, outlineScale: 0.6),
        _text(token.text, wordStyle),
      ]);
      if (hits != null) {
        final key = GlobalKey();
        hits!._add(key, token);
        block = KeyedSubtree(key: key, child: block);
      }
      if (onWord != null) {
        block = MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => onWord!(token), child: block),
        );
      }
      // The outline reaches past the letters; the room keeps the space between words.
      children.add(Padding(padding: EdgeInsets.symmetric(horizontal: (japanese ? 0 : 1) + outline / 2), child: block));
    }
    return Wrap(alignment: alignment, crossAxisAlignment: WrapCrossAlignment.end, children: children);
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
/// pointer that something above it took.
class RubyHits {
  final _words = <(GlobalKey, WordToken)>[];

  /// The line the words are from.
  String line = '';

  void clear(String text) {
    _words.clear();
    line = text;
  }

  void _add(GlobalKey key, WordToken token) => _words.add((key, token));

  /// The word at [global], with a little room around each.
  WordToken? wordAt(Offset global) {
    for (final (key, token) in _words) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final rect = (box.localToGlobal(Offset.zero) & box.size).inflate(2);
      if (rect.contains(global)) return token;
    }
    return null;
  }
}
