import 'dart:ffi';
import 'dart:io';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';

import '../appearance_settings.dart';

/// Motion that settles into place: one curve, a short time for colour and
/// opacity, a longer one for size and position.
abstract final class Ease {
  static const curve = Cubic(0.22, 1, 0.36, 1);
  static const fade = Duration(milliseconds: 200);
  static const move = Duration(milliseconds: 320);
}

/// 减少动画 for the whole app: page changes, expanding sections and hover
/// effects finish at once. Animations that carry meaning while waiting,
/// such as progress indicators, keep running.
abstract final class Motion {
  static bool reduced = false;

  /// Applies [preference]; for [MotionPreference.system], Windows' “Show
  /// animations in Windows” setting, or the platform's reduce-motion one.
  static void update(MotionPreference preference) {
    reduced = switch (preference) {
      MotionPreference.reduced => true,
      MotionPreference.full => false,
      MotionPreference.system => systemPrefersReduced(),
    };
  }

  /// [duration], or none when animations are reduced.
  static Duration of(Duration duration) => reduced ? Duration.zero : duration;

  /// Scrolls [controller] to [offset], with a short animation unless
  /// animations are reduced.
  static Future<void> scrollTo(ScrollController controller, double offset, {Duration duration = const Duration(milliseconds: 220), Curve curve = Ease.curve}) async {
    if (reduced) return controller.jumpTo(offset);
    return controller.animateTo(offset, duration: duration, curve: curve);
  }

  static final _systemParametersInfo = Platform.isWindows
      ? DynamicLibrary.open('user32.dll').lookupFunction<Int32 Function(Uint32, Uint32, Pointer<Int32>, Uint32), int Function(int, int, Pointer<Int32>, int)>('SystemParametersInfoW')
      : null;
  static const _spiGetClientAreaAnimation = 0x1042;

  static bool systemPrefersReduced() {
    final call = _systemParametersInfo;
    if (call != null) {
      final value = calloc<Int32>();
      try {
        if (call(_spiGetClientAreaAnimation, 0, value, 0) != 0) return value.value == 0;
      } finally {
        calloc.free(value);
      }
    }
    return PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;
  }
}
