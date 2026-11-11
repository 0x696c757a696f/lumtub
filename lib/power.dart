import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Whether the computer runs on battery (or, on Windows, with battery saver
/// on), when Lumtub does less in the background and draws the picture the
/// cheap way.
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
    if (Platform.isLinux) return _readLinux();
    if (Platform.isMacOS) return _readMac();
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

  /// Linux: a battery discharging, read from /sys/class/power_supply.
  static bool _readLinux() {
    try {
      final supplies = Directory('/sys/class/power_supply').listSync();
      return supplies.any((supply) => linuxSupplySaving(_readOr('${supply.path}/type'), _readOr('${supply.path}/status'), _readOr('${supply.path}/scope')));
    } catch (_) {
      return false;
    }
  }

  /// A system battery (not a mouse's or a phone's) that is discharging.
  static bool linuxSupplySaving(String type, String status, String scope) =>
      type.trim() == 'Battery' && status.trim() == 'Discharging' && scope.trim() != 'Device';

  static String _readOr(String path) {
    try {
      return File(path).readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  static bool _onBatteryMac = false;
  static bool _askingMac = false;

  /// macOS: pmset says where the power comes from. It is asked in the
  /// background, not waited for on the UI thread; until it answers, the
  /// answer before stands.
  static bool _readMac() {
    if (!_askingMac) {
      _askingMac = true;
      Process.run('pmset', ['-g', 'batt']).then((result) {
        _onBatteryMac = result.exitCode == 0 && result.stdout.toString().contains("'Battery Power'");
        _last = (DateTime.now(), _onBatteryMac);
      }, onError: (Object _) {}).whenComplete(() => _askingMac = false);
    }
    return _onBatteryMac;
  }
}
