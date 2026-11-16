import 'package:media_kit_video/media_kit_video.dart';

import 'theater_mode.dart';
import 'window_chrome.dart';

/// Lets the video fill the window, or brings the page back; from
/// fullscreen it leaves fullscreen.
Future<void> toggleFillWindow(VideoState? state) async {
  if (state == null) return;
  if (state.isFullscreen()) return state.exitFullscreen();
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
