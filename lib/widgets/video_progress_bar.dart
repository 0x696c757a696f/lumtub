import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';

/// A coloured stretch of the bar, such as a SponsorBlock segment or the
/// A-B loop.
class ProgressSegment {
  const ProgressSegment(this.start, this.end, this.color);
  final Duration start;
  final Duration end;
  final Color color;
}

/// A picture of fixed [size] shown over the pointer; [builder] makes it for
/// the time under the pointer.
class ProgressPreview {
  const ProgressPreview(this.size, this.builder);
  final Size size;
  final Widget Function(Duration time) builder;
}

/// A seek bar for a mouse: a thin track that thickens under the pointer,
/// with a time label (and a picture, when there is one) following it.
class VideoProgressBar extends StatefulWidget {
  const VideoProgressBar({
    super.key,
    required this.position,
    required this.buffered,
    required this.total,
    required this.onSeek,
    required this.color,
    this.playedGradient,
    this.segments = const [],
    this.chapterStarts = const [],
    this.labelOf,
    this.preview,
    this.heatmap,
  });

  final Duration position;
  final Duration buffered;
  final Duration total;
  final ValueChanged<Duration> onSeek;
  final Color color;
  final Gradient? playedGradient;
  final List<ProgressSegment> segments;
  final List<Duration> chapterStarts;
  final String Function(Duration time)? labelOf;
  final ProgressPreview? preview;

  /// Samples from 0 to 1 across the whole bar.
  final List<double>? heatmap;

  static const double barHeight = 3.5;
  static const double height = 20.0;

  /// The height that takes a tap: a finger needs more than a mouse, the
  /// track drawn in its middle stays as thin.
  static final double touchHeight = Platform.isAndroid || Platform.isIOS ? 40.0 : height;
  static const double heatmapHeight = 16.0;

