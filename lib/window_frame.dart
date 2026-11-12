import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'app_log.dart';

/// Which edge or corner of the window a resize starts from.
enum WindowEdge { top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight }

/// The maximize button as Windows sees it, so Flutter can draw it.
enum WindowButtonState { none, hover, pressed }

/// The app draws its own title bar when [custom] is on. The runners answer
/// on their own channel: the shell's one already has a Dart handler.
abstract final class WindowFrame {
  static const channelName = 'lumtub/window_frame';
  static const _channel = MethodChannel(channelName);

  static final _maximized = ValueNotifier<bool>(false);
  static final _active = ValueNotifier<bool>(true);
  static final _maximizeButton = ValueNotifier<WindowButtonState>(WindowButtonState.none);
  static bool _listening = false;
  static bool _custom = false;

  /// Windows, Linux (X11 and Wayland) and macOS.
  static bool get supported => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Whether the system title bar is currently removed.
  static bool get custom => _custom;

  /// Removes or restores the system title bar; resize edges, shadow and
  /// snapping stay.
  static Future<void> setCustom(bool on) async {
    if (!supported) return;
    _listen();
    _custom = on;
    await _invoke('setCustom', on);
    // The client area just changed under the title bar: what it reported
    // goes out again from the next frame, whatever the runner holds.
    _lastCaption = null;
    SchedulerBinding.instance.scheduleFrame();
    await _refresh();
  }

  static Future<void> minimize() => _invoke('minimize');

  static Future<void> toggleMaximize() => _invoke('toggleMaximize');

  /// Goes through the normal close path, so the exit request and
  /// close-to-tray still apply.
  static Future<void> close() => _invoke('close');

  /// Call on pointer down in the title bar. Windows moves the window by
  /// hit-testing instead, so there it does nothing.
  static Future<void> startDrag() => _invoke('startDrag');

  /// For undecorated Linux windows, whose edges Flutter draws.
  static Future<void> startResize(WindowEdge edge) => _invoke('startResize', edge.name);

  static ValueListenable<bool> get maximized {
    _listen();
    return _maximized;
  }

  /// False while another window has the focus.
  static ValueListenable<bool> get active {
    _listen();
    return _active;
  }

  /// Windows 11 snap layouts: the maximize rect is HTMAXBUTTON, so Windows
  /// owns its mouse input; the runner reports hover and press here and
  /// maximizes on a click.
  static ValueListenable<WindowButtonState> get maximizeButton {
    _listen();
    return _maximizeButton;
  }

  static ({double height, List<double>? maximize, List<List<double>> interactive})? _lastCaption;

  /// Lets tests see the caption reports Windows gets.
  @visibleForTesting
  static bool debugCaptions = false;

  /// Whether the runner takes caption reports (Windows only).
  static bool get reportsCaption => Platform.isWindows || debugCaptions;

  /// Windows hit-testing, in logical pixels: the title bar [height] (the
  /// caption: draggable, double-click maximizes, Aero snap works; 0 for
  /// none), the [maximizeButton] rect, and [interactive] rects inside the
  /// caption that stay clickable (menus, buttons, the search box). Call it
  /// whenever the layout changes.
  static void setCaption({required double height, Rect? maximizeButton, List<Rect> interactive = const []}) {
    if (!reportsCaption) return;
    final next = (height: height, maximize: maximizeButton == null ? null : rectToList(maximizeButton), interactive: interactive.map(rectToList).toList());
    final last = _lastCaption;
    if (last != null && last.height == next.height && listEquals(last.maximize, next.maximize) && _sameRects(last.interactive, next.interactive)) return;
    _lastCaption = next;
    _listen();
    _tryInvoke('setCaption', {'height': next.height, 'maximize': next.maximize, 'interactive': next.interactive}).then((taken) {
      // Not taken: the next report goes out again instead of being
      // skipped as already sent.
      if (!taken && identical(_lastCaption, next)) _lastCaption = null;
    });
  }

  /// A rect as the runner reads it: left, top, right, bottom.
  @visibleForTesting
  static List<double> rectToList(Rect rect) => [rect.left, rect.top, rect.right, rect.bottom];

  static bool _sameRects(List<List<double>> a, List<List<double>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!listEquals(a[i], b[i])) return false;
    }
    return true;
  }

  /// The state a Windows button report stands for (0, 1 or 2).
  @visibleForTesting
  static WindowButtonState buttonStateOf(Object? value) {
    final index = value is int ? value : 0;
    return WindowButtonState.values[index.clamp(0, WindowButtonState.values.length - 1)];
  }

  static Future<void> _invoke(String method, [Object? arguments]) => _tryInvoke(method, arguments);

  /// False when the runner did not take the call.
  static Future<bool> _tryInvoke(String method, [Object? arguments]) async {
    if (!supported) return false;
    try {
      await _channel.invokeMethod<void>(method, arguments);
      return true;
    } on MissingPluginException {
      // An older runner has no custom frame.
      return false;
    } on PlatformException {
      // Nothing to do for a window call that failed.
      return false;
    }
  }

  static void _listen() {
    if (_listening || !supported) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'maximized':
          _maximized.value = call.arguments == true;
        case 'active':
          _active.value = call.arguments == true;
        case 'maximizeButton':
          _maximizeButton.value = buttonStateOf(call.arguments);
        case 'captionClick':
          logInfo('Title bar click taken as the caption: ${call.arguments}, last report $_lastCaption');
      }
    });
    _refresh();
  }

  static Future<void> _refresh() async {
    try {
      final state = await _channel.invokeMapMethod<String, Object?>('state');
      if (state == null) return;
      _maximized.value = state['maximized'] == true;
      _active.value = state['active'] != false;
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
