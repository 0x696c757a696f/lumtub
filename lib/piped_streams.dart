import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'background_json.dart';
import 'bounded_get.dart';
import 'format_policy.dart';
import 'l10n/l10n.dart';
import 'media_url_policy.dart';
import 'native_core.dart';
import 'player_settings.dart';
import 'relay_servers.dart';
import 'video_codec.dart';

/// The public server networks that can fetch a video in place of YouTube.
enum RelayKind { piped, invidious }

/// Where playback streams come from.
enum PlaybackSource {
  /// The fastest working public Piped server.
  pipedAuto('Piped · Auto-select server'),
  /// The Piped server the user named.
  pipedCustom('Piped · Specific server'),
  /// The fastest working public Invidious instance.
  invidiousAuto('Invidious · Auto-select instance'),
  /// The Invidious instance the user named.
  invidiousCustom('Invidious · Specified instance'),
  /// Straight from YouTube through yt-dlp; the default, so no third party
  /// learns what is watched unless YouTube refuses (429) or fails.
  youtube('Connect to YouTube directly (default)');

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
        for (final entry in list.whereType<Map<Object?, Object?>>())
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

  /// A stream the core read, `[address, codec, height, bitrate, container, video only]`,
  /// or null when its address is not an allowed media address.
  static PipedStream? fromRow(List<Object?> row, Iterable<String> trustedHosts, {String? url}) {
    final address = url ?? row[0]! as String;
    if (!isAllowedMediaUrl(address, trustedHosts: trustedHosts)) return null;
    return PipedStream(url: address, codec: row[1]! as String, height: row[2]! as int, bitrate: row[3]! as int, videoOnly: row[5]! as bool, mime: row[4]! as String);
  }

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

/// What the core read from a Piped or Invidious answer: the stream lists
/// and the server's error, or null without the core.
typedef CoreRelayVideo = ({List<List<Object?>> video, List<List<Object?>> audio, List<List<Object?>> muxed, bool live, String? proxyUrl, String? error});

/// [body] read by the core (native/lumtub_core/src/relay_video.rs): null
/// without the core, and an [error] only when it is no JSON object.
({CoreRelayVideo? video, bool unread})? readRelayVideo(bool invidious, List<int> body) {
  final core = NativeCore.instance;
  if (core == null) return null;
  final json = core.relayVideo(invidious, body);
  if (json == null) return (video: null, unread: true);
  final map = jsonDecode(json) as Map<String, dynamic>;
  List<List<Object?>> rows(String key) => [for (final r in map[key] as List) r as List<Object?>];
  return (
    video: (video: rows('video'), audio: rows('audio'), muxed: rows('muxed'), live: map['live'] == true, proxyUrl: map['proxyUrl'] as String?, error: map['error'] as String?),
    unread: false,
  );
}

/// What a Piped server returned for one video.
class PipedVideo {
  /// [read], the core's reading of a Piped answer from [server]; streams
  /// are kept as in [PipedVideo.fromJson].
  factory PipedVideo.fromCore(String server, CoreRelayVideo read) {
    final trusted = {Uri.tryParse(server)?.host ?? '', Uri.tryParse('${read.proxyUrl}')?.host ?? ''}..remove('');
    return PipedVideo(
      server: server,
      video: [for (final r in read.video) if (PipedStream.fromRow(r, trusted) case final s?) s],
      audio: [for (final r in read.audio) if (PipedStream.fromRow(r, trusted) case final s?) s],
      muxed: [for (final r in read.muxed) if (PipedStream.fromRow(r, trusted) case final s?) s],
      live: read.live,
    );
  }

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

  const PipedVideo({required this.server, required this.video, required this.audio, this.live = false, this.muxed = const []});
  final String server;
  final List<PipedStream> video;
  final List<PipedStream> audio;
  /// Streams with video and audio in one file (mp4), which a TV can play
  /// from a single address; see `castStreamOf`.
  final List<PipedStream> muxed;
  final bool live;

  /// This video without the streams on a host that is not YouTube's and
  /// resolves to an address on this computer or its network.
  Future<PipedVideo> withoutPrivateHosts() async {
    final all = [...video, ...audio, ...muxed];
    final hosts = {for (final s in all) Uri.parse(s.url).host.toLowerCase()};
    final blocked = <String>{};
    for (final host in hosts) {
      if (!isYoutubeMediaHost(host) && !await resolvesToPublicAddress(host)) blocked.add(host);
    }
    if (blocked.isEmpty) return this;
    logWarn('Dropped streams on hosts that point into the local network: ${blocked.join(', ')}');
    bool keep(PipedStream s) => !blocked.contains(Uri.parse(s.url).host.toLowerCase());
    return PipedVideo(server: server, video: video.where(keep).toList(), audio: audio.where(keep).toList(), muxed: muxed.where(keep).toList(), live: live);
  }

