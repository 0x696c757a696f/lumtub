import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';

import 'emoji_text.dart';

/// A piece of a 弹幕 message: text, a YouTube emoji picture, or a Unicode
/// emoji drawn in colour.
sealed class DanmakuPart {
  const DanmakuPart();
}

class DanmakuText extends DanmakuPart {
  const DanmakuText(this.text);
  final String text;
}

class DanmakuEmojiPicture extends DanmakuPart {
  const DanmakuEmojiPicture(this.url);
  final String url;
}

class DanmakuEmojiGlyph extends DanmakuPart {
  const DanmakuEmojiGlyph(this.emoji);
  final String emoji;
}

bool _isEmoji(String cluster) {
  for (final rune in cluster.runes) {
    if (rune >= 0x1F000 || (rune >= 0x2600 && rune <= 0x27BF) || rune == 0xFE0F) return true;
  }
  return false;
}

/// [text] split into parts, the emoji in [emojis] (shortcuts, and Unicode
/// emoji YouTube sent pictures of) becoming their pictures; null when it
/// has no emoji and libass can draw it.
List<DanmakuPart>? danmakuParts(String text, Map<String, String> emojis) {
  final parts = <DanmakuPart>[];
  var plain = StringBuffer();
  var any = false;
  void flush() {
    if (plain.isNotEmpty) parts.add(DanmakuText('$plain'));
    plain = StringBuffer();
  }

  void addText(String piece) {
    for (final cluster in piece.characters) {
      if (_isEmoji(cluster)) {
        flush();
        parts.add(DanmakuEmojiGlyph(cluster));
        any = true;
      } else {
        plain.write(cluster == '\n' || cluster == '\r' ? ' ' : cluster);
      }
    }
  }

  var at = 0;
  if (emojis.keys.any((name) => name.isNotEmpty)) {
    for (final match in emojiPattern(emojis.keys).allMatches(text)) {
      addText(text.substring(at, match.start));
      flush();
      parts.add(DanmakuEmojiPicture(emojis[match[0]]!));
      any = true;
      at = match.end;
    }
  }
  addText(text.substring(at));
  flush();
  return any ? parts : null;
}

/// A message drawn as premultiplied BGRA in native memory, for mpv's
/// `overlay-add`. [left] is how far the text starts in from the edge.
class DanmakuBitmap {
  DanmakuBitmap._(this.pixels, this.width, this.height, this.left, this.scale);
  final Pointer<Uint8> pixels;
  final int width;
  final int height;
  final double left;
  /// The OSD height it was drawn for.
  final double scale;
  bool _freed = false;

  int get stride => width * 4;

  void free() {
    if (_freed) return;
    _freed = true;
    calloc.free(pixels);
  }
}

/// Draws 弹幕 messages the way the ASS ones look: bold, with a thin dark
/// outline, at [size] for a 1080-line picture.
class DanmakuPainter {
  DanmakuPainter({required this.font, required this.size, required this.opacity});

  final String font;
  final double size;
  final double opacity;

  static final _pictures = <String, Future<ui.Image?>>{};
  static const _emojiFonts = ['Segoe UI Emoji', 'Apple Color Emoji', 'Noto Color Emoji'];

  double _border(double scale) => (size / 30).clamp(1, double.infinity) * scale;

