import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'player_settings.dart';
import 'video_format_selector.dart';
import 'l10n/l10n.dart';

/// Where playback streams come from.
enum PlaybackSource {
  /// The fastest working public Piped server.
  pipedAuto('Piped · 自动选择服务器（默认）'),
  /// The Piped server the user named.
  pipedCustom('Piped · 指定服务器'),
  /// Straight from YouTube through yt-dlp.
  youtube('直接连接 YouTube');

  const PlaybackSource(this._label);
  final String _label;
  String get label => tr(_label);

  bool get isPiped => this != youtube;
}

/// A Piped API address as typed, such as `pipedapi.kavin.rocks`, as
/// `https://host`, or null when it is not one.
String? normalizePipedServer(String text) {
  var value = text.trim();
  if (value.isEmpty) return null;
  if (!value.contains('://')) value = 'https://$value';
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  final path = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
  return 'https://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}$path';
}

/// The API servers named in [text]: kavin.rocks's JSON status list, or the
/// Markdown table of the Piped documentation's public-instances page.
List<String> parsePipedInstanceList(String text) {
  try {
    final list = jsonDecode(text);
    return [
      if (list is List)
        for (final entry in list.whereType<Map>())
          if (entry['up_to_date'] != false)
            if (normalizePipedServer('${entry['api_url']}') case final server?) server,
    ];
  } on FormatException {
    return {
      for (final line in const LineSplitter().convert(text))
        if (line.contains('|'))
          for (final cell in line.split('|'))
            if (RegExp(r'^\s*https://[^\s()\[\]]+\s*$').hasMatch(cell))
              if (normalizePipedServer(cell.trim()) case final server?) server,
    }.toList();
  }
}

/// One stream a Piped server lists for a video.
class PipedStream {
  const PipedStream({required this.url, required this.codec, this.height = 0, this.bitrate = 0, this.videoOnly = false});
  final String url;
  /// Normalised to yt-dlp's prefixes: avc1, vp9, av01, mp4a, opus.
  final String codec;
  final int height;
  /// Bits per second.
  final int bitrate;
  final bool videoOnly;

  static PipedStream? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url']?.toString() ?? '';
    if (!url.startsWith('https://')) return null;
    var codec = (raw['codec']?.toString() ?? '').toLowerCase();
    if (codec.startsWith('vp09')) codec = 'vp9';
    final mime = raw['mimeType']?.toString() ?? '';
    if (codec.isEmpty && mime.contains('mp4')) codec = mime.startsWith('audio') ? 'mp4a' : 'avc1';
    int number(String key) => raw[key] is num ? (raw[key] as num).toInt() : int.tryParse('${raw[key]}') ?? 0;
    return PipedStream(url: url, codec: codec, height: number('height'), bitrate: number('bitrate'), videoOnly: raw['videoOnly'] == true);
  }
}

/// What a Piped server returned for one video.
class PipedVideo {
  const PipedVideo({required this.server, required this.video, required this.audio, this.live = false});
  final String server;
  final List<PipedStream> video;
  final List<PipedStream> audio;
  final bool live;

  factory PipedVideo.fromJson(String server, Map<String, dynamic> json) => PipedVideo(
        server: server,
        video: [for (final s in json['videoStreams'] is List ? json['videoStreams'] as List : const []) PipedStream.tryParse(s)]
            .whereType<PipedStream>()
            .where((s) => s.videoOnly && s.height > 0)
            .toList(),
        audio: [for (final s in json['audioStreams'] is List ? json['audioStreams'] as List : const []) PipedStream.tryParse(s)].whereType<PipedStream>().toList(),
        live: json['livestream'] == true,
      );

  List<int> get heights => ({for (final s in video) s.height}.toList()..sort((a, b) => b.compareTo(a)));

  /// The video stream for [settings]: the highest allowed height in the
  /// first preferred codec that has one, as the yt-dlp expression would pick.
  PipedStream? pickVideo(PlayerSettings settings) {
    if (video.isEmpty) return null;
    final limit = settings.maxHeight;
    var allowed = video.where((s) => limit == 0 || s.height <= limit).toList();
    if (allowed.isEmpty) {
      final lowest = video.map((s) => s.height).reduce((a, b) => a < b ? a : b);
      allowed = video.where((s) => s.height == lowest).toList();
    }
    int better(PipedStream a, PipedStream b) => a.height != b.height ? b.height.compareTo(a.height) : b.bitrate.compareTo(a.bitrate);
    for (final codec in VideoFormatSelector.codecOrder(settings)) {
      final matching = allowed.where((s) => s.codec.startsWith(codec)).toList()..sort(better);
      if (matching.isNotEmpty) return matching.first;
    }
    return (allowed..sort(better)).first;
  }

  PipedStream? pickAudio(PlayerSettings settings) {
    if (audio.isEmpty) return null;
    final limit = switch (settings.audioQuality) {
      AudioQuality.best => null,
      AudioQuality.medium => 128000,
      AudioQuality.low => 64000,
    };
    final sorted = [...audio]..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    return sorted.where((s) => limit == null || s.bitrate <= limit * 1.1).firstOrNull ?? sorted.last;
  }

