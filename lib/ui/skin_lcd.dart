import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart';

import '../skins/skin.dart';
import 'app_icons.dart';
import 'common.dart';
import 'motion.dart';
import 'skin_paint.dart';

/// The display under the picture in a skin with "player": {"style": "lcd"}:
/// the time, the title scrolling past, and a level meter, as on the media
/// players of the late 90s. The meter follows play and pause and the
/// volume; it is a decoration, not an analysis of the sound.
class SkinLcd extends StatefulWidget {
  const SkinLcd({super.key, required this.skin, required this.player, required this.title, required this.subtitle, required this.still});
  final Skin skin;
  final Player? player;
  final String title;
  final String subtitle;
  /// Nothing moves: Low resource mode or reduced motion.
  final bool still;

  @override
  State<SkinLcd> createState() => _SkinLcdState();
}

class _SkinLcdState extends State<SkinLcd> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _random = Random(7);
  final _levels = List<double>.filled(_bars, 0);
  final _targets = List<double>.filled(_bars, 0);
  Duration _last = Duration.zero;
  double _scroll = 0;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  static const _bars = 14;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(SkinLcd old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) _listen();
    _run();
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
      ..add(player.stream.playing.listen((v) => setState(() {
            _playing = v;
            _run();
          })))
      ..add(player.stream.position.listen((v) {
        // The display shows whole seconds, so it redraws once a second.
        if (v.inSeconds != _position.inSeconds) setState(() => _position = v);
      }))
      ..add(player.stream.duration.listen((v) => setState(() => _duration = v)));
    _run();
  }

  void _run() {
    final move = !widget.still && !Motion.reduced && (_playing || _levels.any((l) => l > 0.01));
    if (move && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!move && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    // 20 frames a second is enough for a meter and costs almost nothing.
    if (dt < 0.05) return;
    _last = elapsed;
    final volume = ((widget.player?.state.volume ?? 100) / 100).clamp(0.0, 1.0);
    for (var i = 0; i < _bars; i++) {
      if (_random.nextDouble() < 0.35) {
        // Lower bands sit higher, as music usually does.
        final band = 1 - i / _bars * 0.55;
        _targets[i] = _playing ? (0.25 + _random.nextDouble() * 0.75) * band * volume : 0;
      }
      final target = _playing ? _targets[i] : 0.0;
      _levels[i] += (target - _levels[i]) * (target > _levels[i] ? 0.6 : 0.25);
    }
    _scroll += dt * 36;
    setState(() {});
    if (!_playing && _levels.every((l) => l <= 0.01)) _ticker.stop();
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final player = skin.player;
    final text = player.lcdText;
    final glow = [Shadow(color: text.withValues(alpha: 0.6), blurRadius: 6)];
    final time = formatPlaybackTime(_position);
    final total = _duration > Duration.zero ? formatPlaybackTime(_duration) : '--:--';
    return Container(
      height: 56,
      margin: const EdgeInsets.only(top: 8),
      decoration: SurfaceDecoration.of(context, player.lcd ?? SkinSurface.solid(const Color(0xFF050A06)), radius: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: DefaultTextStyle(
        style: TextStyle(color: text, fontFamily: player.lcdFont, shadows: widget.still ? null : glow, height: 1.1),
        child: Row(children: [
          Icon(_playing ? AppIcons.playFill : AppIcons.pauseFill, size: 14, color: player.lcdAccent),
          const SizedBox(width: 6),
          Text(time, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              _Marquee(text: widget.title, offset: widget.still || Motion.reduced ? null : _scroll, style: const TextStyle(fontSize: 18)),
              Text('${widget.subtitle}  $time / $total', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: text.withValues(alpha: 0.75))),
            ]),
          ),
          if (player.spectrum) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 84,
              height: 36,
              child: CustomPaint(painter: _MeterPainter(List.of(_levels), text, player.lcdAccent)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// [text] in one line; if it is too long and [offset] is given it runs
/// past from right to left, looping.
class _Marquee extends StatelessWidget {
  const _Marquee({required this.text, required this.offset, required this.style});
  final String text;
  final double? offset;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final merged = DefaultTextStyle.of(context).style.merge(style);
        final painter = TextPainter(text: TextSpan(text: text, style: merged), textDirection: Directionality.of(context), maxLines: 1)..layout();
        final width = painter.width;
        final height = painter.height;
        painter.dispose();
        final offset = this.offset;
        if (offset == null || width <= constraints.maxWidth) {
          return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
        }
        const gap = 48.0;
        final x = -(offset % (width + gap));
        return ClipRect(
          child: SizedBox(
            height: height,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(left: x, top: 0, child: Text(text, maxLines: 1, softWrap: false, style: style)),
              Positioned(left: x + width + gap, top: 0, child: Text(text, maxLines: 1, softWrap: false, style: style)),
            ]),
          ),
        );
      });
}

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.levels, this.color, this.peak);
  final List<double> levels;
  final Color color;
  final Color peak;

  @override
  void paint(Canvas canvas, Size size) {
    const rows = 9;
    final step = size.width / levels.length;
    final cell = size.height / rows;
    final off = Paint()..color = color.withValues(alpha: 0.12);
    final on = Paint()..color = color;
    final top = Paint()..color = peak;
    for (var i = 0; i < levels.length; i++) {
      final lit = (levels[i] * rows).round();
      for (var r = 0; r < rows; r++) {
        final rect = Rect.fromLTWH(i * step + 1, size.height - (r + 1) * cell + 1, step - 2, cell - 2);
        canvas.drawRect(rect, r >= lit ? off : (r >= rows - 2 ? top : on));
      }
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) => true;
}
