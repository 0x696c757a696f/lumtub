import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

import 'motion.dart';

/// Smooth mouse-wheel scrolling everywhere: each wheel notch reaches the
/// app as a short run of smaller scroll signals that ease out, instead of
/// one jump, so every list, grid and page scrolls with it unchanged.
/// Touchpads (pan/zoom gestures) are left as they are, and with reduced
/// motion the wheel jumps again.
class SmoothWheel {
  SmoothWheel._(this._forward);

  /// One that passes what it makes to [forward], for tests.
  @visibleForTesting
  SmoothWheel.to(ui.PointerDataPacketCallback forward) : _forward = forward;

  /// Takes a packet from the engine.
  @visibleForTesting
  void receive(ui.PointerDataPacket packet) => _receive(packet);

  static const duration = Duration(milliseconds: 220);

  static SmoothWheel? _instance;

  /// Signals this class made after the first one of a notch, by time stamp.
  /// Handlers that count notches (the player's volume) skip them.
  static final _followUps = <Duration>{};

  final ui.PointerDataPacketCallback _forward;
  late final Ticker _ticker = Ticker(_tick);
  ui.PointerData? _template;
  double _x = 0, _y = 0;
  double _sentFraction = 0;
  Duration _started = Duration.zero;

  /// Puts itself between the engine and the gesture binding; call once
  /// after the binding is initialized.
  static void install() {
    if (_instance != null) return;
    final dispatcher = ui.PlatformDispatcher.instance;
    final forward = dispatcher.onPointerDataPacket;
    if (forward == null) return;
    final wheel = _instance = SmoothWheel._(forward);
    dispatcher.onPointerDataPacket = wheel._receive;
  }

  /// Whether [event] continues a wheel notch already delivered.
  static bool isFollowUp(PointerScrollEvent event) => _followUps.contains(event.timeStamp);

  static double _ease(double t) => 1 - (1 - t) * (1 - t) * (1 - t);

  void _receive(ui.PointerDataPacket packet) {
    if (Motion.reduced || !packet.data.any(_isWheel)) {
      _forward(packet);
      return;
    }
    final rest = <ui.PointerData>[];
    for (final datum in packet.data) {
      if (!_isWheel(datum)) {
        rest.add(datum);
        continue;
      }
      if (rest.isNotEmpty) {
        _forward(ui.PointerDataPacket(data: List.of(rest)));
        rest.clear();
      }
      _start(datum);
    }
    if (rest.isNotEmpty) _forward(ui.PointerDataPacket(data: rest));
  }

  static bool _isWheel(ui.PointerData datum) => datum.signalKind == ui.PointerSignalKind.scroll && datum.kind == ui.PointerDeviceKind.mouse;

  void _start(ui.PointerData datum) {
    final left = 1 - _sentFraction;
    final sameWay = _template != null && _x * datum.scrollDeltaX >= 0 && _y * datum.scrollDeltaY >= 0;
    // A notch during a glide carries on from what is left of it, the way it
    // goes; turning the wheel back drops the rest.
    _x = (sameWay ? _x * left : 0) + datum.scrollDeltaX;
    _y = (sameWay ? _y * left : 0) + datum.scrollDeltaY;
    _template = datum;
    _sentFraction = 0;
    _started = _ticker.isActive ? _elapsed : Duration.zero;
    // The first piece goes now, as the notch itself, so the page answers at
    // once and notch counters see each notch once.
    _send(_ease(16 / duration.inMilliseconds), followUp: false);
    if (!_ticker.isActive) _ticker.start();
  }

  Duration _elapsed = Duration.zero;

  void _tick(Duration elapsed) {
    _elapsed = elapsed;
    final t = ((elapsed - _started).inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);
    _send(_ease(t), followUp: true);
    if (t >= 1) _stop();
  }

  void _send(double fraction, {required bool followUp}) {
    final template = _template;
    if (template == null || fraction <= _sentFraction) return;
    final step = fraction - _sentFraction;
    _sentFraction = fraction;
    var stamp = template.timeStamp + (followUp ? _elapsed - _started + const Duration(microseconds: 1) : Duration.zero);
    if (followUp) {
      while (_followUps.contains(stamp)) {
        stamp += const Duration(microseconds: 1);
      }
      _followUps.add(stamp);
      if (_followUps.length > 256) _followUps.remove(_followUps.first);
    }
    _forward(ui.PointerDataPacket(data: [
      ui.PointerData(
        viewId: template.viewId,
        timeStamp: stamp,
        change: template.change,
        kind: template.kind,
        signalKind: template.signalKind,
        device: template.device,
        pointerIdentifier: template.pointerIdentifier,
        physicalX: template.physicalX,
        physicalY: template.physicalY,
        buttons: template.buttons,
        scrollDeltaX: _x * step,
        scrollDeltaY: _y * step,
      ),
    ]));
  }

  void _stop() {
    _ticker.stop();
    _template = null;
    _x = _y = 0;
    _sentFraction = 0;
    _elapsed = Duration.zero;
  }
}
