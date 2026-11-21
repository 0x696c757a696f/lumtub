import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// This computer, as the license server counts it: the system's own
/// machine id, hashed so the id itself never leaves the computer, or a
/// random one kept in [data] where the system has none to read. 32 hex
/// digits.
Future<String> learningDeviceId(Directory data) async {
  var raw = '';
  try {
    if (Platform.isWindows) {
      final result = await Process.run('reg', ['query', r'HKLM\SOFTWARE\Microsoft\Cryptography', '/v', 'MachineGuid']).timeout(const Duration(seconds: 5));
      raw = RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)').firstMatch('${result.stdout}')?.group(1) ?? '';
    } else if (Platform.isLinux) {
      for (final path in ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
        final file = File(path);
        if (await file.exists()) {
          raw = (await file.readAsString()).trim();
          if (raw.isNotEmpty) break;
        }
      }
    } else if (Platform.isMacOS) {
      final result = await Process.run('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']).timeout(const Duration(seconds: 5));
      raw = RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"').firstMatch('${result.stdout}')?.group(1) ?? '';
    }
  } catch (_) {
    raw = '';
  }
  if (raw.isEmpty) {
    final file = File('${data.path}${Platform.pathSeparator}device-id');
    try {
      if (await file.exists()) raw = (await file.readAsString()).trim();
    } catch (_) {}
    if (raw.isEmpty) {
      final random = Random.secure();
      raw = [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
      try {
        await file.writeAsString(raw, flush: true);
      } catch (_) {}
    }
  }
  return sha256.convert(utf8.encode('lumtub-device-v1:$raw')).toString().substring(0, 32);
}

/// What the device list shows for this computer: the system only, never
/// its name, which often carries the owner's.
String learningDeviceLabel() => switch (Platform.operatingSystem) {
      'windows' => 'Windows',
      'macos' => 'macOS',
      'linux' => 'Linux',
      'android' => 'Android',
      'ios' => 'iOS',
      final other => other,
    };
