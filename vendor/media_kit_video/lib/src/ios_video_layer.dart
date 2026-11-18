// Lumtub: picture in picture on iOS, through the display layer libmpv's
// avfoundation video output draws into (ios/Classes/plugin/PlayerLayer.swift).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the picture-in-picture window asks for or tells.
enum IosPipEvent {
  /// About to open (also when iOS opens it on going home).
  willStart,
  started,
  stopped,

  /// Its button to go back to the app was pressed.
  restore,
  play,
  pause,

  /// Skip by [IosVideoLayer.onEvent]'s seconds (negative: back).
  skip,
  failed,
}

/// The iOS player's display layer and its picture-in-picture window.
class IosVideoLayer {
  IosVideoLayer._();

  static const _channel = MethodChannel('com.alexmercerind/media_kit_video');

  /// The handle of the player whose layer was made last.
  static int? current;

  /// Called for what the picture-in-picture window does: the event, the
  /// seconds of a skip, and an error's text for [IosPipEvent.failed].
  static void Function(IosPipEvent event, double? seconds, String? error)? onEvent;

  /// Whether picture in picture is open now.
  static final ValueNotifier<bool> active = ValueNotifier(false);

  static bool get available => Platform.isIOS && current != null;

  static Map<String, Object?> _args([Map<String, Object?> more = const {}]) => {'handle': current.toString(), ...more};

  /// Where playback is: the window's progress bar and its play button show
  /// it.
  static Future<void> update({required Duration position, required Duration duration, required bool playing, required double rate, required bool live}) async {
    if (!available) return;
    await _channel.invokeMethod('Layer.Update', _args({
      'position': position.inMilliseconds / 1000,
      'duration': duration.inMilliseconds / 1000,
      'playing': playing,
      'rate': rate,
      'live': live,
    }));
  }

  /// Opens picture in picture; false when this device or the moment can't.
  static Future<bool> start() async => available && (await _channel.invokeMethod<bool>('Layer.StartPip', _args()) ?? false);

  static Future<void> stop() async {
    if (available) await _channel.invokeMethod('Layer.StopPip', _args());
  }

  /// Whether going to the Home Screen while the video plays opens picture
  /// in picture.
  static Future<void> setAuto(bool on) async {
    if (available) await _channel.invokeMethod('Layer.AutoPip', _args({'on': on}));
  }

  static int _warmth = 0xFFFFFFFF;

  /// The eye-care warm light over the picture, as the colour white becomes
  /// (opaque white: none). It is multiplied into the picture by Core
  /// Animation above the layer: Flutter draws over the platform view and
  /// has nothing of the picture to multiply. Picture in picture shows the
  /// layer alone, unwarmed.
  static Future<void> setWarmth(int argb) async {
    if (!available || argb == _warmth) return;
    _warmth = argb;
    await _channel.invokeMethod('Layer.Warmth', _args({'argb': argb}));
  }

  static Future<bool> supported() async => available && (await _channel.invokeMethod<bool>('Layer.PipSupported', _args()) ?? false);

  static final _byName = {for (final e in IosPipEvent.values) e.name: e};

  /// From the native side, through NativeVideoController's channel handler.
  static void handleEvent(int handle, String event, double? seconds) {
    if (handle != current) return;
    final failed = event.startsWith('failed:');
    final kind = failed ? IosPipEvent.failed : _byName[event];
    if (kind == null) return;
    if (kind == IosPipEvent.willStart || kind == IosPipEvent.started) {
      active.value = true;
    } else if (kind == IosPipEvent.stopped || kind == IosPipEvent.failed) {
      active.value = false;
    }
    onEvent?.call(kind, seconds, failed ? event.substring('failed:'.length) : null);
  }
}
