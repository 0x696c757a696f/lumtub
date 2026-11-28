import 'dart:ffi';
import 'dart:io';
import 'app_log.dart';

/// Hands memory the process has freed back to the system.
///
/// libmpv frees a closed video's cache and frames, but the C heap keeps the
/// freed pages committed for reuse, so Task Manager still shows them.
/// Compacting the process heap, where the C runtime's malloc of Lumtub,
/// libmpv and the core lives, decommits the free pages. Nothing in use is
/// touched, so nothing has to be paged back in afterwards. On Linux glibc's
/// malloc_trim and on macOS malloc_zone_pressure_relief do the same.
///
/// Only the process heap: the other heaps belong to system DLLs and drivers,
/// some of which may not be compacted or go away meanwhile. Compacting one
/// of those faulted inside a window message, which Windows answers by
/// ending the process at once (0.2.50).
void releaseFreedMemory() {
  if (Platform.isLinux || Platform.isMacOS) return _releaseUnix();
  if (!Platform.isWindows) return;
  try {
    _heapCompact(_getProcessHeap(), 0);
  } catch (e) {
    logDebug(() => 'Heap trimming failed: $e');
  }
}

void _releaseUnix() {
  try {
    final process = DynamicLibrary.process();
    if (Platform.isMacOS) {
      process.lookupFunction<Size Function(Pointer<Void>, Size), int Function(Pointer<Void>, int)>(
          'malloc_zone_pressure_relief')(nullptr, 0);
    } else {
      // Absent outside glibc, as on musl.
      process.lookupFunction<Int32 Function(Size), int Function(int)>('malloc_trim')(0);
    }
  } catch (e) {
    logDebug(() => 'malloc_trim is not available: $e');
  }
}

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _heapCompact = _kernel32.lookupFunction<IntPtr Function(Pointer<Void>, Uint32),
    int Function(Pointer<Void>, int)>('HeapCompact');
final _getProcessHeap =
    _kernel32.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('GetProcessHeap');
