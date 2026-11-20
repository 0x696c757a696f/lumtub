import 'package:flutter/material.dart';

import '../../learning/chinese_dictionary.dart';

/// A Chinese line as words, each with its pinyin above it when [pinyin]
/// is on. Tapping a word calls [onWord]; on the video, where the controls
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
  });

  final List<ChineseToken> tokens;
  final TextStyle style;
  final bool pinyin;
  final ValueChanged<ChineseToken>? onWord;
  final TextScaler? textScaler;
  final double outline;
  final WrapAlignment alignment;
  final RubyHits? hits;

  /// A word drawn marked, such as one in the vocabulary book.
  final bool Function(String word)? highlight;

  @override
  Widget build(BuildContext context) {
    hits?.clear(tokens.map((t) => t.text).join());
    final size = style.fontSize ?? 14;
    // Half the line's size, but never too small to read in a list.
    final rubyStyle = style.copyWith(fontSize: size * 0.5 < 9 ? (size < 9 ? size : 9.0) : size * 0.5, height: 1.1, fontWeight: FontWeight.normal);
    final children = <Widget>[];
    for (final token in tokens) {
      if (!token.isWord) {
        // Text between words wraps at its spaces.
        for (final piece in RegExp(r'\S+\s*|\s+').allMatches(token.text)) {
          children.add(_text(piece[0]!, style));
        }
        continue;
      }
      final marked = highlight?.call(token.text) ?? false;
      final wordStyle = marked ? style.copyWith(decoration: TextDecoration.underline, decorationColor: style.color, decorationThickness: 2) : style;
      Widget block = Column(mainAxisSize: MainAxisSize.min, children: [
        if (pinyin && token.reading != null) _text(token.reading!, rubyStyle, outlineScale: 0.6),
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
      children.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: block));
    }
    return Wrap(alignment: alignment, crossAxisAlignment: WrapCrossAlignment.end, children: children);
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
  final _words = <(GlobalKey, ChineseToken)>[];

  /// The line the words are from.
  String line = '';

  void clear(String text) {
    _words.clear();
    line = text;
  }

  void _add(GlobalKey key, ChineseToken token) => _words.add((key, token));

  /// The word at [global], with a little room around each.
  ChineseToken? wordAt(Offset global) {
    for (final (key, token) in _words) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final rect = (box.localToGlobal(Offset.zero) & box.size).inflate(2);
      if (rect.contains(global)) return token;
    }
    return null;
  }
}
