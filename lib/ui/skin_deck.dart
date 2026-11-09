import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../skins/skin.dart';
import 'scene_props.dart';
import 'theme.dart';

/// The player body under the picture in a skin with "player": {"style":
/// "deck"}: a piece of hardware of its own, in metal, pearl or clear
/// plastic, with a little screen showing the time and title, a groove to
/// seek in and round buttons, the big one to play.
class SkinDeckView extends StatefulWidget {
  const SkinDeckView({super.key, required this.deck, required this.player, required this.title, required this.onSeek});
  final SkinDeck deck;
  final Player? player;
  final String title;
  final Future<void> Function(Duration to) onSeek;

  @override
  State<SkinDeckView> createState() => _SkinDeckViewState();
}

class _SkinDeckViewState extends State<SkinDeckView> {
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _dragging;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(SkinDeckView old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) _listen();
  }

  void _listen() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
    final player = widget.player;
    if (player == null) return;
    _playing = player.state.playing;
    _position = player.state.position;
    _duration = player.state.duration;
    _subscriptions
      ..add(player.stream.playing.listen((v) => setState(() => _playing = v)))
      ..add(player.stream.position.listen((v) {
        // The groove moves smoothly enough at a few steps a second.
        if ((v - _position).abs() >= const Duration(milliseconds: 250)) setState(() => _position = v);
      }))
      ..add(player.stream.duration.listen((v) => setState(() => _duration = v)));
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  void _jump(int seconds) {
    final to = _position + Duration(seconds: seconds);
    unawaited(widget.onSeek(to < Duration.zero ? Duration.zero : (_duration > Duration.zero && to > _duration ? _duration : to)));
  }

  double get _played => _dragging ?? (_duration.inMilliseconds == 0 ? 0 : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0, 1).toDouble());

  @override
  Widget build(BuildContext context) {
    final d = widget.deck;
    final boombox = d.shape == 'boombox';
    final height = boombox ? 96.0 : (d.shape == 'oval' ? 82.0 : 70.0);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _BodyPainter(d, warmth: context.pictureWarmth),
          child: LayoutBuilder(builder: (context, box) {
            final narrow = box.maxWidth < 520;
            // Room for the round ends, or the speakers in them.
            final ends = boombox || d.speakers ? height * 0.86 : (d.shape == 'capsule' || d.shape == 'oval' ? height * 0.42 : 14.0);
            final play = height * (boombox ? 0.5 : 0.62);
            final small = play * 0.7;
            final top = boombox ? height * 0.24 : (d.shape == 'wave' ? height * 0.16 : 0.0);
            return Padding(
              padding: EdgeInsets.fromLTRB(ends, top, ends, boombox ? height * 0.06 : 0),
              child: Row(children: [
                _GelButton(colors: d.button, glyph: d.glyph, size: small, kind: _Glyph.back, glow: d.glow, tooltip: '-10', onTap: () => _jump(-10)),
                const SizedBox(width: 6),
                _GelButton(colors: d.play, glyph: d.playGlyph, size: play, kind: _playing ? _Glyph.pause : _Glyph.play, glow: d.glow, onTap: () => unawaited(widget.player?.playOrPause())),
                const SizedBox(width: 6),
                _GelButton(colors: d.button, glyph: d.glyph, size: small, kind: _Glyph.forward, glow: d.glow, tooltip: '+10', onTap: () => _jump(10)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _Screen(deck: d, time: '${_clock(_dragging == null ? _position : _duration * _dragging!)} / ${_clock(_duration)}', title: narrow ? '' : widget.title),
                    const SizedBox(height: 7),
                    _Groove(
                      deck: d,
                      played: _played,
                      onDrag: (v) => setState(() => _dragging = v),
                      onDone: (v) {
                        setState(() => _dragging = null);
                        if (_duration > Duration.zero) unawaited(widget.onSeek(_duration * v));
                      },
                    ),
                  ]),
                ),
              ]),
            );
          }),
        ),
      ),
    );
  }
}

