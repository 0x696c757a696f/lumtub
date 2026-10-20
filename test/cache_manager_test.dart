import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/app_directories.dart';
import 'package:ytplus/cache_manager.dart';
import 'package:ytplus/player_settings.dart';

void main() {
  test('clear removes only YTPlus-managed cache folders', () async {
    final temp = await Directory.systemTemp.createTemp('ytplus-cache-test-');
    addTearDown(() => temp.delete(recursive: true));
    final manager = CacheManager(AppDirectories.at(Directory('${temp.path}${Platform.pathSeparator}app')));
    const settings = PlayerSettings();
    final root = await manager.prepare(settings);
    await File('${root.path}${Platform.pathSeparator}temp${Platform.pathSeparator}download.part').writeAsString('1234');
    final userFile = File('${root.path}${Platform.pathSeparator}do-not-delete.txt');
    await userFile.writeAsString('user file');

    final nested = File('${root.path}${Platform.pathSeparator}yt-dlp${Platform.pathSeparator}youtube-sigfuncs${Platform.pathSeparator}a.json');
    await nested.create(recursive: true);
    await nested.writeAsString('123456');

    expect(await manager.size(settings), 10);
    final result = await manager.clear(settings);

    expect(result, (freed: 10, skipped: 0));
    expect(await manager.size(settings), 0);
    expect(await userFile.readAsString(), 'user file');
    // The managed folders stay, emptied, for processes that use them.
    for (final name in CacheManager.managedFolders) {
      final folder = Directory('${root.path}${Platform.pathSeparator}$name');
      expect(await folder.exists(), isTrue);
      expect(await folder.list().isEmpty, isTrue);
    }
  });
}
