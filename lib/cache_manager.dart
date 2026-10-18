import 'dart:io';

import 'app_directories.dart';
import 'player_settings.dart';

/// Manages only folders created by YTPlus. A selected parent folder is never
/// deleted or scanned as if it belonged to the application.
class CacheManager {
  static const managedFolders = {'thumbnails', 'temp', 'yt-dlp', 'mpv'};
  final AppDirectories directories;
  CacheManager(this.directories);

  Directory rootFor(PlayerSettings settings) => settings.cachePath == null
      ? directories.cache
      : Directory(settings.cachePath!);

  Future<Directory> prepare(PlayerSettings settings) async {
    final root = rootFor(settings);
    await root.create(recursive: true);
    for (final name in managedFolders) {
      await Directory('${root.path}${Platform.pathSeparator}$name').create(recursive: true);
    }
    return root;
  }

  Future<int> size(PlayerSettings settings) async {
    var bytes = 0;
    final root = rootFor(settings);
    for (final name in managedFolders) {
      final child = Directory('${root.path}${Platform.pathSeparator}$name');
      if (!await child.exists()) continue;
      await for (final item in child.list(recursive: true, followLinks: false)) {
        if (item is File) bytes += await item.length();
      }
    }
    return bytes;
  }

  Future<void> clear(PlayerSettings settings) async {
    final root = await prepare(settings);
    for (final name in managedFolders) {
      final child = Directory('${root.path}${Platform.pathSeparator}$name');
      if (await child.exists()) await child.delete(recursive: true);
      await child.create(recursive: true);
    }
  }

  Future<void> migrate(PlayerSettings from, PlayerSettings to) async {
    final oldRoot = await prepare(from);
    final newRoot = await prepare(to);
    for (final name in managedFolders) {
      final source = Directory('${oldRoot.path}${Platform.pathSeparator}$name');
      final destination = Directory('${newRoot.path}${Platform.pathSeparator}$name');
      if (source.path == destination.path || !await source.exists()) continue;
      if (await destination.exists()) await destination.delete(recursive: true);
      try {
        await source.rename(destination.path);
      } on FileSystemException {
        await _copyDirectory(source, destination);
        await source.delete(recursive: true);
      }
      await source.create(recursive: true);
    }
  }

  Future<void> _copyDirectory(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final item in from.list(recursive: true, followLinks: false)) {
      final relative = item.path.substring(from.path.length).replaceFirst(RegExp(r'^[\\/]'), '');
      final destination = '${to.path}${Platform.pathSeparator}$relative';
      if (item is Directory) {
        await Directory(destination).create(recursive: true);
      } else if (item is File) {
        await File(destination).parent.create(recursive: true);
        await item.copy(destination);
      }
    }
  }
}
