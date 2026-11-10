part of 'app_controller.dart';

/// The mini player, picture in picture and the window mode.
extension WindowActions on AppController {
  /// Turns on X11 compatibility mode and starts Lumtub again in it.
  Future<void> switchToX11() async {
    final data = directories?.data;
    if (data == null) return;
    try {
      await AppWindow.x11Marker(data).writeAsString('');
    } catch (e) {
      _notice(tr('Could not switch: {0}', ['$e']));
      return;
    }
    await restart();
  }

  /// Saves everything still waiting to be written, then starts Lumtub again.
  Future<void> restart() async {
    await shutdown(install: false);
    await restartApp();
  }

  /// Shows [playing] on the watch page again, where it was.
  void expandMini() {
    if (mini) _update(() => mini = false);
  }

  /// Puts the video on the watch page into the mini player (the 应用内小窗
  /// button), over the page it was opened from.
  void enterMini() {
    if (playing == null || mini || player == null) return;
    setPip(false);
    _saveProgress(now: true);
    _update(() => mini = true);
  }

  void setPip(bool on) {
    if (on == pip) return;
    final ok = on ? AppWindow.enterPip(aspect: videoAspect) : AppWindow.exitPip(keepOnTop: pinned);
    if (on && !ok) return _notice(tr('Could not open picture in picture'));
    _update(() => pip = on);
    if (on) _noteWaylandTop();
  }

  /// Android began or ended picture in picture itself.
  void pipChangedBySystem(bool on) {
    AppWindow.pipChangedBySystem(on);
    if (on != pip) _update(() => pip = on);
  }

  /// The next video may have another ratio: the picture-in-picture window
  /// follows it.
  void updatePipAspect() {
    if (pip) AppWindow.setPipAspect(videoAspect);
  }
}
