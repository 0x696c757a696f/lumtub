import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Whether Windows runs on battery or with battery saver on, when Lumtub
/// does less in the background and draws the picture the cheap way.
abstract final class Power {
  static final _getSystemPowerStatus = Platform.isWindows
      ? DynamicLibrary.open('kernel32.dll').lookupFunction<Int32 Function(Pointer<Uint8>), int Function(Pointer<Uint8>)>('GetSystemPowerStatus')
      : null;

  static (DateTime, bool)? _last;

  /// Read at most every 30 seconds; false where it cannot be asked.
  static bool get saving {
    final last = _last;
    if (last != null && DateTime.now().difference(last.$1) < const Duration(seconds: 30)) return last.$2;
    final value = _read();
    _last = (DateTime.now(), value);
    return value;
  }

  static bool _read() {
    final call = _getSystemPowerStatus;
    if (call == null) return false;
    // SYSTEM_POWER_STATUS: ACLineStatus, BatteryFlag, BatteryLifePercent,
    // SystemStatusFlag, then two DWORDs.
    final status = calloc<Uint8>(12);
    try {
      if (call(status) == 0) return false;
      return savingOf(acLine: status[0], systemStatus: status[3]);
    } finally {
      calloc.free(status);
    }
  }

  /// On battery (AC line 0) or with battery saver on (system status 1).
  static bool savingOf({required int acLine, required int systemStatus}) => acLine == 0 || systemStatus == 1;
}
