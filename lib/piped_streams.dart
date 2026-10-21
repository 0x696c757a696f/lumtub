import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'media_url_policy.dart';
import 'player_settings.dart';
import 'relay_servers.dart';
import 'video_format_selector.dart';
import 'l10n/l10n.dart';

/// The public server networks that can fetch a video in place of YouTube.
enum RelayKind { piped, invidious }

/// Where playback streams come from.
enum PlaybackSource {
  /// The fastest working public Piped server.
  pipedAuto('Piped · 自动选择服务器'),
  /// The Piped server the user named.
  pipedCustom('Piped · 指定服务器'),
  /// The fastest working public Invidious instance.
  invidiousAuto('Invidious · 自动选择实例'),
  /// The Invidious instance the user named.
  invidiousCustom('Invidious · 指定实例'),
  /// Straight from YouTube through yt-dlp; the default, so no third party
  /// learns what is watched unless YouTube refuses (429) or fails.
  youtube('直接连接 YouTube（默认）');

  const PlaybackSource(this._label);
  final String _label;
  String get label => tr(_label);

  /// The server network this source uses, or null for YouTube.
  RelayKind? get relay => switch (this) {
        pipedAuto || pipedCustom => RelayKind.piped,
        invidiousAuto || invidiousCustom => RelayKind.invidious,
        youtube => null,
      };

  /// Whether a named server is used instead of the fastest one.
  bool get isCustom => this == pipedCustom || this == invidiousCustom;
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
  const PipedStream({required this.url, required this.codec, this.height = 0, this.bitrate = 0, this.videoOnly = false, this.mime = ''});
  final String url;
  /// Normalised to yt-dlp's prefixes: avc1, vp9, av01, mp4a, opus.
  final String codec;
  final int height;
  /// Bits per second.
  final int bitrate;
  final bool videoOnly;
  /// The container's MIME type, such as video/mp4, when the server gave one.
  final String mime;

  /// The stream in [raw], or null when its address is not an allowed media
  /// address (see [isAllowedMediaUrl]; [trustedHosts] are the server's own).
  static PipedStream? tryParse(Object? raw, {Iterable<String> trustedHosts = const []}) {
    if (raw is! Map) return null;
    final url = raw['url']?.toString() ?? '';
    if (!isAllowedMediaUrl(url, trustedHosts: trustedHosts)) return null;
    var codec = (raw['codec']?.toString() ?? '').toLowerCase();
    if (codec.startsWith('vp09')) codec = 'vp9';
    final mime = raw['mimeType']?.toString() ?? '';
    if (codec.isEmpty && mime.contains('mp4')) codec = mime.startsWith('audio') ? 'mp4a' : 'avc1';
    int number(String key) => raw[key] is num ? (raw[key] as num).toInt() : int.tryParse('${raw[key]}') ?? 0;
    return PipedStream(url: url, codec: codec, height: number('height'), bitrate: number('bitrate'), videoOnly: raw['videoOnly'] == true, mime: mime.split(';').first.trim());
  }
}

/// What a Piped server returned for one video.
class PipedVideo {
  const PipedVideo({required this.server, required this.video, required this.audio, this.live = false, this.muxed = const []});
  final String server;
  final List<PipedStream> video;
  final List<PipedStream> audio;
  /// Streams with video and audio in one file (mp4), which a TV can play
  /// from a single address; see `castStreamOf`.
  final List<PipedStream> muxed;
  final bool live;

  /// Streams are kept only on the server's host, its `proxyUrl` host or YouTube's.
  factory PipedVideo.fromJson(String server, Map<String, dynamic> json) {
    final trusted = {Uri.tryParse(server)?.host ?? '', Uri.tryParse('${json['proxyUrl']}')?.host ?? ''}..remove('');
    PipedStream? parse(Object? s) => PipedStream.tryParse(s, trustedHosts: trusted);
    return PipedVideo(
      server: server,
      video: [for (final s in json['videoStreams'] is List ? json['videoStreams'] as List : const []) parse(s)]
          .whereType<PipedStream>()
          .where((s) => s.videoOnly && s.height > 0)
          .toList(),
      audio: [for (final s in json['audioStreams'] is List ? json['audioStreams'] as List : const []) parse(s)].whereType<PipedStream>().toList(),
      live: json['livestream'] == true,
      muxed: [for (final s in json['videoStreams'] is List ? json['videoStreams'] as List : const []) parse(s)]
          .whereType<PipedStream>()
          .where((s) => !s.videoOnly && s.height > 0 && (s.mime.isEmpty || s.mime.contains('mp4')))
          .toList(),
    );
  }

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
class PipedStreams extends RelayServers {
  PipedStreams(http.Client client) : super(client, 'Piped');

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

  @override
  List<String> get defaultServers => knownServers;
  @override
  String? normalize(String text) => normalizePipedServer(text);
  @override
  Uri healthUrl(String server) => Uri.parse('$server/healthcheck');
  @override
  String get pausedMessage => tr('Piped 最近连续失败，暂时不用');

  @override
  Future<Set<String>> downloadCatalog() async {
    final found = <String>{};
    await Future.wait(instanceLists.map((url) async {
      try {
        final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) found.addAll(parsePipedInstanceList(utf8.decode(response.bodyBytes)));
      } catch (e) {
        logInfo('读取 Piped 服务器列表 $url 失败：$e');
      }
    }));
    return found;
  }

  /// The streams of [videoId] from [server], or from the fastest servers
  /// in turn when [server] is null.
  Future<PipedVideo> fetch(String videoId, {String? server}) => guarded(() => _fetch(videoId, server));

  Future<PipedVideo> _fetch(String videoId, String? server) async {
    final order = server != null ? [server] : (await servers()).take(2).toList();
    if (order.isEmpty) throw StateError(tr('没有可用的 Piped 服务器'));
    Object? lastError;
    for (final candidate in order) {
      try {
        final response = await client.get(Uri.parse('$candidate/streams/$videoId')).timeout(const Duration(seconds: 8));
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
