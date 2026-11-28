import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Smooth mouse-wheel scrolling for everything under it: a list a wheel
/// notch jumps is put back and glides to where the notch sent it instead.
/// Notches that come while it is still moving add to where it is heading
/// and carry on at the speed it already has, so a quick spin glides on
/// rather than starting over or surging at every notch. Whichever list
/// takes the notch, nested or sideways, is the one that moves. Touchpads,
/// touch and dragging are left alone.
///
/// The glide is a function of time, not of frames: a frame that comes late
/// (a busy or throttled processor) shows the list where it should be by
/// then, so the scroll keeps its pace and length and only fewer steps of it
/// are seen. It is a wheel's own motion, like a browser's smooth
/// scrolling, so it stays on in 低占用模式 and with the system's reduced
/// animations; only Lumtub's own 减少动画 turns it off ([enabled]).
class SmoothWheel extends StatefulWidget {
  const SmoothWheel({super.key, required this.child});

  final Widget child;

  /// Whether the wheel glides; set from the appearance settings.
  static bool enabled = true;

  /// How long a notch from rest takes.
  static const duration = Duration(milliseconds: 200);

  /// The shortest a glide is made to keep the speed it already has.
  static const shortest = Duration(milliseconds: 90);

  @override
  State<SmoothWheel> createState() => _SmoothWheelState();
}

/// Where a list the wheel set moving is heading, and how: an ease-out
/// cubic from [from] to [target] over [duration], timed by the frame clock
/// from [start] (the first frame it moves, unless it carries on from a
/// glide before it).
class _Glide {
  _Glide(this.from, this.target, this.duration, {this.start});
  final double from;
  final double target;
  final Duration duration;
  Duration? start;

  /// The frame it last moved the list in.
  Duration? lastFrame;

  double _u(Duration at) {
    final since = at - (start ?? at);
    return duration == Duration.zero
        ? 1
        : (since.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);
  }

  /// Where the list is at frame time [at].
  double positionAt(Duration at) {
    final rest = 1 - _u(at);
    return from + (target - from) * (1 - rest * rest * rest);
  }

  /// Pixels a second at frame time [at].
  double velocityAt(Duration at) {
    final rest = 1 - _u(at);
    return duration == Duration.zero
        ? 0
        : 3 *
            (target - from) *
            rest *
            rest /
            (duration.inMicroseconds / Duration.microsecondsPerSecond);
  }

  bool doneAt(Duration at) => _u(at) >= 1;
}

/// Moves a list along a [_Glide], one step for each frame, to where the
/// glide is at the time of that frame. Like Flutter's own animated scroll it
/// holds the pointer off the list while it moves, so the cards passing
/// under a still mouse do not each light up and fade on the way.
/// The time between frames of the display.
Duration get _frameInterval {
  final views = SchedulerBinding.instance.platformDispatcher.views;
  final rate = views.isEmpty ? 60.0 : views.first.display.refreshRate;
  return Duration(
      microseconds:
          (Duration.microsecondsPerSecond / (rate.isFinite && rate >= 24 ? rate : 60)).round());
}

class _GlideActivity extends ScrollActivity {
  _GlideActivity(super.delegate, this.glide, TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick)..start();
  }

  final _Glide glide;
  late final Ticker _ticker;
  double _velocity = 0;

  void _tick(Duration _) {
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    // A glide from rest counts from a frame before its first, so its first
    // frame already moves the list.
    glide.start ??= now - _frameInterval;
    glide.lastFrame = now;
    _velocity = glide.velocityAt(now);
    if (delegate.setPixels(glide.positionAt(now)) != 0) {
      // Hit an end (the list became shorter under it).
      delegate.goIdle();
      return;
    }
    if (glide.doneAt(now)) delegate.goBallistic(0);
  }

  @override
  bool get shouldIgnorePointer => true;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => _velocity;

  @override
  void dispatchOverscrollNotification(
      ScrollMetrics metrics, BuildContext context, double overscroll) {
    OverscrollNotification(
            metrics: metrics, context: context, overscroll: overscroll, velocity: velocity)
        .dispatch(context);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

class _SmoothWheelState extends State<SmoothWheel> {
  static final _gliding = Expando<_Glide>();

  /// The time of the latest frame drawn, whoever asked for it.
  static Duration? _latestFrame;
  static bool _timing = false;

  @override
  void initState() {
    super.initState();
    if (_timing) return;
    _timing = true;
    SchedulerBinding.instance.addPersistentFrameCallback((time) => _latestFrame = time);
  }

  /// Lists moved while a notch is handled, with where each one was before.
  Map<ScrollPosition, double>? _moved;

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.kind != PointerDeviceKind.mouse ||
        !SmoothWheel.enabled ||
        _moved != null) {
      return;
    }
    _moved = {};
    // The list takes the notch after every listener on the way has seen it;
    // what it did is looked at once the event is done.
    scheduleMicrotask(_ease);
  }

  bool _onUpdate(ScrollUpdateNotification notification) {
    final moved = _moved;
    if (moved == null || notification.dragDetails != null) return false;
    final position = Scrollable.maybeOf(notification.context!)?.position;
    if (position != null) {
      moved.putIfAbsent(
          position, () => notification.metrics.pixels - (notification.scrollDelta ?? 0));
    }
    return false;
  }

  void _ease() {
    final moved = _moved;
    _moved = null;
    if (moved == null || !mounted) return;
    for (final MapEntry(key: position, value: from) in moved.entries) {
      if (!position.hasPixels || !position.hasContentDimensions) continue;
      final step = position.pixels - from;
      if (step == 0) continue;
      // The glide this notch broke off: one still moving the list in the
      // last frame drawn (a drag or a key since would have drawn frames of
      // its own) and heading the same way.
      var before = _gliding[position];
      if (before != null) {
        final last = before.lastFrame;
        final moving = last == null || (last == _latestFrame && !before.doneAt(last));
        if (!moving || (before.target - from) * step <= 0) before = null;
      }
      // A notch the same way adds to where the glide is heading and goes on
      // from the last frame at the speed it had there, so the next frame
      // steps on as far as the one before; turning back starts at rest.
      final base = before?.target ?? from;
      final target = (base + step).clamp(position.minScrollExtent, position.maxScrollExtent);
      final distance = target - from;
      var duration = SmoothWheel.duration;
      final last = before?.lastFrame;
      final speed = last == null ? 0.0 : before!.velocityAt(last);
      if (speed * distance > 0) {
        // An ease-out cubic starts at three times its average speed: as
        // long as that takes to start at the speed the list already has.
        final seconds = 3 * distance / speed;
        duration = Duration(
            microseconds: (seconds * Duration.microsecondsPerSecond)
                .round()
                .clamp(SmoothWheel.shortest.inMicroseconds, SmoothWheel.duration.inMicroseconds));
      }
      final glide = _gliding[position] = _Glide(from, target, duration, start: last);
      position.jumpTo(from);
      if (position is ScrollPositionWithSingleContext) {
        position.beginActivity(_GlideActivity(position, glide, position.context.vsync));
      } else {
        unawaited(position.animateTo(target, duration: duration, curve: Curves.easeOutCubic));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerSignal: _onSignal,
        child: NotificationListener<ScrollUpdateNotification>(
            onNotification: _onUpdate, child: widget.child),
      );
}