String _clock(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// The outline of each deck shape inside [rect].
Path deckOutline(String shape, Rect rect) {
  final h = rect.height;
  switch (shape) {
    case 'slab':
      return Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)));
    case 'oval':
      return Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.elliptical(h * 0.9, h / 2)));
    case 'wave':
      // The top edge rolls; the bottom is a soft rounded base.
      final p = Path()..moveTo(rect.left, rect.top + h * 0.3);
      const steps = 60;
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        p.lineTo(rect.left + rect.width * t, rect.top + h * (0.16 + 0.12 * math.sin(t * math.pi * 2.6 + 0.4)));
      }
      return p
        ..lineTo(rect.right, rect.bottom - 16)
        ..quadraticBezierTo(rect.right, rect.bottom, rect.right - 16, rect.bottom)
        ..lineTo(rect.left + 16, rect.bottom)
        ..quadraticBezierTo(rect.left, rect.bottom, rect.left, rect.bottom - 16)
        ..close();
    case 'boombox':
      // A rounded box with a carry handle arching over the middle.
      final body = Rect.fromLTRB(rect.left, rect.top + h * 0.2, rect.right, rect.bottom);
      final handle = Path()
        ..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(rect.center.dx - rect.width * 0.22, rect.top, rect.center.dx + rect.width * 0.22, rect.top + h * 0.3), Radius.circular(h * 0.15)));
      final hole = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(rect.center.dx - rect.width * 0.2, rect.top + h * 0.07, rect.center.dx + rect.width * 0.2, rect.top + h * 0.22), Radius.circular(h * 0.08)));
      return Path.combine(PathOperation.union, Path()..addRRect(RRect.fromRectAndRadius(body, Radius.circular(h * 0.4))), Path.combine(PathOperation.difference, handle, hole));
    default:
      return Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(h / 2)));
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter(this.deck, {this.warmth});
  final SkinDeck deck;
  final Color? warmth;

  Color _w(Color c) => warmth == null ? c : Color.from(alpha: c.a, red: c.r * warmth!.r, green: c.g * warmth!.g, blue: c.b * warmth!.b);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outline = deckOutline(deck.shape, rect);
    final solid = 1 - deck.clear;
    // A soft shadow under the body.
    canvas.drawPath(outline.shift(const Offset(0, 3)), Paint()
      ..color = const Color(0xFF001830).withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawPath(outline, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [for (final c in deck.body) _w(c).withValues(alpha: c.a * solid)]).createShader(rect));
    canvas.save();
    canvas.clipPath(outline);
    // Brushed metal: faint horizontal lines; on clear plastic, a light
    // sheen instead.
    if (deck.clear == 0) {
      final line = Paint()..strokeWidth = 1;
      for (var y = 2.0; y < size.height; y += 2) {
        line.color = const Color(0xFFFFFFFF).withValues(alpha: (y.round() * 37 % 11) / 11 * 0.08);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
    }
    // The gloss over the top half.
    final top = Rect.fromLTRB(0, 0, size.width, size.height * 0.48);
    canvas.drawRRect(RRect.fromRectAndRadius(top.deflate(3), Radius.circular(size.height * 0.3)), Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFFFFFFFF).withValues(alpha: 0.7), const Color(0xFFFFFFFF).withValues(alpha: 0.08)]).createShader(top));
    // Round speakers at both ends.
    if (deck.speakers || deck.shape == 'boombox') {
      final r = size.height * (deck.shape == 'boombox' ? 0.36 : 0.32);
      final cy = deck.shape == 'boombox' ? size.height * 0.6 : size.height / 2;
      for (final cx in [r * 1.25, size.width - r * 1.25]) {
        final c = Offset(cx, cy);
        canvas.drawCircle(c, r, Paint()..shader = RadialGradient(colors: [_w(deck.rim), Color.lerp(_w(deck.rim), const Color(0xFF000000), 0.5)!]).createShader(Rect.fromCircle(center: c, radius: r)));
        // The grille.
        final dot = Paint()..color = const Color(0xFF000000).withValues(alpha: 0.35);
        for (var y = -r * 0.8; y <= r * 0.8; y += 4) {
          for (var x = -r * 0.8; x <= r * 0.8; x += 4) {
            if (x * x + y * y < r * r * 0.62) canvas.drawCircle(c + Offset(x, y), 0.9, dot);
          }
        }
        canvas.drawCircle(c, r * 0.28, Paint()..shader = RadialGradient(colors: [_w(deck.button.first), _w(deck.button.last)]).createShader(Rect.fromCircle(center: c, radius: r * 0.28)));
        canvas.drawCircle(c, r, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.65));
        gloss(canvas, c, r, strength: 0.5, shadow: false);
      }
    }
    canvas.restore();
    // The rim: a darker edge and a bright line just inside the top.
    canvas.drawPath(outline, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _w(deck.rim));
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, size.height * 0.5));
    canvas.drawPath(outline.shift(const Offset(0, 1.5)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.75));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BodyPainter old) => old.deck != deck || old.warmth != warmth;
}