  /// An mpv EDL address joining the picked video and audio, or null when
  /// this video cannot be played this way (live, nothing separate).
  String? edl(PlayerSettings settings) {
    if (live) return null;
    final v = pickVideo(settings);
    final a = pickAudio(settings);
    if (v == null || a == null) return null;
    String part(String url) => '!new_stream;!no_clip;!no_chapters;%${utf8.encode(url).length}%$url';
    return 'edl://${part(v.url)};${part(a.url)}';
  }
}

/// Finds playable streams on Piped servers. Piped servers fetch the video
/// from YouTube and pass it on, so YouTube's per-connection throttling of
/// players that request whole files does not apply.
class PipedStreams {
  PipedStreams(this._client);
  final http.Client _client;

  /// Public API servers checked first, without waiting for the live list;
  /// those that do not answer are simply left out.
  static const knownServers = [
    'https://pipedapi.kavin.rocks',
    'https://pipedapi-libre.kavin.rocks',
    'https://pipedapi.adminforge.de',
    'https://api.piped.private.coffee',
    'https://pipedapi.leptons.xyz',
    'https://pipedapi.nosebs.ru',
    'https://pipedapi.reallyaweso.me',
    'https://piped-api.lunar.icu',
    'https://pipedapi.tokhmi.xyz',
    'https://pipedapi.moomoo.me',
    'https://api.looleh.xyz',
    'https://piped-api.cfe.re',
    'https://pipedapi.r4fo.com',
    'https://pa.mint.lgbt',
    'https://piped-api.privacy.com.de',
    'https://api.piped.projectsegfau.lt',
    'https://pa.il.ax',
  ];
  /// The Piped project's table of public instances, and kavin.rocks's live
  /// status list; servers either names are measured with the known ones.
  static const instanceLists = [
    'https://raw.githubusercontent.com/TeamPiped/documentation/main/content/docs/public-instances/index.md',
    'https://piped-instances.kavin.rocks/',
  ];

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
  List<String> get catalog => {...knownServers, ..._catalog}.toList();

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

  /// Downloads [instanceLists] and keeps the servers they name; returns the
  /// whole [catalog]. On failure the previous list stays.
  Future<List<String>> updateCatalog() async {
    await _loadCatalog();
    final found = <String>{};
    await Future.wait(instanceLists.map((url) async {
      try {
        final response = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) found.addAll(parsePipedInstanceList(utf8.decode(response.bodyBytes)));
      } catch (e) {
        logInfo('读取 Piped 服务器列表 $url 失败：$e');
      }
    }));
    if (found.isNotEmpty) {
      _catalog = found.toList();
      _catalogAt = DateTime.now();
      logInfo('Piped 服务器列表已更新，共 ${catalog.length} 个');
      try {
        await catalogFile?.parent.create(recursive: true);
        await catalogFile?.writeAsString(jsonEncode({'updated': _catalogAt.toIso8601String(), 'servers': _catalog}));
      } catch (e) {
        logInfo('无法保存 Piped 服务器列表：$e');
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
          if (normalizePipedServer('$s') case final server?) server,
      ];
      _catalogAt = DateTime.tryParse('${data['updated']}') ?? DateTime(0);
    } catch (_) {}
  }

  Future<void> _measure(Iterable<String> servers) => Future.wait(servers.map((server) async {
        final watch = Stopwatch()..start();
        try {
          final response = await _client.get(Uri.parse('$server/healthcheck')).timeout(const Duration(seconds: 5));
          if (response.statusCode == 200) _timings[server] = watch.elapsedMilliseconds;
        } catch (_) {}
        _tried.add(server);
      }));

  List<String> _publish() {
    final ranked = _timings.keys.toList()..sort((a, b) => _timings[a]!.compareTo(_timings[b]!));
    logInfo(ranked.isEmpty ? 'Piped 服务器都无法连接' : 'Piped 服务器（按速度）：${ranked.take(5).map((s) => '$s ${_timings[s]} ms').join('，')}');
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

  /// The streams of [videoId] from [server], or from the fastest servers
  /// in turn when [server] is null.
  ///
  /// After three videos in a row failed, Piped is skipped for ten minutes,
  /// so a time when no server works does not delay every video.
  Future<PipedVideo> fetch(String videoId, {String? server}) async {
    if (DateTime.now().isBefore(_pausedUntil)) throw StateError(tr('Piped 最近连续失败，暂时不用'));
    try {
      final video = await _fetch(videoId, server);
      _failures = 0;
      return video;
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

  Future<PipedVideo> _fetch(String videoId, String? server) async {
    final order = server != null ? [server] : (await servers()).take(2).toList();
    if (order.isEmpty) throw StateError(tr('没有可用的 Piped 服务器'));
    Object? lastError;
    for (final candidate in order) {
      try {
        final response = await _client.get(Uri.parse('$candidate/streams/$videoId')).timeout(const Duration(seconds: 8));
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (response.statusCode != 200 || data is! Map<String, dynamic>) {
          throw StateError(data is Map && data['message'] != null ? '${data['message']}' : 'HTTP ${response.statusCode}');
        }
        return PipedVideo.fromJson(candidate, data);
      } catch (e) {
        lastError = e;
        logInfo('Piped 服务器 $candidate 无法解析 $videoId：$e');
        if (server == null) demote(candidate);
      }
    }
    throw StateError(tr('Piped 解析失败：{0}', [lastError]));
  }
}
