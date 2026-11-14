import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../device.dart';

/// Taps felt on a phone: a tick when a tab, a segment or a chip is picked,
/// a firmer knock when a long press opens a menu. Computers and TVs have
/// nothing to feel them with.
abstract final class Haptics {
  static bool get _felt => (Platform.isAndroid || Platform.isIOS) && !Device.tv;

  static void select() {
    if (_felt) unawaited(HapticFeedback.selectionClick());
  }

  static void menu() {
    if (_felt) unawaited(HapticFeedback.mediumImpact());
  }
}
