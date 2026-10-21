import 'dart:ffi';
import 'dart:io';

/// Hands memory the process has freed back to Windows.
///
/// libmpv frees a closed video's cache and frames, but the C heap keeps the
/// freed pages committed for reuse, so Task Manager still shows them.
/// Compacting every heap decommits the free pages. Nothing in use is touched,
/// so nothing has to be paged back in afterwards. Does nothing off Windows.
void releaseFreedMemory() {
  if (!Platform.isWindows) return;
  try {
    final count = _getProcessHeaps(0, nullptr);
    if (count <= 0) return;
    final heaps = _alloc(count);
    try {
      final got = _getProcessHeaps(count, heaps);
      for (var i = 0; i < got && i < count; i++) {
        _heapCompact(heaps[i], 0);
      }
    } finally {
      _free(heaps);
    }
  } catch (_) {}
}

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _getProcessHeaps = _kernel32.lookupFunction<Uint32 Function(Uint32, Pointer<Pointer<Void>>), int Function(int, Pointer<Pointer<Void>>)>('GetProcessHeaps');
final _heapCompact = _kernel32.lookupFunction<IntPtr Function(Pointer<Void>, Uint32), int Function(Pointer<Void>, int)>('HeapCompact');
final _getProcessHeap = _kernel32.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('GetProcessHeap');
final _heapAlloc = _kernel32.lookupFunction<Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr), Pointer<Void> Function(Pointer<Void>, int, int)>('HeapAlloc');
final _heapFree = _kernel32.lookupFunction<Int32 Function(Pointer<Void>, Uint32, Pointer<Void>), int Function(Pointer<Void>, int, Pointer<Void>)>('HeapFree');

Pointer<Pointer<Void>> _alloc(int count) => _heapAlloc(_getProcessHeap(), 0, count * sizeOf<Pointer<Void>>()).cast();
void _free(Pointer<Pointer<Void>> p) => _heapFree(_getProcessHeap(), 0, p.cast());