  List<int> get heights => ({for (final s in video) s.height}.toList()..sort((a, b) => b.compareTo(a)));

  /// [heights] of the streams [settings] allows.
  List<int> heightsFor(PlayerSettings settings) => ({for (final s in video) if (FormatPolicy.allowsName(settings, s.codec)) s.height}.toList()..sort((a, b) => b.compareTo(a)));

  /// The video stream for [settings]: the highest allowed height in the
  /// first preferred allowed codec that has one, as the yt-dlp expression would pick.
  PipedStream? pickVideo(PlayerSettings settings) {
    final streams = video.where((s) => FormatPolicy.allowsName(settings, s.codec)).toList();
    if (streams.isEmpty) return null;
    final limit = settings.maxHeight;
    var allowed = streams.where((s) => limit == 0 || s.height <= limit).toList();
    if (allowed.isEmpty) {
      final lowest = streams.map((s) => s.height).reduce((a, b) => a < b ? a : b);
      allowed = streams.where((s) => s.height == lowest).toList();
    }
    int better(PipedStream a, PipedStream b) => a.height != b.height ? b.height.compareTo(a.height) : b.bitrate.compareTo(a.bitrate);
    // Quality strategy has no codec preference: the best picture wins.
    if (settings.strategy == PlaybackStrategy.quality) return (allowed..sort(better)).first;
    for (final codec in FormatPolicy.codecOrder(settings)) {
      final matching = allowed.where((s) => VideoCodec.of(s.codec) == codec).toList()..sort(better);
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
    // The two that still passed a stream check in November 2026.
    'https://api.piped.private.coffee',
    'https://pipedapi.ducks.party',
    'https://pipedapi.kavin.rocks',
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
  Future<({List<({String url})> video, List<({String url})> audio})> probe(String server) async {
    final video = await _from(server, RelayServers.probeVideo);
    return (video: [for (final s in video.video) (url: s.url)], audio: [for (final s in video.audio) (url: s.url)]);
  }
  @override
  String get pausedMessage => tr('Piped failed repeatedly; skipping it for now');

  @override
  Future<Set<String>> downloadCatalog() async {
    final found = <String>{};
    await Future.wait(instanceLists.map((url) async {
      try {
        final response = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) found.addAll(parsePipedInstanceList(utf8.decode(response.bodyBytes)));
      } catch (e) {
        logWarn('Could not read the Piped server list $url: $e');
      }
    }));
    return found;
  }

  /// The streams of [videoId] from [server], or from the fastest servers
  /// in turn when [server] is null.
  Future<PipedVideo> fetch(String videoId, {String? server}) => guarded(() => _fetch(videoId, server));

  Future<PipedVideo> _fetch(String videoId, String? server) async {
    final order = server != null ? [server] : (await servers()).take(2).toList();
    if (order.isEmpty) throw StateError(tr('No Piped servers available'));
    Object? lastError;
    for (final candidate in order) {
      try {
        return await _from(candidate, videoId);
      } catch (e) {
        lastError = e;
        logWarn('Piped server $candidate could not resolve $videoId: $e');
        if (server == null) demote(candidate);
      }
    }
    throw StateError(tr('Piped failed to resolve: {0}', [lastError]));
  }

  /// The streams of [videoId] from [server]; throws when it has none.
  Future<PipedVideo> _from(String server, String videoId) async {
    final (status, body) = await getBounded(client, Uri.parse('$server/streams/$videoId'), limit: 8 << 20).timeout(const Duration(seconds: 8));
    if (readRelayVideo(false, body) case final read?) {
      final video = read.video;
      if (status != 200 || video == null) throw StateError(video?.error ?? 'HTTP $status');
      return PipedVideo.fromCore(server, video).withoutPrivateHosts();
    }
    final data = await decodeUtf8JsonInBackground(body);
    if (status != 200 || data is! Map<String, dynamic>) {
      throw StateError(data is Map && data['message'] != null ? '${data['message']}' : 'HTTP $status');
    }
    return PipedVideo.fromJson(server, data).withoutPrivateHosts();
  }
}
