import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// The main window's always-on-top state and the small picture-in-picture
/// window, through user32 directly: Flutter's Windows embedder has no API
/// for either, and a plugin for two calls is more than they need.
class AppWindow {
  AppWindow._();

  static final _user32 = Platform.isWindows ? DynamicLibrary.open('user32.dll') : null;
  static final _kernel32 = Platform.isWindows ? DynamicLibrary.open('kernel32.dll') : null;

  static final _findWindowEx = _user32?.lookupFunction<IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>), int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)>('FindWindowExW');
  static final _getWindowThreadProcessId = _user32?.lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>), int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
  static final _getCurrentProcessId = _kernel32?.lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');
  static final _setWindowPos = _user32?.lookupFunction<Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32), int Function(int, int, int, int, int, int, int)>('SetWindowPos');
  static final _getWindowRect = _user32?.lookupFunction<Int32 Function(IntPtr, Pointer<_Rect>), int Function(int, Pointer<_Rect>)>('GetWindowRect');
  static final _isZoomed = _user32?.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsZoomed');
  static final _showWindow = _user32?.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
  static final _monitorFromWindow = _user32?.lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>('MonitorFromWindow');
  static final _getMonitorInfo = _user32?.lookupFunction<Int32 Function(IntPtr, Pointer<_MonitorInfo>), int Function(int, Pointer<_MonitorInfo>)>('GetMonitorInfoW');
  static final _getDpiForWindow = _user32?.lookupFunction<Uint32 Function(IntPtr), int Function(int)>('GetDpiForWindow');
  static final _setProp = _user32?.lookupFunction<Int32 Function(IntPtr, Pointer<Utf16>, IntPtr), int Function(int, Pointer<Utf16>, int)>('SetPropW');
  static final _removeProp = _user32?.lookupFunction<IntPtr Function(IntPtr, Pointer<Utf16>), int Function(int, Pointer<Utf16>)>('RemovePropW');

  static const _topmost = -1, _notTopmost = -2;
  static const _noSize = 0x1, _noMove = 0x2, _noActivate = 0x10;
  static const _restore = 9, _maximize = 3;

  static int? _handle;

  /// YTPlus's own top-level window: the runner's window class in this
  /// process, so a second copy of the app is never moved.
  static int? get handle {
    if (_handle != null || _user32 == null) return _handle;
    final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final pid = calloc<Uint32>();
    try {
      final own = _getCurrentProcessId!();
      var window = 0;
      while ((window = _findWindowEx!(0, window, className, nullptr)) != 0) {
        _getWindowThreadProcessId!(window, pid);
        if (pid.value == own) return _handle = window;
      }
      return null;
    } finally {
      calloc.free(className);
      calloc.free(pid);
    }
  }

  /// Keeps the window above the others, or lets it go back among them.
  static bool setTopmost(bool on) {
    final window = handle;
    if (window == null) return false;
    return _setWindowPos!(window, on ? _topmost : _notTopmost, 0, 0, 0, 0, _noMove | _noSize | _noActivate) != 0;
  }

  static ({int left, int top, int width, int height, bool maximized})? _before;

  /// Shrinks the window to a 16:9 picture of [width] logical pixels in the
  /// bottom-right corner of its monitor's work area, above other windows.
  static bool enterPip({int width = 480}) {
    final window = handle;
    if (window == null) return false;
    final rect = calloc<_Rect>();
    final monitor = calloc<_MonitorInfo>()..ref.size = sizeOf<_MonitorInfo>();
    final name = _pipProperty.toNativeUtf16();
    try {
      final maximized = _isZoomed!(window) != 0;
      if (maximized) _showWindow!(window, _restore);
      if (_getWindowRect!(window, rect) == 0) return false;
      _before ??= (left: rect.ref.left, top: rect.ref.top, width: rect.ref.right - rect.ref.left, height: rect.ref.bottom - rect.ref.top, maximized: maximized);
      if (_getMonitorInfo!(_monitorFromWindow!(window, 2), monitor) == 0) return false;
      final scale = (_getDpiForWindow!(window) == 0 ? 96 : _getDpiForWindow!(window)) / 96;
      final w = (width * scale).round();
      // The caption bar stays, so the window can still be moved and sized.
      final h = (width * 9 / 16 * scale + 32 * scale).round();
      final margin = (16 * scale).round();
      final area = monitor.ref.work;
      // Window placement is not saved while this marker is on, so the next
      // launch opens at the usual size.
      _setProp!(window, name, 1);
      return _setWindowPos!(window, _topmost, area.right - w - margin, area.bottom - h - margin, w, h, 0) != 0;
    } finally {
      calloc.free(rect);
      calloc.free(monitor);
      calloc.free(name);
    }
  }

  /// Puts the window back where and how it was before [enterPip].
  static bool exitPip({bool keepOnTop = false}) {
    final window = handle;
    final before = _before;
    if (window == null || before == null) return false;
    _before = null;
    final name = _pipProperty.toNativeUtf16();
    try {
      _removeProp!(window, name);
    } finally {
      calloc.free(name);
    }
    final ok = _setWindowPos!(window, keepOnTop ? _topmost : _notTopmost, before.left, before.top, before.width, before.height, 0) != 0;
    if (before.maximized) _showWindow!(window, _maximize);
    return ok;
  }

  /// Read by the runner's window_placement.cpp; keep the two in step.
  static const _pipProperty = 'YTPlusPictureInPicture';
}

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

final class _MonitorInfo extends Struct {
  @Uint32()
  external int size;
  external _Rect monitor;
  external _Rect work;
  @Uint32()
  external int flags;
}
