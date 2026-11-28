import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../native_core.dart';

/// Reads what a device on the local network sent with the Rust core
/// (cast_lan.rs), which answers in JSON. Throws [FormatException] when the
/// core is missing or cannot read it.
Object? readInCore(String symbol, List<int> bytes) {
  final core = NativeCore.instance;
  if (core == null || !core.library.providesSymbol(symbol)) {
    throw FormatException(NativeCore.missingMessage);
  }
  final call = _calls[symbol] ??= core.library.lookupFunction<
      Pointer<Utf8> Function(Pointer<Uint8>, Size),
      Pointer<Utf8> Function(Pointer<Uint8>, int)>(symbol);
  final text = core.take(core.withBytes(bytes, call));
  if (text == null) throw FormatException('No answer from $symbol');
  return jsonDecode(text);
}

/// [readInCore] for text.
Object? readTextInCore(String symbol, String text) => readInCore(symbol, utf8.encode(text));

final _calls = <String, Pointer<Utf8> Function(Pointer<Uint8>, int)>{};
