import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'app_log.dart';

/// The device's memory, which sets how much Lumtub keeps in memory: iOS
/// and Android end an app in the background sooner on a device with less.
class DeviceMemory {
  DeviceMemory._();

  /// The memory the device has, in MiB; 0 when it could not be read.
  static final int totalMb = _read();

  /// A phone, tablet or TV with 3 GB or less (iPhone 8, X, XR, SE 2 and
  /// older; Android Go and low-end TVs): caches stay at their smallest.
  static bool get low => totalMb > 0 && totalMb <= 3 * 1024 + 256;

  static int _read() {
    try {
      if (Platform.isIOS || Platform.isMacOS) return _sysctl('hw.memsize') >> 20;
      if (Platform.isAndroid || Platform.isLinux) {
        final line = File('/proc/meminfo').readAsLinesSync().firstWhere((l) => l.startsWith('MemTotal:'), orElse: () => '');
        final kb = int.tryParse(RegExp(r'\d+').firstMatch(line)?.group(0) ?? '') ?? 0;
        return kb >> 10;
      }
    } catch (e) {
      logWarn('Could not read the device memory: $e');
    }
    return 0;
  }

  static int _sysctl(String name) {
    final sysctlbyname = DynamicLibrary.process().lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Uint64>, Pointer<Size>, Pointer<Void>, Size),
        int Function(Pointer<Utf8>, Pointer<Uint64>, Pointer<Size>, Pointer<Void>, int)>('sysctlbyname');
    final key = name.toNativeUtf8();
    final value = calloc<Uint64>();
    final size = calloc<Size>()..value = sizeOf<Uint64>();
    try {
      return sysctlbyname(key, value, size, nullptr, 0) == 0 ? value.value : 0;
    } finally {
      calloc.free(key);
      calloc.free(value);
      calloc.free(size);
    }
  }
}
