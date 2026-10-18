import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/app_directories.dart';

void main() {
  test('creates the complete application directory tree without deleting data', () async {
    final root = await Directory.systemTemp.createTemp('ytplus-directories-test-');
    addTearDown(() => root.delete(recursive: true));
    final directories = AppDirectories.at(Directory('${root.path}${Platform.pathSeparator}YTPlus'));

    await directories.ensureExists();
    final keep = File('${directories.data.path}${Platform.pathSeparator}keep.json');
    await keep.writeAsString('{"keep":true}');
    await directories.ensureExists();

    expect(await directories.config.exists(), isTrue);
    expect(await directories.data.exists(), isTrue);
    expect(await directories.cache.exists(), isTrue);
    expect(await directories.components.exists(), isTrue);
    expect(await directories.logs.exists(), isTrue);
    expect(await keep.readAsString(), '{"keep":true}');
  });
}