  @override
  State<VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<VideoProgressBar> {
  double? _hover;
  double? _drag;
  bool _touching = false;

  void _letGo() {
    if (!_touching) return;
    _touching = false;
    setState(() => _hover = null);
  }

  double _fractionAt(double x, double width) => width <= 0 ? 0 : (x / width).clamp(0.0, 1.0);

  Duration _timeAt(double fraction) => widget.total * fraction;

  double _fractionOf(Duration time) {
    final total = widget.total.inMicroseconds;
    return total <= 0 ? 0 : (time.inMicroseconds / total).clamp(0.0, 1.0);
  }

  String _clock(Duration time) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hours = time.inHours;
    final minutes = two(time.inMinutes.remainder(60));
    final seconds = two(time.inSeconds.remainder(60));
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  void _seekTo(double fraction) {
    if (widget.total <= Duration.zero) return;
    widget.onSeek(_timeAt(fraction));
  }

  String _spoken(Duration at) => '${_clock(at < Duration.zero ? Duration.zero : (at > widget.total ? widget.total : at))} / ${_clock(widget.total)}';

  /// Screen readers move it five seconds at a time.
  void _step(int seconds) {
    if (widget.total <= Duration.zero) return;
    final to = widget.position + Duration(seconds: seconds);
    widget.onSeek(to < Duration.zero ? Duration.zero : (to > widget.total ? widget.total : to));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final pointer = _drag ?? _hover;
      final dragging = _drag != null;
      final heat = widget.heatmap;
      final hasHeat = heat != null && heat.length > 1;
      final played = _drag ?? _fractionOf(widget.position);
      final height = VideoProgressBar.touchHeight;
      final known = widget.total > Duration.zero;
      return Semantics(
        slider: true,
        value: known ? _spoken(widget.position) : null,
        increasedValue: known ? _spoken(widget.position + const Duration(seconds: 5)) : null,
        decreasedValue: known ? _spoken(widget.position - const Duration(seconds: 5)) : null,
        onIncrease: known ? () => _step(5) : null,
        onDecrease: known ? () => _step(-5) : null,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (event) => setState(() => _hover = _fractionAt(event.localPosition.dx, width)),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // A finger has no hover: the time shows while it is down.
            onTapDown: (details) {
              if (details.kind == PointerDeviceKind.mouse) return;
              _touching = true;
              setState(() => _hover = _fractionAt(details.localPosition.dx, width));
            },
            onTapCancel: _letGo,
            onTapUp: (details) {
              _letGo();
              _seekTo(_fractionAt(details.localPosition.dx, width));
            },
            onHorizontalDragStart: (details) => setState(() => _drag = _fractionAt(details.localPosition.dx, width)),
            onHorizontalDragUpdate: (details) => setState(() => _drag = _fractionAt(details.localPosition.dx, width)),
            onHorizontalDragEnd: (_) {
              final last = _drag;
              setState(() => _drag = null);
              if (last != null) _seekTo(last);
            },
            onHorizontalDragCancel: () => setState(() => _drag = null),
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(clipBehavior: Clip.none, children: [
                if (hasHeat)
                  Positioned(
                    left: 0,
                    right: 0,
                    height: VideoProgressBar.heatmapHeight,
                    bottom: height / 2 + VideoProgressBar.barHeight / 2 + 1,
                    child: IgnorePointer(child: CustomPaint(painter: _HeatPainter(heat, widget.color))),
                  ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TrackPainter(
                      color: widget.color,
                      gradient: widget.playedGradient,
                      played: played,
                      buffered: _fractionOf(widget.buffered),
                      segments: [for (final s in widget.segments) (_fractionOf(s.start), _fractionOf(s.end), s.color)],
                      chapters: [for (final c in widget.chapterStarts) if (c > Duration.zero) _fractionOf(c)],
                      active: pointer != null,
                      pointer: pointer,
                    ),
                  ),
                ),
                if (pointer != null && widget.total > Duration.zero) _label(width, pointer, hasHeat, dragging),
              ]),
            ),
          ),
        ),
      );
    });
  }

  Widget _label(double width, double pointer, bool hasHeat, bool dragging) {
    final time = _timeAt(pointer);
    final text = widget.labelOf?.call(time) ?? _clock(time);
    const style = TextStyle(color: Colors.white, fontSize: 12);
    final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout(maxWidth: 320);
    final labelWidth = painter.width + 16;
    painter.dispose();
    final preview = widget.preview;
    final columnWidth = math.max(labelWidth, preview?.size.width ?? 0);
    final left = (pointer * width - columnWidth / 2).clamp(0.0, math.max(0.0, width - columnWidth)).toDouble();
    return Positioned(
      left: left,
      width: columnWidth,
      bottom: VideoProgressBar.touchHeight + 4 + (hasHeat ? 16 : 0),
      child: IgnorePointer(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (preview != null) ...[
              DecoratedBox(
                decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: 0.7)), borderRadius: BorderRadius.circular(4)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox.fromSize(size: preview.size, child: preview.builder(time)),
                ),
              ),
              const SizedBox(height: 4),
            ],
            Container(
              width: labelWidth,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(4)),
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: style),
            ),
          ]),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.color,
    required this.gradient,
    required this.played,
    required this.buffered,
    required this.segments,
    required this.chapters,
    required this.active,
    required this.pointer,
  });

  final Color color;
  final Gradient? gradient;
  final double played;
  final double buffered;
  final List<(double, double, Color)> segments;
  final List<double> chapters;
  final bool active;
  final double? pointer;

  static const _dark = Color(0xCC000000);

  @override
  void paint(Canvas canvas, Size size) {
    final thickness = active ? VideoProgressBar.barHeight + 1.5 : VideoProgressBar.barHeight;
    final cy = size.height / 2;
    final track = Rect.fromLTWH(0, cy - thickness / 2, size.width, thickness);
    final w = size.width;

    void fill(double from, double to, Paint paint) {
      if (to <= from) return;
      canvas.drawRect(Rect.fromLTRB(from * w, track.top, to * w, track.bottom), paint);
    }

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(track, Radius.circular(thickness / 2)));
    fill(0, 1, Paint()..color = const Color(0x33FFFFFF));
    fill(0, buffered, Paint()..color = color.withValues(alpha: 0.4));
    final playedPaint = Paint()..color = color;
    if (gradient != null) playedPaint.shader = gradient!.createShader(track);
    fill(0, played, playedPaint);

    for (final (start, end, segmentColor) in segments) {
      if (end <= start) continue;
      final shade = Color.alphaBlend(const Color(0x59000000), segmentColor);
      final split = played.clamp(start, end);
      fill(start, split, Paint()..color = shade);
      fill(split, end, Paint()..color = segmentColor);
      for (final edge in [start, end]) {
        canvas.drawRect(Rect.fromLTWH(edge * w - 0.75, track.top, 1.5, thickness), Paint()..color = _dark);
      }
    }
    canvas.restore();

    for (final chapter in chapters) {
      canvas.drawRect(Rect.fromLTWH(chapter * w - 1, track.top - 0.5, 2, thickness + 1), Paint()..color = _dark);
    }

    canvas.drawCircle(Offset(played * w, cy), active ? 7 : 5.5, Paint()..color = color);

    final x = pointer == null ? null : pointer! * w;
    if (x != null) {
      final paint = Paint()..color = color;
      canvas.drawPath(Path()..moveTo(x - 4.5, cy - 9)..lineTo(x + 4.5, cy - 9)..lineTo(x, cy - 4)..close(), paint);
      canvas.drawPath(Path()..moveTo(x - 4.5, cy + 9)..lineTo(x + 4.5, cy + 9)..lineTo(x, cy + 4)..close(), paint);
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) {
    if (old.color != color || old.gradient != gradient || old.played != played || old.buffered != buffered || old.active != active || old.pointer != pointer) return true;
    if (old.segments.length != segments.length || old.chapters.length != chapters.length) return true;
    for (var i = 0; i < segments.length; i++) {
      if (old.segments[i] != segments[i]) return true;
    }
    for (var i = 0; i < chapters.length; i++) {
      if (old.chapters[i] != chapters[i]) return true;
    }
    return false;
  }
}

class _HeatPainter extends CustomPainter {
  _HeatPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final peak = values.fold<double>(0, math.max);
    if (n < 2 || peak <= 0) return;
    final bottom = size.height;
    final points = [
      for (var i = 0; i < n; i++) Offset(i / (n - 1) * size.width, bottom - (values[i] / peak).clamp(0.0, 1.0) * (size.height - 1) - 1),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < n - 1; i++) {
      final mid = Offset((points[i].dx + points[i + 1].dx) / 2, (points[i].dy + points[i + 1].dy) / 2);
      line.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    line.lineTo(points.last.dx, points.last.dy);
    final area = Path.from(line)
      ..lineTo(points.last.dx, bottom)
      ..lineTo(points.first.dx, bottom)
      ..close();
    canvas.drawPath(area, Paint()..color = Colors.white.withValues(alpha: 0.14));
    canvas.drawPath(line, Paint()..color = Colors.white.withValues(alpha: 0.3)..style = PaintingStyle.stroke..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_HeatPainter old) => !identical(old.values, values) || old.color != color;
}
