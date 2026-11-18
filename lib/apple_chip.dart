import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// What an iPhone's or iPad's chip can decode, read from its model name.
abstract final class AppleChip {
  static String? _model;

  /// The model name, such as `iPhone11,2`; empty off iOS or when unknown.
  static String get model => _model ??= Platform.isIOS ? _readModel() : '';

  static String _readModel() {
    try {
      final uname = DynamicLibrary.process().lookupFunction<Int32 Function(Pointer<Uint8>), int Function(Pointer<Uint8>)>('uname');
      // Darwin's struct utsname: five fields of 256 characters, the
      // machine last.
      final buffer = calloc<Uint8>(5 * 256);
      try {
        if (uname(buffer) != 0) return '';
        return (buffer + 4 * 256).cast<Utf8>().toDartString();
      } finally {
        calloc.free(buffer);
      }
    } catch (_) {
      return '';
    }
  }

  /// Whether the chip of [model] has a VP9 decoder: the A12 (iPhone XS and
  /// XR, iPhone11,x; iPad mini 5, iPad Air 3, iPad 8, iPad11,x; the 2018
  /// iPad Pro's A12X, iPad8,x) and every chip after it; Vision Pro
  /// (RealityDevice, M2 and later) runs the iPad app and has one too. Null
  /// when the name says nothing, as in the simulator.
  static bool? hasVp9(String model) {
    if (model.startsWith('RealityDevice')) return true;
    final match = RegExp(r'^(iPhone|iPad|iPod)(\d+),\d+$').firstMatch(model);
    if (match == null) return null;
    final major = int.parse(match.group(2)!);
    return switch (match.group(1)) {
      'iPhone' => major >= 11,
      'iPad' => major >= 8,
      _ => false,
    };
  }
}
