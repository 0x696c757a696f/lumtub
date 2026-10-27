import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'emoji_text.dart';

/// A piece of text: plain, a time such as 1:23:45, or a web link.
sealed class TextPart {
  const TextPart(this.text);
  final String text;
}

class PlainPart extends TextPart {
  const PlainPart(super.text);
}

class TimePart extends TextPart {
  const TimePart(super.text, this.time);
  final Duration time;
}

class LinkPart extends TextPart {
  const LinkPart(super.text);
}

final _pattern = RegExp(r'https?://[^\s<>"）)】」，。]+|(?<![\d:.])(?:(\d{1,2}):)?(\d{1,2}):(\d{2})(?![\d:])');

/// Splits [text] into plain text, times and links, as PiliNara does for
/// descriptions and comments.
List<TextPart> splitLinks(String text) {
  final parts = <TextPart>[];
  var last = 0;
  for (final match in _pattern.allMatches(text)) {
    final value = match[0]!;
    TextPart? part;
    if (value.startsWith('http')) {
      part = LinkPart(value);
    } else {
      final hours = int.parse(match[1] ?? '0');
      final minutes = int.parse(match[2]!);
      final seconds = int.parse(match[3]!);
      // 1:75 is not a time; with hours, minutes must be below 60 too.
      if (seconds < 60 && (match[1] == null || minutes < 60)) part = TimePart(value, Duration(hours: hours, minutes: minutes, seconds: seconds));
    }
    if (part == null) continue;
    if (match.start > last) parts.add(PlainPart(text.substring(last, match.start)));
    parts.add(part);
    last = match.end;
  }
  if (last < text.length) parts.add(PlainPart(text.substring(last)));
  return parts;
}

/// [text] with its times and links tappable.
class LinkedText extends StatefulWidget {
  const LinkedText(this.text, {super.key, this.style, this.maxLines, required this.onTime, required this.onLink, this.emojis = const {}});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final ValueChanged<Duration> onTime;
  final ValueChanged<String> onLink;
  /// Custom emoji shortcuts in [text] and their pictures.
  final Map<String, String> emojis;

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final link = TextStyle(color: Theme.of(context).colorScheme.primary);
    return Text.rich(
      TextSpan(children: [
        for (final part in splitLinks(widget.text))
          switch (part) {
            TimePart(:final time) => TextSpan(text: part.text, style: link, recognizer: _tap(() => widget.onTime(time)), mouseCursor: SystemMouseCursors.click),
            LinkPart() => TextSpan(text: part.text, style: link, recognizer: _tap(() => widget.onLink(part.text)), mouseCursor: SystemMouseCursors.click),
            PlainPart() => TextSpan(children: emojiSpans(context, part.text, widget.emojis, style: widget.style)),
          },
      ]),
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
