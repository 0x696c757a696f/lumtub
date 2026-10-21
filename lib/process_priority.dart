import 'dart:ffi';
import 'dart:io';

/// Lowers a helper process to below-normal priority so that yt-dlp parsing
/// pages in the background never competes with the interface or playback.
/// Does nothing off Windows or when the process has already ended.
void lowerPriority(int pid) {
  if (!Platform.isWindows) return;
  try {
    final handle = _openProcess(_processSetInformation, 0, pid);
    if (handle == nullptr) return;
    _setPriorityClass(handle, _belowNormalPriorityClass);
    _closeHandle(handle);
  } catch (_) {}
}

const _processSetInformation = 0x0200;
const _belowNormalPriorityClass = 0x00004000;

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _openProcess = _kernel32.lookupFunction<Pointer<Void> Function(Uint32, Int32, Uint32), Pointer<Void> Function(int, int, int)>('OpenProcess');
final _setPriorityClass = _kernel32.lookupFunction<Int32 Function(Pointer<Void>, Uint32), int Function(Pointer<Void>, int)>('SetPriorityClass');
final _closeHandle = _kernel32.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('CloseHandle');
