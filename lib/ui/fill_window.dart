import 'dart:async';

import 'package:media_kit_video/media_kit_video.dart';

import '../window_frame.dart';

import 'motion.dart';
import 'theater_mode.dart';
import 'window_chrome.dart';

/// Lets the video fill the window, or brings the page back; from
/// fullscreen it leaves fullscreen.
Future<void> toggleFillWindow(VideoState? state) async {
  if (state == null) return;
  if (state.isFullscreen()) return state.exitFullscreen();
  // The window stays as it is, so the video can grow into it smoothly;
  // real fullscreen still cuts, as the screen mode changes under it.
  fullscreenTransition = () => fillingWindow.value ? Motion.of(Ease.move) : Duration.zero;
  fillingWindow.value = true;
  await state.enterFullscreen();
}

/// Fullscreen or out of it; while the video fills the window, it goes on
/// to fullscreen rather than back to the page.
Future<void> toggleFullscreenFrom(VideoState? state) async {
  if (state == null) return;
  // Left behind if the view closed some other way.
  if (!state.isFullscreen()) fillingWindow.value = false;
  if (fillingWindow.value) {
    fillingWindow.value = false;
    WindowChrome.fullscreen.value = true;
    return defaultEnterNativeFullscreen();
  }
  return state.toggleFullscreen();
}

/// While the video fills the window, the window takes the video's shape
/// and keeps it as it is resized; leaving gives the window back its size.
/// The player reports the shape of the picture it shows as [aspect].
abstract final class VideoShapedWindow {
  static double _aspect = 0;
  static double _sent = 0;
  static bool _listening = false;

  /// The picture's width over height; 0 when not known yet.
  static set aspect(double value) {
    _aspect = value.isFinite && value > 0 ? value : 0;
    if (!_listening) {
      _listening = true;
      fillingWindow.addListener(_apply);
      WindowChrome.fullscreen.addListener(_apply);
    }
    _apply();
  }

  static void _apply() {
    final on = WindowFrame.supported && fillingWindow.value && !WindowChrome.fullscreen.value;
    final next = on ? _aspect : 0.0;
    if ((next - _sent).abs() < 0.001) return;
    _sent = next;
    unawaited(WindowFrame.keepVideoShape(next));
  }
}
