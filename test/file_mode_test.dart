import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/file_mode.dart';

void main() {
  test('sets permission bits without starting chmod', () async {
    final folder = await Directory.systemTemp.createTemp('lumtub_mode');
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}/secret.bin')..writeAsStringSync('x');
    setFileMode(file.path, ownerOnlyMode);
    if (Platform.isWindows) return;
    expect(file.statSync().mode & 0x1FF, ownerOnlyMode);
    makeExecutable(file.path);
    expect(file.statSync().mode & 0x1FF, 0x1C9);
    setFileMode(file.path, executableMode);
    expect(file.statSync().mode & 0x1FF, executableMode);
    expect(() => setFileMode('${folder.path}/missing', ownerOnlyMode), throwsA(isA<FileSystemException>()));
  });
}