class _Screen extends StatelessWidget {
  const _Screen({required this.deck, required this.time, required this.title});
  final SkinDeck deck;
  final String time;
  final String title;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: deck.screenText, fontSize: 13, fontWeight: FontWeight.w600, height: 1.1, fontFeatures: const [FontFeature.tabularFigures()]);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: deck.screen,
        border: Border.all(color: const Color(0x66000000)),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(deck.screen, const Color(0xFFFFFFFF), 0.12)!, deck.screen, deck.screen]),
        boxShadow: const [BoxShadow(color: Color(0x40FFFFFF), offset: Offset(0, 1))],
      ),
      child: Row(children: [
        Text(time, style: style),
        if (title.isNotEmpty) ...[
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: style.copyWith(fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ] else
          const Spacer(),
      ]),
    );
  }
}

class _Groove extends StatelessWidget {
  const _Groove({required this.deck, required this.played, required this.onDrag, required this.onDone});
  final SkinDeck deck;
  final double played;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onDone;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        double at(Offset p) => (p.dx / box.maxWidth).clamp(0, 1).toDouble();
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (e) => onDone(at(e.localPosition)),
            onHorizontalDragUpdate: (e) => onDrag(at(e.localPosition)),
            onHorizontalDragEnd: (_) => onDone(played),
            child: SizedBox(height: 16, width: double.infinity, child: CustomPaint(painter: _GroovePainter(deck, played))),
          ),
        );
      });
}

class _GroovePainter extends CustomPainter {
  _GroovePainter(this.deck, this.played);
  final SkinDeck deck;
  final double played;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final track = RRect.fromRectAndRadius(Rect.fromLTRB(0, y - 3, size.width, y + 3), const Radius.circular(3));
    canvas.drawRRect(track, Paint()..color = deck.groove);
    // Sunk in: dark above, light below.
    canvas.drawLine(Offset(3, y - 2.5), Offset(size.width - 3, y - 2.5), Paint()
      ..color = const Color(0x55000000)
      ..strokeWidth = 1);
    canvas.drawLine(Offset(3, y + 3.5), Offset(size.width - 3, y + 3.5), Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = 1);
    final x = size.width * played;
    if (x > 0) {
      final fill = RRect.fromRectAndRadius(Rect.fromLTRB(0, y - 3, x, y + 3), const Radius.circular(3));
      canvas.drawRRect(fill, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(deck.fill, const Color(0xFFFFFFFF), 0.45)!, deck.fill]).createShader(fill.outerRect));
    }
    // The knob: a little gel ball.
    gelOrb(canvas, Offset(math.max(6, math.min(x, size.width - 6)), y), 6.5, deck.button.last);
  }

  @override
  bool shouldRepaint(_GroovePainter old) => old.played != played || old.deck != deck;
}

enum _Glyph { play, pause, back, forward }