  TextPainter _painter(List<DanmakuPart> parts, double scale, {Paint? stroke, Color? colour}) {
    final px = size * scale;
    final style = TextStyle(fontFamily: font, fontWeight: FontWeight.bold, fontSize: px, height: 1.2, foreground: stroke, color: stroke == null ? colour : null);
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      text: TextSpan(style: style, children: [
        for (final part in parts)
          switch (part) {
            DanmakuText(:final text) => TextSpan(text: text),
            _ => const WidgetSpan(alignment: PlaceholderAlignment.middle, child: SizedBox.shrink()),
          },
      ]),
    );
    final emoji = px * 1.15;
    painter.setPlaceholderDimensions([
      for (final part in parts)
        if (part is! DanmakuText) PlaceholderDimensions(size: Size(emoji, emoji), alignment: PlaceholderAlignment.middle),
    ]);
    painter.layout();
    return painter;
  }

  /// How wide [parts] are at [HEIGHT] 1080, in units of a 1920-wide
  /// picture shown [osdWidth] × [osdHeight].
  double measure(List<DanmakuPart> parts, double osdWidth, double osdHeight) {
    final scale = osdHeight / 1080;
    final painter = _painter(parts, scale);
    final width = painter.width;
    painter.dispose();
    return width / (osdWidth / 1920);
  }

  static Future<ui.Image?> _picture(String url) => _pictures.putIfAbsent(url, () {
        final done = Completer<ui.Image?>();
        final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
        late final ImageStreamListener listener;
        listener = ImageStreamListener((info, _) {
          if (!done.isCompleted) done.complete(info.image.clone());
          stream.removeListener(listener);
        }, onError: (error, stack) {
          if (!done.isCompleted) done.complete(null);
          stream.removeListener(listener);
          _pictures.remove(url);
        });
        stream.addListener(listener);
        return done.future.timeout(const Duration(seconds: 10), onTimeout: () {
          _pictures.remove(url);
          return null;
        });
      });

  /// [parts] drawn for an OSD [osdHeight] pixels high, gold when [paid];
  /// null when nothing could be drawn.
  Future<DanmakuBitmap?> draw(List<DanmakuPart> parts, {required double osdHeight, required bool paid}) async {
    final scale = osdHeight / 1080;
    final images = <String, ui.Image?>{
      for (final part in parts)
        if (part case DanmakuEmojiPicture(:final url)) url: await _picture(url),
    };
    final border = _border(scale);
    final edge = Color.fromARGB((opacity * 0.6 * 255).round(), 0, 0, 0);
    final fillColour = (paid ? const Color(0xFFFFC838) : const Color(0xFFFFFFFF)).withValues(alpha: opacity);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = border * 2
      ..strokeJoin = StrokeJoin.round
      ..color = edge;
    final outline = _painter(parts, scale, stroke: stroke);
    final fill = _painter(parts, scale, colour: fillColour);
    final pad = (border * 2).ceilToDouble();
    final width = (fill.width + pad * 2).ceil();
    final height = (size * 1.25 * scale).ceil();
    if (width <= 0 || height <= 0) {
      outline.dispose();
      fill.dispose();
      return null;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final offset = Offset(pad, (height - fill.height) / 2);
    outline.paint(canvas, offset);
    fill.paint(canvas, offset);
    final boxes = fill.inlinePlaceholderBoxes ?? const [];
    final emojiParts = parts.where((p) => p is! DanmakuText).toList();
    final imagePaint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, opacity);
    for (var i = 0; i < boxes.length && i < emojiParts.length; i++) {
      final box = boxes[i].toRect().shift(offset);
      switch (emojiParts[i]) {
        case DanmakuEmojiPicture(:final url):
          final image = images[url];
          if (image != null) {
            canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), box, imagePaint);
          }
        case DanmakuEmojiGlyph(:final emoji):
          final glyph = TextPainter(
            textDirection: TextDirection.ltr,
            text: TextSpan(text: emoji, style: TextStyle(fontSize: box.height * 0.85, height: 1, fontFamilyFallback: _emojiFonts, color: Color.fromRGBO(0, 0, 0, opacity))),
          )..layout();
          glyph.paint(canvas, box.center - Offset(glyph.width / 2, glyph.height / 2));
          glyph.dispose();
        case DanmakuText():
      }
    }
    outline.dispose();
    fill.dispose();
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return null;
    final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final pixels = calloc<Uint8>(rgba.length);
    final bgra = pixels.asTypedList(rgba.length);
    bgra.setAll(0, rgba);
    for (var i = 0; i < bgra.length; i += 4) {
      final red = bgra[i];
      bgra[i] = bgra[i + 2];
      bgra[i + 2] = red;
    }
    return DanmakuBitmap._(pixels, width, height, pad, osdHeight);
  }
}
