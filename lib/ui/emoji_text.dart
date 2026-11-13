import 'package:flutter/material.dart';

import '../emoji_pictures.dart';

/// [text] with each emoji in [emojis] (a shortcut such as
/// `:face-blue-smiling:`, or a Unicode emoji YouTube sent a picture of)
/// drawn as its picture, the size of the text. YouTube's own emoji that
/// came without a picture take one seen before; see [EmojiPictures].
List<InlineSpan> emojiSpans(BuildContext context, String text, Map<String, String> given, {TextStyle? style}) {
  final emojis = EmojiPictures.fill(text, given);
  if (emojis.isEmpty) return [TextSpan(text: text, style: style)];
  final size = (style?.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 14) * 1.4;
  final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
  final pattern = emojiPattern(emojis.keys);
  final spans = <InlineSpan>[];
  var start = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > start) spans.add(TextSpan(text: text.substring(start, match.start), style: style));
    final name = match[0]!;
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Tooltip(
        message: name,
        child: Image(
          image: ResizeImage(NetworkImage(emojis[name]!), width: pixels, height: pixels),
          width: size,
          height: size,
          semanticLabel: name,
          errorBuilder: (context, _, __) => Text(name, style: style),
        ),
      ),
    ));
    start = match.end;
  }
  if (start < text.length) spans.add(TextSpan(text: text.substring(start), style: style));
  return spans;
}

/// The names in [names] as one pattern, longest first, so that an emoji
/// with a skin tone is found whole rather than as its plain emoji.
RegExp emojiPattern(Iterable<String> names) {
  final sorted = [for (final name in names) if (name.isNotEmpty) name]..sort((a, b) => b.length.compareTo(a.length));
  return RegExp(sorted.map(RegExp.escape).join('|'));
}
