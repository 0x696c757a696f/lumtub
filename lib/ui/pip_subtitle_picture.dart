import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The subtitle lines Flutter's view draws, as a picture for iOS's
/// picture-in-picture window, which shows only what goes into the video
/// frames: libmpv's own subtitles go in by themselves, these where libmpv
/// has no font for a line.
typedef PipSubtitlePicture = ({Uint8List pixels, int width, int height, double x, double y});

/// One subtitle line's look: its style, as the Flutter view draws it.
typedef PipSubtitleStyle = ({TextStyle style, double outline});

/// Draws [second] above [main] on a canvas [canvas] big, the way the
/// Flutter subtitle view lays them out: centred, at most nine tenths of
/// the width, [scale] times their size, with their outline, their bottom
/// [position] percent down the canvas (100 is the bottom edge). Only the
/// box around the text is drawn; null when there is no text.
Future<PipSubtitlePicture?> drawPipSubtitles({
  required String main,
  required String second,
  required PipSubtitleStyle mainStyle,
  required PipSubtitleStyle secondStyle,
  required Size canvas,
  required double scale,
  required int position,
}) async {
  final lines = [
    if (second.trim().isNotEmpty) (text: second.trim(), look: secondStyle),
    if (main.trim().isNotEmpty) (text: main.trim(), look: mainStyle),
  ];
  if (lines.isEmpty || canvas.isEmpty) return null;
  final room = canvas.width * 0.9;
  final scaler = TextScaler.linear(scale);
  final laid = [
    for (final line in lines)
      (
        painter: TextPainter(text: TextSpan(text: line.text, style: line.look.style), textDirection: TextDirection.ltr, textAlign: TextAlign.center, textScaler: scaler, maxLines: 4)
          ..layout(maxWidth: room),
        stroke: line.look.outline * scale,
        look: line.look,
        text: line.text,
      ),
  ];
  final spacing = 6 * scale;
  final pad = laid.map((l) => l.stroke).fold(0.0, max).ceilToDouble() + 1;
  final width = laid.map((l) => l.painter.width).fold(0.0, max) + 2 * pad;
  final height = laid.fold(0.0, (sum, l) => sum + l.painter.height) + spacing * (laid.length - 1) + 2 * pad;
  final w = width.ceil(), h = height.ceil();
  if (w <= 0 || h <= 0) return null;

  final recorder = ui.PictureRecorder();
  final canvasOf = Canvas(recorder);
  var top = pad;
  for (final line in laid) {
    final left = (width - line.painter.width) / 2;
    if (line.stroke > 0) {
      // The outline under the letters, as the view and libass draw it.
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = line.stroke * 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF000000).withValues(alpha: line.look.style.color?.a ?? 1);
      final outline = TextPainter(text: TextSpan(text: line.text, style: line.look.style.copyWith(foreground: stroke, shadows: const [])), textDirection: TextDirection.ltr, textAlign: TextAlign.center, textScaler: scaler, maxLines: 4)
        ..layout(maxWidth: room)
        ..paint(canvasOf, Offset(left, top));
      outline.dispose();
    }
    line.painter.paint(canvasOf, Offset(left, top));
    top += line.painter.height + spacing;
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  try {
    // Premultiplied, as Core Graphics takes it.
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) return null;
    final bottom = canvas.height * position.clamp(0, 100) / 100 - canvas.height * 0.03;
    return (
      pixels: bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      width: w,
      height: h,
      x: (canvas.width - width) / 2,
      y: max(0.0, min(bottom, canvas.height) - height),
    );
  } finally {
    image.dispose();
    for (final line in laid) {
      line.painter.dispose();
    }
  }
}

/// A subtitle line's look as the Flutter view gives it: [font] at [scale]
/// of 32 px, in [color] at [opacity], with [fallback] and [locale] for
/// its language, its outline [outline] px wide or a box behind it.
PipSubtitleStyle pipSubtitleStyle({
  required String font,
  required double scale,
  required int color,
  required double opacity,
  required bool bold,
  required bool box,
  required double outline,
  required List<String> fallback,
  Locale? locale,
}) =>
    (
      style: TextStyle(
        height: 1.3,
        fontSize: 32 * scale,
        fontFamily: font.isEmpty ? null : font,
        fontFamilyFallback: fallback,
        locale: locale,
        color: Color(0xFF000000 | color).withValues(alpha: opacity),
        fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
        backgroundColor: box ? Color.fromRGBO(0, 0, 0, 0.67 * opacity) : null,
      ),
      outline: box ? 0 : outline,
    );
