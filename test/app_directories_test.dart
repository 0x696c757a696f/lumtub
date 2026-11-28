import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_directories.dart';

void main() {
  test('creates the complete application directory tree without deleting data', () async {
    final root = await Directory.systemTemp.createTemp('lumtub-directories-test-');
    addTearDown(() => root.delete(recursive: true));
    final directories = AppDirectories.at(Directory('${root.path}${Platform.pathSeparator}Lumtub'));

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

  test('saves to one file overlapping keep the last and leave no temporary file', () async {
    final temp = await Directory.systemTemp.createTemp('lumtub_atomic');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}${Platform.pathSeparator}known.json');
    await Future.wait(
        [for (var i = 0; i < 20; i++) writeFileAtomic(file, '{"n":$i,"pad":"${'x' * 100000}"}')]);
    expect(await file.readAsString(), startsWith('{"n":19,'));
    expect(temp.listSync().map((e) => e.uri.pathSegments.last), ['known.json']);
  });

  test('uses the folder the runner chose, else LocalAppData', () async {
    final temp = await Directory.systemTemp.createTemp('lumtub_dirs');
    addTearDown(() => temp.delete(recursive: true));
    final sep = Platform.pathSeparator;
    final portable = await AppDirectories.create(environment: {
      'LUMTUB_HOME': '${temp.path}${sep}userdata',
      'LOCALAPPDATA': '${temp.path}${sep}local'
    });
    expect(portable.logs.path, '${temp.path}${sep}userdata${sep}logs');
    expect(portable.logs.existsSync(), isTrue);
    final installed =
        await AppDirectories.create(environment: {'LOCALAPPDATA': '${temp.path}${sep}local'});
    expect(installed.root.path, '${temp.path}${sep}local${sep}Lumtub');
  });
}
