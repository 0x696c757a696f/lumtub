import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What kind of device Lumtub runs on, beyond the operating system.
class Device {
  Device._();

  /// A TV, Android TV or another Android TV box: no touch screen, a remote.
  static bool tv = false;

  /// Asks the Android side once, before the first frame.
  static Future<void> load() async {
    if (!Platform.isAndroid) return;
    try {
      tv = await const MethodChannel('lumtub/windows_shell').invokeMethod<bool>('isTv') ?? false;
    } catch (_) {}
  }

  /// On a TV something must hold focus for the remote's arrows to move:
  /// the first control, once the first page is shown.
  static void focusFirstOnTv() {
    if (!tv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final focus = FocusManager.instance.primaryFocus;
      if (focus == null || focus == FocusManager.instance.rootScope || focus is FocusScopeNode) {
        FocusManager.instance.rootScope.nextFocus();
      }
    });
  }
}
