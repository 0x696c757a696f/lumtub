import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Smooth mouse-wheel scrolling for everything under it: a list a wheel
/// notch jumps is put back and eased to where the notch sent it instead.
/// Notches that come while it is still moving add to where it is heading,
/// so a quick spin glides on rather than starting over. Whichever list
/// takes the notch, nested or sideways, is the one that moves. Touchpads,
/// touch and dragging are left alone, and with reduced motion the wheel
/// jumps again.
class SmoothWheel extends StatefulWidget {
  const SmoothWheel({super.key, required this.child});

  final Widget child;

  static const duration = Duration(milliseconds: 200);
  static const curve = Curves.easeOutCubic;

  @override
  State<SmoothWheel> createState() => _SmoothWheelState();
}

/// Where a list the wheel set moving is heading.
class _Glide {
  _Glide(this.target);
  final double target;
}

class _SmoothWheelState extends State<SmoothWheel> {
  static final _gliding = Expando<_Glide>();

  /// Lists moved while a notch is handled, with where each one was before.
  Map<ScrollPosition, double>? _moved;

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.kind != PointerDeviceKind.mouse || Motion.reduced || _moved != null) return;
    _moved = {};
    // The list takes the notch after every listener on the way has seen it;
    // what it did is looked at once the event is done.
    scheduleMicrotask(_ease);
  }

  bool _onUpdate(ScrollUpdateNotification notification) {
    final moved = _moved;
    if (moved == null || notification.dragDetails != null) return false;
    final position = Scrollable.maybeOf(notification.context!)?.position;
    if (position != null) moved.putIfAbsent(position, () => notification.metrics.pixels - (notification.scrollDelta ?? 0));
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
      final heading = _gliding[position]?.target;
      // A notch the same way as the glide adds to it; turning back starts
      // from where the list is.
      final base = heading != null && (heading - from) * step > 0 ? heading : from;
      final target = (base + step).clamp(position.minScrollExtent, position.maxScrollExtent);
      final glide = _gliding[position] = _Glide(target);
      position.jumpTo(from);
      position.animateTo(target, duration: SmoothWheel.duration, curve: SmoothWheel.curve).whenComplete(() {
        if (identical(_gliding[position], glide)) _gliding[position] = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerSignal: _onSignal,
        child: NotificationListener<ScrollUpdateNotification>(onNotification: _onUpdate, child: widget.child),
      );
}
