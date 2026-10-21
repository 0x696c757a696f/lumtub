import 'dart:ffi';
import 'dart:io';

/// Keeps the display on while a video plays, through Windows'
/// SetThreadExecutionState. The setting belongs to the calling thread (the
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

  static void _systemApply(int flags) => _setThreadExecutionState?.call(flags);

  /// Whether [holder] wants the display kept on from now on.
  static void hold(Object holder, bool awake) {
    final changed = awake ? _holders.add(holder) : _holders.remove(holder);
    if (!changed) return;
    apply?.call(_holders.isEmpty ? _continuous : _continuous | _displayRequired);
  }
}