/// A round gel button: coloured right through, lit from the top, pressing
/// in when clicked.
class _GelButton extends StatefulWidget {
  const _GelButton({required this.colors, required this.glyph, required this.size, required this.kind, required this.onTap, this.glow, this.tooltip});
  final List<Color> colors;
  final Color glyph;
  final double size;
  final _Glyph kind;
  final VoidCallback onTap;
  final Color? glow;
  final String? tooltip;

  @override
  State<_GelButton> createState() => _GelButtonState();
}

class _GelButtonState extends State<_GelButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(painter: _GelPainter(widget, hover: _hover, down: _down)),
        ),
      ),
    );
    if (widget.tooltip != null) button = Tooltip(message: widget.tooltip!, child: button);
    return Semantics(button: true, label: widget.kind.name, child: button);
  }
}

class _GelPainter extends CustomPainter {
  _GelPainter(this.b, {required this.hover, required this.down});
  final _GelButton b;
  final bool hover;
  final bool down;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    if (b.glow != null || hover) {
      final g = b.glow ?? const Color(0xFFFFFFFF);
      canvas.drawCircle(c, r + 4, Paint()
        ..color = g.withValues(alpha: hover ? 0.6 : 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }
    // The socket it sits in.
    canvas.drawCircle(c, r + 1.5, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: const [Color(0x66000000), Color(0x22FFFFFF)]).createShader(rect.inflate(2)));
    final deep = b.colors.last;
    final light = down ? deep : (hover ? Color.lerp(b.colors.first, const Color(0xFFFFFFFF), 0.25)! : b.colors.first);
    canvas.drawCircle(c, r, Paint()..shader = RadialGradient(colors: [deep, deep, Color.lerp(deep, const Color(0xFF000000), 0.35)!], stops: const [0, 0.6, 1]).createShader(rect));
    // Light gathered in the bottom of the gel.
    final glow = Rect.fromCenter(center: c + Offset(0, r * 0.6), width: r * 1.5, height: r * 0.8);
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    canvas.drawOval(glow, Paint()..shader = RadialGradient(colors: [light.withValues(alpha: 0.9), light.withValues(alpha: 0)]).createShader(glow));
    canvas.restore();
    if (!down) gloss(canvas, c, r, strength: 0.85, shadow: false);
    _glyph(canvas, c + (down ? const Offset(0, 1) : Offset.zero), r * 0.42);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Color.lerp(b.colors.last, const Color(0xFF000000), 0.35)!);
  }

  void _glyph(Canvas canvas, Offset c, double s) {
    final paint = Paint()..color = b.glyph;
    final shade = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
    Path tri(Offset at, double w, bool right) => Path()
      ..moveTo(at.dx + (right ? -w * 0.45 : w * 0.45), at.dy - w * 0.6)
      ..lineTo(at.dx + (right ? w * 0.6 : -w * 0.6), at.dy)
      ..lineTo(at.dx + (right ? -w * 0.45 : w * 0.45), at.dy + w * 0.6)
      ..close();
    final Path path;
    switch (b.kind) {
      case _Glyph.play:
        path = tri(c + Offset(s * 0.12, 0), s * 1.1, true);
      case _Glyph.pause:
        path = Path()
          ..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c - Offset(s * 0.35, 0), width: s * 0.42, height: s * 1.3), Radius.circular(s * 0.1)))
          ..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(s * 0.35, 0), width: s * 0.42, height: s * 1.3), Radius.circular(s * 0.1)));
      case _Glyph.back:
        path = Path()
          ..addPath(tri(c - Offset(s * 0.3, 0), s * 0.8, false), Offset.zero)
          ..addPath(tri(c + Offset(s * 0.3, 0), s * 0.8, false), Offset.zero);
      case _Glyph.forward:
        path = Path()
          ..addPath(tri(c - Offset(s * 0.3, 0), s * 0.8, true), Offset.zero)
          ..addPath(tri(c + Offset(s * 0.3, 0), s * 0.8, true), Offset.zero);
    }
    canvas.drawPath(path.shift(const Offset(0, 1)), shade);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GelPainter old) => old.hover != hover || old.down != down || old.b.kind != b.kind || old.b.colors != b.colors;
}
