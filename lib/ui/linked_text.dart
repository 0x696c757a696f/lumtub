import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../skins/skin.dart' show contrastRatio;
import 'theme.dart' show SkinTheme;
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
    final link = linkStyle(Theme.of(context));
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

/// The accent as links show it while it reads nearly as well as text,
/// else the text colour (with [linkStyle]'s underline in the accent): a
/// dark accent on a dark page, or on a skin's picture seen through the
/// veil, made links look thin and faint beside the words around them.
/// Every built-in skin is checked for it in skin_theme_contrast_test.
Color linkColor(ThemeData theme) {
  final colors = theme.colorScheme;
  // Over a skin's picture the page behind changes from place to place.
  final skin = theme.extension<SkinTheme>()?.skin?.forBrightness(theme.brightness);
  if (skin != null && skin.veil > 0) return colors.onSurface;
  final text = contrastRatio(colors.onSurface, colors.surface);
  final wanted = min(text * 0.9, 6.0);
  final worst = [colors.surface, colors.surfaceContainerLow].map((bg) => contrastRatio(colors.primary, bg)).reduce((a, b) => a < b ? a : b);
  return worst >= wanted ? colors.primary : colors.onSurface;
}

/// How links and times show in text: in [linkColor], underlined in the
/// accent where they take the text colour.
TextStyle linkStyle(ThemeData theme) {
  final colors = theme.colorScheme;
  final color = linkColor(theme);
  return color == colors.primary ? TextStyle(color: color) : TextStyle(color: color, decoration: TextDecoration.underline, decorationColor: colors.primary, decorationThickness: 1.5);
}
