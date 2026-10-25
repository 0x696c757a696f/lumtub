import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/native_core.dart';

void main() {
  test('hashes a file on another isolate', () async {
    final dir = await Directory.systemTemp.createTemp('lumtub_hash');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}abc 中文.txt');
    await file.writeAsString('abc');
    final path = file.path;
    expect(await Isolate.run(() => NativeCore.fileSha256Of(path)), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(NativeCore.fileSha256Of('${dir.path}${Platform.pathSeparator}missing'), isNull);
  }, skip: NativeCore.instance == null ? 'needs lumtub_core (LUMTUB_CORE_DLL)' : null);
}
