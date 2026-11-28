import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// This installation, as the license server counts it: a random id made
/// once and kept in [data], hashed before it leaves the computer. Nothing
/// is read from the hardware or the system, so it says nothing about the
/// computer; a new installation is a new device, and the device list
/// lets the buyer free the old one. 32 hex digits.
Future<String> learningDeviceId(Directory data) async {
  final file = File('${data.path}${Platform.pathSeparator}device-id');
  var raw = '';
  try {
    if (await file.exists()) raw = (await file.readAsString()).trim();
  } catch (_) {}
  if (raw.isEmpty) {
    final random = Random.secure();
    raw =
        [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    try {
      await file.writeAsString(raw, flush: true);
    } catch (_) {}
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
