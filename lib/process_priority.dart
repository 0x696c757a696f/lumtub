import 'dart:ffi';
import 'dart:io';
import 'app_log.dart';

/// Lowers a helper process to below-normal priority so that yt-dlp parsing
/// pages in the background never competes with the interface or playback.
/// Does nothing when the process has already ended. On Linux and macOS it
/// is a nice value of 5, which the processes it starts inherit.
void lowerPriority(int pid) {
  if (Platform.isWindows) return _setPriority(pid, _belowNormalPriorityClass);
  try {
    _setPriorityUnix(_prioProcess, pid, 5);
  } catch (e) {
    logDebug(() => 'Could not lower the process priority: $e');
  }
}

/// Puts a process lowered with [lowerPriority] back to normal, for example
/// once the user is waiting on it. Windows only: elsewhere only root may
/// raise a priority again, and a nice value of 5 is a mild one.
void restorePriority(int pid) => _setPriority(pid, _normalPriorityClass);

const _prioProcess = 0;
final _setPriorityUnix = DynamicLibrary.process().lookupFunction<Int32 Function(Int32, Uint32, Int32), int Function(int, int, int)>('setpriority');

void _setPriority(int pid, int priorityClass) {
  if (!Platform.isWindows) return;
  try {
    final handle = _openProcess(_processSetInformation, 0, pid);
    if (handle == nullptr) return;
    _setPriorityClass(handle, priorityClass);
    _closeHandle(handle);
  } catch (e) {
    logDebug(() => 'Could not lower the process priority: $e');
  }
}

const _processSetInformation = 0x0200;
const _belowNormalPriorityClass = 0x00004000;
const _normalPriorityClass = 0x00000020;

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _openProcess = _kernel32.lookupFunction<Pointer<Void> Function(Uint32, Int32, Uint32), Pointer<Void> Function(int, int, int)>('OpenProcess');
final _setPriorityClass = _kernel32.lookupFunction<Int32 Function(Pointer<Void>, Uint32), int Function(Pointer<Void>, int)>('SetPriorityClass');
final _closeHandle = _kernel32.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('CloseHandle');
