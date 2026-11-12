import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_log.dart';
import 'skins/skin.dart';

/// What kind of device Lumtub runs on, beyond the operating system.
class Device {
  Device._();

  /// A TV, Android TV or another Android TV box: no touch screen, a remote.
  static bool tv = false;

  /// Asks the Android side once, before the first frame.
  static Future<void> load() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (Platform.isAndroid) {
      try {
        tv = await const MethodChannel('lumtub/windows_shell').invokeMethod<bool>('isTv') ?? false;
      } catch (e) {
        logWarn('Could not ask whether this is a TV: $e');
      }
    }
    Skin.formFactor = tv ? 'tv' : tablet ? 'tablet' : 'mobile';
  }

  /// A screen whose shorter side is at least 600 logical pixels, as
  /// Android and iPadOS count tablets.
  static bool get tablet {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final view = views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return size.shortestSide >= 600;
  }

  /// On a TV something must hold focus for the remote's arrows to move:
  /// the first control, once the first page is shown.
  static void focusFirstOnTv() {
    if (!tv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final focus = FocusManager.instance.primaryFocus;
      if (focus == null || focus == FocusManager.instance.rootScope || focus is FocusScopeNode) {
        // The root scope has no context to find a traversal order in, so
        // take the first control that can hold focus, in tree order.
        FocusManager.instance.rootScope.traversalDescendants.where((node) => node.context?.mounted ?? false).firstOrNull?.requestFocus();
      }
    });
  }
}
