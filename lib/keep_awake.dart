import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps the display on while a video plays, through Windows'
/// SetThreadExecutionState; on Linux and macOS the runner holds off the
/// screen saver (linux_shell.cc, MacShell.swift). The setting belongs to the calling thread (the
/// UI thread, where every call here comes from) and several players can
/// ask at once, such as the page and its fullscreen copy, so the display is
/// released only when the last one lets go.
class KeepAwake {
  KeepAwake._();

  static const _continuous = 0x80000000, _displayRequired = 0x2;
  static final _holders = <Object>{};

  /// Replaced in tests.
  static void Function(int flags)? apply = _systemApply;

  static final _setThreadExecutionState =
      Platform.isWindows ? DynamicLibrary.open('kernel32.dll').lookupFunction<Uint32 Function(Uint32), int Function(int)>('SetThreadExecutionState') : null;

  static bool? _shellAwake;

  static void _systemApply(int flags) {
    if (Platform.isWindows) {
      _setThreadExecutionState?.call(flags);
      return;
    }
    final awake = flags & _displayRequired != 0;
    if (awake == _shellAwake) return;
    _shellAwake = awake;
    const MethodChannel('lumtub/windows_shell').invokeMethod<void>('setKeepAwake', awake).catchError((Object _) {});
  }

  static bool _hidden = false;

  /// Whether the window is minimised: nobody watches the display then, so
  /// it may turn off even while a video plays on as sound.
  static set hidden(bool value) {
    if (value == _hidden) return;
    _hidden = value;
    _apply();
  }

  /// Whether [holder] wants the display kept on from now on.
  static void hold(Object holder, bool awake) {
    final changed = awake ? _holders.add(holder) : _holders.remove(holder);
    if (changed) _apply();
  }

  static void _apply() => apply?.call(_holders.isEmpty || _hidden ? _continuous : _continuous | _displayRequired);
}
