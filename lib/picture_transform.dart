import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Mirroring, rotating and zooming of the picture through libmpv
/// (`vf=hflip`, `video-rotate`, `video-zoom`). They belong to one video:
/// [reset] runs when the next one opens.
class PictureTransform extends ChangeNotifier {
  PictureTransform(this._player);
  final Player _player;

  /// Zoom steps in the 更多 menu.
  static const zoomLevels = [1.0, 1.25, 1.5, 2.0];

  /// Turns in the 更多 menu, clockwise in degrees.
  static const rotations = [0, 90, 180, 270];

  bool mirrored = false;
  int rotation = 0;
  double zoom = 1;

  bool get isDefault => !mirrored && rotation == 0 && zoom == 1;

  /// mpv's `video-zoom` is a power of two: 0 is the picture's own size.
  static double zoomProperty(double factor) => factor <= 1 ? 0 : log(factor) / ln2;

  Future<void> _set(String name, String value) async {
    final platform = _player.platform;
    if (platform is NativePlayer) await platform.setProperty(name, value);
  }

  Future<void> setMirrored(bool value) async {
    mirrored = value;
    notifyListeners();
    await _set('vf', value ? 'hflip' : '');
  }

  Future<void> setRotation(int degrees) async {
    rotation = degrees % 360;
    notifyListeners();
    await _set('video-rotate', '$rotation');
  }

  Future<void> setZoom(double factor) async {
    zoom = factor;
    notifyListeners();
    await _set('video-zoom', zoomProperty(factor).toString());
  }

  void reset() {
    if (isDefault) return;
    unawaited(setMirrored(false).catchError((_) {}));
    unawaited(setRotation(0).catchError((_) {}));
    unawaited(setZoom(1).catchError((_) {}));
  }
}
