import 'package:flutter/material.dart';

/// [text] with each custom emoji shortcut in [emojis] (such as
/// `:face-blue-smiling:`) drawn as its picture, the size of the text.
List<InlineSpan> emojiSpans(BuildContext context, String text, Map<String, String> emojis, {TextStyle? style}) {
  if (emojis.isEmpty || !text.contains(':')) return [TextSpan(text: text, style: style)];
  final size = (style?.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 14) * 1.4;
  final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
  final pattern = RegExp([for (final name in emojis.keys) RegExp.escape(name)].join('|'));
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
