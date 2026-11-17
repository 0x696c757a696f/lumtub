import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// rw------- (0600): readable and writable by the user alone.
const ownerOnlyMode = 0x180;

/// rwxr-xr-x (0755).
const executableMode = 0x1ED;

typedef _ChmodLinux = Int32 Function(Pointer<Utf8>, Uint32);
typedef _ChmodApple = Int32 Function(Pointer<Utf8>, Uint16);
typedef _ChmodDart = int Function(Pointer<Utf8>, int);

// mode_t is 16 bits on Apple's systems, 32 elsewhere.
final _ChmodDart _chmod = Platform.isMacOS || Platform.isIOS
    ? DynamicLibrary.process().lookupFunction<_ChmodApple, _ChmodDart>('chmod')
    : DynamicLibrary.process().lookupFunction<_ChmodLinux, _ChmodDart>('chmod');

/// Sets the permission bits of [path] to [mode] with the C library's chmod,
/// never the chmod program: iOS lets an app start no programs at all.
/// Does nothing on Windows.
void setFileMode(String path, int mode) {
  if (Platform.isWindows) return;
  final native = path.toNativeUtf8();
  try {
    if (_chmod(native, mode) != 0) throw FileSystemException('chmod failed', path);
  } finally {
    malloc.free(native);
  }
}

/// Adds the execute bits for everyone, like `chmod +x` with the usual
/// umask.
void makeExecutable(String path) {
  if (Platform.isWindows) return;
  setFileMode(path, (File(path).statSync().mode & 0xFFF) | 0x49);
}
