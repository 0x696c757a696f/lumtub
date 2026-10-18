import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The small set of directories owned by YTPlus.
///
/// They live under LocalAppData so both the installed and portable package can
/// initialise without elevation. Only files created by YTPlus are kept here.
class AppDirectories {
  final Directory root;
  final Directory config;
  final Directory data;
  final Directory cache;
  final Directory components;
  final Directory logs;

  const AppDirectories({
    required this.root,
    required this.config,
    required this.data,
    required this.cache,
    required this.components,
    required this.logs,
  });

  factory AppDirectories.at(Directory root) => AppDirectories(
        root: root,
        config: Directory('${root.path}${Platform.pathSeparator}config'),
        data: Directory('${root.path}${Platform.pathSeparator}data'),
        cache: Directory('${root.path}${Platform.pathSeparator}cache'),
        components: Directory('${root.path}${Platform.pathSeparator}components'),
        logs: Directory('${root.path}${Platform.pathSeparator}logs'),
      );

  static Future<AppDirectories> create() async {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final root = localAppData == null || localAppData.trim().isEmpty
        ? Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}YTPlus')
        : Directory('$localAppData${Platform.pathSeparator}YTPlus');
    final directories = AppDirectories.at(root);
    await directories.ensureExists();
    return directories;
  }

  Future<void> ensureExists() async {
    for (final directory in [root, config, data, cache, components, logs]) {
      await directory.create(recursive: true);
    }
  }
}
