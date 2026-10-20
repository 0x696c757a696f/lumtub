import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_log.dart';

/// A list of public servers (Piped, Invidious) that fetch videos from
/// YouTube for the app: a built-in list plus one downloaded at most once a
/// day and kept on disk, measured fastest first, with a pause after repeated
/// failures. Subclasses say where the servers are and how to ask them.
abstract class RelayServers {
  RelayServers(this.client, this.name);
  final http.Client client;
  /// For log lines, such as `Piped`.
  final String name;

  /// Servers measured first, without waiting for the downloaded list.
  List<String> get defaultServers;

  /// [text] as a server address, or null when it is not one.
  String? normalize(String text);

  /// The cheap request that shows [server] answers.
  Uri healthUrl(String server);

  /// Whether [response] to [healthUrl] means the server works.
  bool isHealthy(http.Response response) => response.statusCode == 200;

  /// Downloads the public list; may throw, an empty result keeps the old list.
  Future<Set<String>> downloadCatalog();

  /// Why requests are paused after repeated failures.
  String get pausedMessage;

  /// Where the downloaded list is kept between runs; null keeps it in memory.
  File? catalogFile;
  List<String> _catalog = const [];
  DateTime _catalogAt = DateTime(0);
  bool _catalogLoaded = false;

  List<String>? _ranked;
  DateTime _rankedAt = DateTime(0);
  Future<List<String>>? _ranking;
  final _timings = <String, int>{};
  final _tried = <String>{};

  /// The built-in servers and those from the last downloaded list.
  List<String> get catalog => {...defaultServers, ..._catalog}.toList();

  /// When the list was last downloaded, or null if it never was.
  DateTime? get catalogUpdatedAt => _catalogAt.year > 2000 ? _catalogAt : null;

  /// The last measured response time of [server] in ms; null when it was not
  /// measured or did not answer (see [wasTried]).
  int? timingOf(String server) => _timings[server];
  bool wasTried(String server) => _tried.contains(server);
  bool get isRanking => _ranking != null;

  /// Servers to try, fastest first, re-measured every few hours.
  Future<List<String>> servers() {
    final ranked = _ranked;
    if (ranked != null && ranked.isNotEmpty && DateTime.now().difference(_rankedAt) < const Duration(hours: 3)) return Future.value(ranked);
    return _ranking ??= _rank().whenComplete(() => _ranking = null);
  }

  /// Measures every server again now.
  Future<List<String>> remeasure() {
    _ranked = null;
    return servers();
  }

  /// Measures the servers already known at once. A list older than a day is
  /// downloaded meanwhile, and servers new in it are measured when it comes
  /// in, so a slow list does not hold up the first video. When no known
  /// server answers, the new list is all there is, so it is waited for.
  Future<List<String>> _rank() async {
    await _loadCatalog();
    final update = DateTime.now().difference(_catalogAt) > const Duration(days: 1) ? updateCatalog() : Future.value(catalog);
    _timings.clear();
    _tried.clear();
    final before = catalog;
    final others = update.then((all) => _measure(all.where((s) => !before.contains(s))));
    await _measure(before);
    if (_timings.isEmpty) {
      await others;
    } else {
      unawaited(others.then((_) => _publish()));
    }
    return _publish();
  }

  /// Downloads the public list and keeps the servers in it; returns the
  /// whole [catalog]. On failure the previous list stays.
  Future<List<String>> updateCatalog() async {
    await _loadCatalog();
    var found = <String>{};
    try {
      found = await downloadCatalog();
    } catch (e) {
      logInfo('读取 $name 服务器列表失败：$e');
    }
    if (found.isNotEmpty) {
      _catalog = found.toList();
      _catalogAt = DateTime.now();
      logInfo('$name 服务器列表已更新，共 ${catalog.length} 个');
      try {
        await catalogFile?.parent.create(recursive: true);
        await catalogFile?.writeAsString(jsonEncode({'updated': _catalogAt.toIso8601String(), 'servers': _catalog}));
      } catch (e) {
        logInfo('无法保存 $name 服务器列表：$e');
      }
    }
    return catalog;
  }

  Future<void> _loadCatalog() async {
    if (_catalogLoaded) return;
    _catalogLoaded = true;
    final file = catalogFile;
    if (file == null || !await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      _catalog = [
        for (final s in data['servers'] is List ? data['servers'] as List : const [])
          if (normalize('$s') case final server?) server,
      ];
      _catalogAt = DateTime.tryParse('${data['updated']}') ?? DateTime(0);
    } catch (_) {}
  }

  Future<void> _measure(Iterable<String> servers) => Future.wait(servers.map((server) async {
        final watch = Stopwatch()..start();
        try {
          final response = await client.get(healthUrl(server)).timeout(const Duration(seconds: 5));
          if (isHealthy(response)) _timings[server] = watch.elapsedMilliseconds;
        } catch (_) {}
        _tried.add(server);
      }));

  List<String> _publish() {
    final ranked = _timings.keys.toList()..sort((a, b) => _timings[a]!.compareTo(_timings[b]!));
    logInfo(ranked.isEmpty ? '$name 服务器都无法连接' : '$name 服务器（按速度）：${ranked.take(5).map((s) => '$s ${_timings[s]} ms').join('，')}');
    _ranked = ranked;
    _rankedAt = DateTime.now();
    return ranked;
  }

  /// Moves [server] to the back after it failed, so the next video starts
  /// with another.
  void demote(String server) {
    final ranked = _ranked;
    if (ranked != null && ranked.remove(server)) ranked.add(server);
  }

  /// Runs [fetch]. After three videos in a row failed, requests are skipped
  /// for ten minutes, so a time when no server works does not delay every
  /// video.
  Future<T> guarded<T>(Future<T> Function() fetch) async {
    if (DateTime.now().isBefore(_pausedUntil)) throw StateError(pausedMessage);
    try {
      final result = await fetch();
      _failures = 0;
      return result;
    } catch (_) {
      if (++_failures >= 3) {
        _failures = 0;
        _pausedUntil = DateTime.now().add(const Duration(minutes: 10));
      }
      rethrow;
    }
  }

  int _failures = 0;
  DateTime _pausedUntil = DateTime(0);
}
