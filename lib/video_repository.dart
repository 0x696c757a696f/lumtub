import 'dart:convert';
import 'dart:io';

import 'app_directories.dart';
import 'models.dart';

class VideoRepository {
  final String ytDlpPath;
  final String? cacheDirectory;
  VideoRepository(this.ytDlpPath, {this.cacheDirectory});

  Future<List<VideoItem>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final result = await Process.run(
      ytDlpPath,
      [
        '--no-warnings',
        '--skip-download',
        if (cacheDirectory != null) ...['--cache-dir', cacheDirectory!],
        '--flat-playlist',
        '--dump-json',
        '--playlist-end', '20',
        '--', 'ytsearch20:$q',
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      environment: {
        ...Platform.environment,
        if (cacheDirectory != null) ...{
          'TMP': '${cacheDirectory!}${Platform.pathSeparator}..${Platform.pathSeparator}temp',
          'TEMP': '${cacheDirectory!}${Platform.pathSeparator}..${Platform.pathSeparator}temp',
        },
      },
    ).timeout(const Duration(seconds: 100));
    final items = VideoItem.fromJsonLines(result.stdout.toString());
    if (items.isEmpty) {
      final err = result.stderr.toString().trim();
      throw StateError(err.isEmpty ? 'YouTube did not return any results.' : err);
    }
    return items;
  }
}

class HistoryStore {
  final AppDirectories directories;
  HistoryStore(this.directories);

  late File file;
  final List<VideoItem> items = [];

  Future<void> initialize() async {
    file = File('${directories.data.path}${Platform.pathSeparator}watch_history.json');
    if (!await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is List) {
        for (final value in data) {
          try {
            if (value is Map<String, dynamic>) items.add(VideoItem.fromJson(value));
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> record(VideoItem item) async {
    items.removeWhere((other) => other.id == item.id);
    items.insert(0, item);
    if (items.length > 60) items.removeRange(60, items.length);
    await file.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()), flush: true);
  }
}
