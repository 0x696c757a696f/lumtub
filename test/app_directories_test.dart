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

  test('uses the folder the runner chose, else LocalAppData', () async {
    final temp = await Directory.systemTemp.createTemp('ytplus_dirs');
    addTearDown(() => temp.delete(recursive: true));
    final sep = Platform.pathSeparator;
    final portable = await AppDirectories.create(environment: {'YTPLUS_HOME': '${temp.path}${sep}userdata', 'LOCALAPPDATA': '${temp.path}${sep}local'});
    expect(portable.logs.path, '${temp.path}${sep}userdata${sep}logs');
    expect(portable.logs.existsSync(), isTrue);
    final installed = await AppDirectories.create(environment: {'LOCALAPPDATA': '${temp.path}${sep}local'});
    expect(installed.root.path, '${temp.path}${sep}local${sep}YTPlus');
  });
}
