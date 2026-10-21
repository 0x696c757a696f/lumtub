import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'l10n/l10n.dart';
import 'piped_streams.dart';
import 'relay_servers.dart';

/// The https instances with the API enabled in api.invidious.io's list
/// (`instances.json`: `[["domain", {"type": "https", "api": true, "uri": …}], …]`),
/// in the order given, at most [limit].
List<String> parseInvidiousInstances(String text, {int limit = 30}) {
  final Object? list;
  try {
    list = jsonDecode(text);
  } on FormatException {
    return const [];
  }
  final found = <String>{};
  if (list is List) {
    for (final entry in list) {
      if (entry is! List || entry.length < 2 || entry[1] is! Map) continue;
      final info = entry[1] as Map;
      if (info['type'] != 'https' || info['api'] != true) continue;
      if (normalizePipedServer('${info['uri'] ?? 'https://${entry[0]}'}') case final server?) found.add(server);
    }
  }
  return found.take(limit).toList();
}

/// What an Invidious instance returned for `/api/v1/videos/<id>` as the same
/// kind of video a Piped server gives: the video-only and audio-only
/// `adaptiveFormats`. Addresses without a host (`/videoplayback?…`, as
/// `local=true` gives on some instances) belong to [server].
PipedVideo parseInvidiousVideo(String server, Map<String, dynamic> json) {
  final host = Uri.parse(server).host;
  String? address(Object? raw) {
    var url = '$raw';
    if (url.startsWith('/')) url = '$server$url';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    // An instance behind a TLS-terminating proxy may state its own address as http.
    return uri.host == host && uri.scheme == 'http' ? uri.replace(scheme: 'https').toString() : url;
  }

  final video = <PipedStream>[];
  final audio = <PipedStream>[];
  for (final format in json['adaptiveFormats'] is List ? json['adaptiveFormats'] as List : const []) {
    if (format is! Map) continue;
    final type = '${format['type']}';
    final mime = type.split(';').first.trim();
    final isVideo = mime.startsWith('video/');
    if (!isVideo && !mime.startsWith('audio/')) continue;
    final codec = RegExp(r'codecs="?([^",;]+)').firstMatch(type)?[1] ?? '';
    final size = RegExp(r'^(\d+)x(\d+)$').firstMatch('${format['size']}');
    final height = size != null ? int.parse(size[2]!) : int.tryParse(RegExp(r'^\d+').firstMatch('${format['qualityLabel'] ?? format['resolution']}')?[0] ?? '') ?? 0;
    final stream = PipedStream.tryParse({
      'url': address(format['url']),
      'codec': codec,
      'mimeType': mime,
      'height': isVideo ? height : 0,
      'bitrate': format['bitrate'],
      'videoOnly': isVideo,
    });
    if (stream == null) continue;
    if (isVideo) {
      if (height > 0) video.add(stream);
    } else {
      audio.add(stream);
    }
  }
  // formatStreams are the files with picture and sound together.
  final muxed = <PipedStream>[];
  for (final format in json['formatStreams'] is List ? json['formatStreams'] as List : const []) {
    if (format is! Map) continue;
    final type = '${format['type']}';
    final size = RegExp(r'^(\d+)x(\d+)$').firstMatch('${format['size']}');
    final stream = PipedStream.tryParse({
      'url': address(format['url']),
      'codec': RegExp(r'codecs="?([^",;]+)').firstMatch(type)?[1] ?? '',
      'mimeType': type,
      'height': size != null ? int.parse(size[2]!) : int.tryParse(RegExp(r'^\d+').firstMatch('${format['qualityLabel']}')?[0] ?? '') ?? 0,
      'bitrate': format['bitrate'],
    });
    if (stream != null && stream.height > 0 && stream.mime == 'video/mp4') muxed.add(stream);
  }
  return PipedVideo(server: server, video: video, audio: audio, live: json['liveNow'] == true, muxed: muxed);
}

/// Finds playable streams on Invidious instances, the second source beside
/// Piped. With `local=true` the instance fetches the video from YouTube and
/// passes it on, so the player never talks to googlevideo.com itself.
class InvidiousStreams extends RelayServers {
  InvidiousStreams(http.Client client) : super(client, 'Invidious');

  /// A few long-running instances, measured before the downloaded list is
  /// known; those that do not answer are simply left out.
  static const knownServers = [
    'https://yewtu.be',
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
    'https://invidious.privacyredirect.com',
    'https://invidious.f5.si',
  ];
  /// Invidious's own list of public instances.
  static const instanceList = 'https://api.invidious.io/instances.json?sort_by=type,users';

  /// A short public video; an instance that can look it up works.
  static const probeVideo = 'jNQXAC9IVRw';

  @override
  List<String> get defaultServers => knownServers;
  @override
  String? normalize(String text) => normalizePipedServer(text);
  @override
  Uri healthUrl(String server) => Uri.parse('$server/api/v1/videos/$probeVideo?fields=videoId');
  @override
  bool isHealthy(http.Response response) => response.statusCode == 200 && response.body.contains(probeVideo);
  @override
  String get pausedMessage => tr('Invidious 最近连续失败，暂时不用');

  @override
  Future<Set<String>> downloadCatalog() async {
    final response = await client.get(Uri.parse(instanceList)).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw StateError('HTTP ${response.statusCode}');
    return parseInvidiousInstances(utf8.decode(response.bodyBytes)).toSet();
  }

  /// The streams of [videoId] from [server], or from the fastest instances
  /// in turn when [server] is null.
  Future<PipedVideo> fetch(String videoId, {String? server}) => guarded(() => _fetch(videoId, server));

  Future<PipedVideo> _fetch(String videoId, String? server) async {
    final order = server != null ? [server] : (await servers()).take(2).toList();
    if (order.isEmpty) throw StateError(tr('没有可用的 Invidious 实例'));
    Object? lastError;
    for (final candidate in order) {
      try {
        final response = await client.get(Uri.parse('$candidate/api/v1/videos/$videoId?local=true')).timeout(const Duration(seconds: 10));
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (response.statusCode != 200 || data is! Map<String, dynamic>) {
          throw StateError(data is Map && data['error'] != null ? '${data['error']}' : 'HTTP ${response.statusCode}');
        }
        return parseInvidiousVideo(candidate, data);
      } catch (e) {
        lastError = e;
        logInfo('Invidious 实例 $candidate 无法解析 $videoId：$e');
        if (server == null) demote(candidate);
      }
    }
    throw StateError(tr('Invidious 解析失败：{0}', [lastError]));
  }
}
