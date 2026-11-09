part of 'app_controller.dart';

/// One line of the network check: what was reached, how, and how fast.
class NetworkCheck {
  const NetworkCheck(this.name, {required this.ok, this.ms, this.route = '', this.detail = '', this.skipped = false});
  final String name;
  final bool ok;
  final bool skipped;
  final int? ms;

  /// Which way the request went: direct, the proxy, or the SOCKS bridge.
  final String route;
  final String detail;
}

/// How one codec played in the playback test.
class PlaybackSample {
  const PlaybackSample({required this.codec, this.error, this.decoder = '', this.picture = '', this.cpuPercent, this.memoryMb, this.dropped});
  final VideoCodec codec;
  final String? error;
  final String decoder;
  final String picture;

  /// Processor use while it played, as a share of one core.
  final double? cpuPercent;
  final int? memoryMb;
  final int? dropped;
}

/// Addresses in error messages are cut down to their host, so copied
/// results carry no signatures or tokens.
String diagnosticText(Object error) => '$error'.replaceAllMapped(RegExp(r'https?://([^/\s:]+)[^\s]*'), (m) => m[1]!).replaceAll(RegExp(r'\s+'), ' ').trim();

/// An IPv4 address with its last part hidden, an IPv6 one after its
/// fourth group.
String maskedAddress(String ip) {
  if (ip.contains('.')) return ip.replaceFirst(RegExp(r'\.\d+$'), '.x');
  final groups = ip.split(':');
  return groups.length > 4 ? '${groups.take(4).join(':')}:…' : ip;
}

/// What Cloudflare's trace page says about the asker: its address and country.
({String ip, String country})? readTrace(String body) {
  String? field(String name) => RegExp('^$name=(.*)\$', multiLine: true).firstMatch(body)?.group(1)?.trim();
  final ip = field('ip');
  return ip == null ? null : (ip: ip, country: field('loc') ?? '');
}

/// The network and playback checks of 网络诊断.
extension Diagnostics on AppController {
  static const _testVideo = 'jNQXAC9IVRw';
  static const _benchmarkVideo = 'aqz-KE-bpKQ';

  String get _appRoute {
    if (proxy.url == null) {
      final dns = DnsServer.of(settings.dnsServer, settings.dnsCustomUrl);
      return dns == null ? tr('Direct') : tr('Direct, names looked up by {0}', [dns.name]);
    }
    return tr('Proxy {0}', [proxy.redacted ?? '']);
  }

  String get _playerRoute {
    final endpoint = proxyEndpoint;
    if (endpoint == null) return tr('Direct');
    return proxy.isSocks ? tr('Local bridge {0} to {1}', [endpoint, proxy.redacted ?? '']) : tr('Proxy {0}', [proxy.redacted ?? '']);
  }

  String get _ytDlpRoute => switch (proxy.ytDlpValue(settings.proxyMode)) {
        null => tr('System proxy as yt-dlp finds it'),
        '' => tr('Direct'),
        final url => tr('Proxy {0}', [NetworkProxy(url).redacted ?? '']),
      };

  /// Checks each way Lumtub reaches YouTube, one after another, calling
  /// [progress] with every result as it comes.
  Future<List<NetworkCheck>> runNetworkCheck(void Function(List<NetworkCheck> sofar) progress) async {
    await _refreshProxy();
    final results = <NetworkCheck>[];
    void add(NetworkCheck check) {
      results.add(check);
      progress(List.unmodifiable(results));
    }

    Future<T> timed<T>(Future<T> Function() run, void Function(T value, int ms) done, void Function(Object error, int ms) failed) async {
      final watch = Stopwatch()..start();
      try {
        final value = await run();
        done(value, watch.elapsedMilliseconds);
        return value;
      } catch (e) {
        failed(e, watch.elapsedMilliseconds);
        rethrow;
      }
    }

    // The proxy itself first: when it is down, everything after fails
    // through it rather than going direct.
    if (proxy.url case final url?) {
      final uri = Uri.parse(url);
      try {
        await timed(() => Socket.connect(uri.host, uri.port, timeout: const Duration(seconds: 4)).then((s) => s.destroy()), (_, ms) => add(NetworkCheck(tr('Proxy'), ok: true, ms: ms, route: proxy.redacted ?? '')),
            (e, ms) => add(NetworkCheck(tr('Proxy'), ok: false, ms: ms, route: proxy.redacted ?? '', detail: tr('The proxy cannot be reached; nothing goes direct instead. {0}', [diagnosticText(e)]))));
      } catch (_) {}
      if (proxy.isSocks) {
        final endpoint = proxyEndpoint ?? '';
        final bridged = endpoint.isNotEmpty && endpoint != '127.0.0.1:1';
        add(NetworkCheck(tr('Local SOCKS bridge'), ok: bridged, route: endpoint, detail: bridged ? tr('libmpv and pictures reach the SOCKS proxy through it') : tr('The bridge did not start, so libmpv and pictures cannot connect')));
      }
    }

    // Where each kind of request comes out.
    final exits = <String, String>{};
    Future<void> exit(String name, Future<String> Function() fetch, String route) async {
      try {
        await timed(fetch, (body, ms) {
          final trace = readTrace(body);
          if (trace != null) exits[name] = trace.ip;
          add(NetworkCheck(name, ok: trace != null, ms: ms, route: route, detail: trace == null ? tr('No address in the answer') : '${trace.ip}${trace.country.isEmpty ? '' : ' · ${trace.country}'}'));
        }, (e, ms) => add(NetworkCheck(name, ok: false, ms: ms, route: route, detail: diagnosticText(e))));
      } catch (_) {}
    }

    final trace = Uri.parse('https://www.cloudflare.com/cdn-cgi/trace');
    await exit(tr('Exit address of app requests'), () => _http.get(trace).timeout(const Duration(seconds: 10)).then((r) => r.body), _appRoute);
    await exit(tr('Exit address of the player and pictures'), () => _ioGet(trace).then(utf8.decode), _playerRoute);
    if (exits.values.toSet().length > 1) {
      add(NetworkCheck(tr('Exit addresses'), ok: false, detail: tr('App requests and the player come out at different addresses, so YouTube may see two users')));
    }

    if (DnsServer.of(settings.dnsServer, settings.dnsCustomUrl) case final dns?) {
      if (proxy.url != null) {
        add(NetworkCheck(tr('Encrypted DNS'), ok: true, skipped: true, route: dns.name, detail: tr('Not used: with a proxy, names are looked up by the proxy')));
      } else {
        final test = await testDnsServer(dns);
        add(NetworkCheck(tr('Encrypted DNS'), ok: test.ok, ms: test.milliseconds, route: dns.name, detail: test.ok ? test.addresses.take(2).join(', ') : diagnosticText(test.error)));
      }
    }

    // YouTube's API, and the quick start built on it.
    final core = NativeCore.instance;
    final request = core?.quickRequest(_testVideo);
    if (core != null && request != null) {
      try {
        final parts = jsonDecode(request) as Map<String, dynamic>;
        await timed(
          () => _http
              .post(Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'), headers: {'Content-Type': 'application/json', ...(parts['headers'] as Map).cast<String, String>()}, body: jsonEncode(parts['body']))
              .timeout(const Duration(seconds: 10)),
          (response, ms) {
            add(NetworkCheck(tr('YouTube API'), ok: response.statusCode == 200, ms: ms, route: _appRoute, detail: 'HTTP ${response.statusCode}'));
            if (response.statusCode == 200) {
              final info = core.quickInfo(utf8.decode(response.bodyBytes, allowMalformed: true), FormatPolicy.settingsJson(_playback));
              add(NetworkCheck(tr('Quick start'), ok: info != null, route: _appRoute, detail: info != null ? tr('Streams found without yt-dlp') : tr('Left to yt-dlp, as YouTube gave no plain streams')));
            }
          },
          (e, ms) => add(NetworkCheck(tr('YouTube API'), ok: false, ms: ms, route: _appRoute, detail: diagnosticText(e))),
        );
      } catch (_) {}
    }

    // yt-dlp, then the servers its answer points at.
    Map<String, dynamic>? info;
    final repository = _repository;
    if (repository != null) {
      repository.streams.forget(_testVideo);
      try {
        info = await timed(() => repository.streams.resolve(_testVideo, _format, formatSort: _formatSort).then((r) => r.info), (_, ms) => add(NetworkCheck(tr('Stream extraction (yt-dlp)'), ok: true, ms: ms, route: _ytDlpRoute)),
            (e, ms) => add(NetworkCheck(tr('Stream extraction (yt-dlp)'), ok: false, ms: ms, route: _ytDlpRoute, detail: diagnosticText(e))));
      } catch (_) {}
    }
    final formats = info?['formats'] is List ? (info!['formats'] as List).whereType<Map>() : const <Map>[];
    final stream = formats.where((f) => '${f['url']}'.contains('googlevideo.com') && f['protocol'] == 'https').lastOrNull?['url']?.toString();
    final agent = info?['http_headers'] is Map ? (info!['http_headers'] as Map)['User-Agent']?.toString() : null;
    if (stream == null) {
      add(NetworkCheck(tr('Video servers'), ok: false, skipped: info == null, detail: info == null ? tr('Needs stream extraction') : tr('The answer had no stream address')));
    } else {
      final host = Uri.parse(stream).host;
      const size = 1 << 20;
      final headers = {'Range': 'bytes=0-${size - 1}', if (agent != null) 'User-Agent': agent};
      String speed(int bytes, int ms) => '${(bytes / 1024 / (ms / 1000).clamp(0.001, double.infinity) / 1024).toStringAsFixed(1)} MB/s';
      try {
        await timed(() => _http.get(Uri.parse(stream), headers: headers).timeout(const Duration(seconds: 20)), (r, ms) => add(NetworkCheck(tr('Video servers (relay)'), ok: r.statusCode == 206 || r.statusCode == 200, ms: ms, route: _appRoute, detail: 'HTTP ${r.statusCode} · $host · ${speed(r.bodyBytes.length, ms)}')),
            (e, ms) => add(NetworkCheck(tr('Video servers (relay)'), ok: false, ms: ms, route: _appRoute, detail: diagnosticText(e))));
      } catch (_) {}
      try {
        await timed(() => _ioGet(Uri.parse(stream), headers: headers), (bytes, ms) => add(NetworkCheck(tr('Video servers (player)'), ok: true, ms: ms, route: _playerRoute, detail: '$host · ${speed(bytes.length, ms)}')),
            (e, ms) => add(NetworkCheck(tr('Video servers (player)'), ok: false, ms: ms, route: _playerRoute, detail: diagnosticText(e))));
      } catch (_) {}
    }

    // Subtitles, from the same answer.
    String? captions;
    for (final key in ['subtitles', 'automatic_captions']) {
      final tracks = info?[key];
      if (tracks is! Map) continue;
      for (final list in tracks.values.whereType<List>()) {
        captions ??= list.whereType<Map>().where((t) => t['ext'] == 'vtt' || t['ext'] == 'json3').firstOrNull?['url']?.toString();
      }
    }
    if (captions == null) {
      add(NetworkCheck(tr('Subtitles'), ok: false, skipped: true, detail: info == null ? tr('Needs stream extraction') : tr('The test video has no subtitles')));
    } else {
      try {
        await timed(() => _http.get(Uri.parse(captions!)).timeout(const Duration(seconds: 10)), (r, ms) => add(NetworkCheck(tr('Subtitles'), ok: r.statusCode == 200, ms: ms, route: _appRoute, detail: 'HTTP ${r.statusCode}')),
            (e, ms) => add(NetworkCheck(tr('Subtitles'), ok: false, ms: ms, route: _appRoute, detail: diagnosticText(e))));
      } catch (_) {}
    }

    // Pictures load the way Flutter's images do.
    try {
      await timed(() => _ioGet(Uri.parse('https://i.ytimg.com/vi/$_testVideo/mqdefault.jpg')), (bytes, ms) => add(NetworkCheck(tr('Thumbnails'), ok: bytes.isNotEmpty, ms: ms, route: _playerRoute, detail: '${bytes.length >> 10} KB')),
          (e, ms) => add(NetworkCheck(tr('Thumbnails'), ok: false, ms: ms, route: _playerRoute, detail: diagnosticText(e))));
    } catch (_) {}
    logInfo('Network check: ${results.where((r) => r.ok || r.skipped).length} of ${results.length} passed');
    return results;
  }

  /// A GET through dart:io, which follows the same proxy as libmpv.
  Future<List<int>> _ioGet(Uri uri, {Map<String, String> headers = const {}}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(const Duration(seconds: 20));
      final bytes = await response.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk)).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 400) throw HttpException('HTTP ${response.statusCode}', uri: uri);
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  /// What the playing video is decoded and drawn with now; empty when
  /// nothing plays.
  Future<Map<String, String>> playbackNow() async {
    final platform = player?.platform;
    if (platform is! NativePlayer || playing == null) return const {};
    Future<String> read(String name) async {
      try {
        return (await platform.getProperty(name)).trim();
      } catch (_) {
        return '';
      }
    }

    final hwdec = await read('hwdec-current');
    final width = await read('video-params/w');
    final height = await read('video-params/h');
    final fps = double.tryParse(await read('estimated-vf-fps'));
    return {
      tr('Video codec'): await read('video-codec'),
      tr('Picture'): width.isEmpty ? '' : '$width×$height${fps == null ? '' : ' · ${fps.toStringAsFixed(fps.truncateToDouble() == fps ? 0 : 2)} fps'}',
      tr('Decoding'): hwdec.isEmpty || hwdec == 'no'
          ? tr('Software')
          : hwdec.endsWith('-copy')
              ? tr('Hardware ({0}), frames copied back to memory', [hwdec])
              : tr('Hardware ({0}), frames stay on the GPU', [hwdec]),
      tr('Pixel format'): await read('video-out-params/pixelformat'),
      tr('Dropped frames'): tr('{0} by the decoder, {1} by the display', [await read('decoder-frame-drop-count'), await read('frame-drop-count')]),
      tr('Memory'): '${ProcessInfo.currentRss >> 20} MB',
    };
  }

  /// Plays the same video as H.264, VP9 and AV1 at up to 1080p for
  /// [seconds] each, muted and kept out of the history, and measures the
  /// processor, memory and dropped frames. Calls [progress] with each codec
  /// as it starts.
  Future<List<PlaybackSample>> runPlaybackTest(void Function(VideoCodec codec) progress, {int seconds = 15}) async {
    final results = <PlaybackSample>[];
    final wasIncognito = incognito;
    incognito = true;
    try {
      for (final codec in const [VideoCodec.h264, VideoCodec.vp9, VideoCodec.av1]) {
        progress(codec);
        results.add(await _sampleCodec(codec, seconds));
      }
    } finally {
      _benchmark = null;
      incognito = wasIncognito;
      final platform = player?.platform;
      if (platform is NativePlayer) unawaited(platform.setProperty('mute', 'no'));
      _unload();
    }
    logInfo('Playback test: ${[for (final r in results) '${r.codec.label} ${r.error ?? '${r.decoder} ${r.cpuPercent?.round()}% ${r.memoryMb} MB ${r.dropped} dropped'}'].join(' · ')}');
    return results;
  }

  Future<PlaybackSample> _sampleCodec(VideoCodec codec, int seconds) async {
    _benchmark = settings.copyWith(disabledCodecs: {for (final c in VideoCodec.values) if (c != codec) c}, maxHeight: 1080);
    await play(VideoItem(id: _benchmarkVideo, title: 'Big Buck Bunny', channel: 'Blender', url: 'https://www.youtube.com/watch?v=$_benchmarkVideo'));
    final player = this.player;
    final platform = player?.platform;
    if (player == null || platform is! NativePlayer) return PlaybackSample(codec: codec, error: tr('No player'));
    await platform.setProperty('mute', 'yes');
    final started = DateTime.now();
    while (!(player.state.playing && player.state.position > const Duration(seconds: 1))) {
      if (playbackError != null) return PlaybackSample(codec: codec, error: diagnosticText(playbackError!));
      if (DateTime.now().difference(started) > const Duration(seconds: 40)) return PlaybackSample(codec: codec, error: tr('Did not start'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final actual = VideoCodec.of(DecoderStatus.codecKey((await platform.getProperty('video-codec')).trim().toLowerCase()));
    if (actual != codec) return PlaybackSample(codec: codec, error: tr('YouTube has no {0} stream of the test video', [codec.label]));
    await Future<void>.delayed(const Duration(seconds: 3));
    Future<int> drops() async => (int.tryParse(await platform.getProperty('decoder-frame-drop-count')) ?? 0) + (int.tryParse(await platform.getProperty('frame-drop-count')) ?? 0);
    final cpu = NativeCore.processCpuMs();
    final watch = Stopwatch()..start();
    final dropsBefore = await drops();
    var memory = ProcessInfo.currentRss;
    for (var i = 0; i < seconds * 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      memory = max(memory, ProcessInfo.currentRss);
    }
    final used = NativeCore.processCpuMs();
    final hwdec = (await platform.getProperty('hwdec-current')).trim();
    return PlaybackSample(
      codec: codec,
      decoder: hwdec.isEmpty || hwdec == 'no' ? tr('Software') : hwdec,
      picture: '${await platform.getProperty('video-params/w')}×${await platform.getProperty('video-params/h')}',
      cpuPercent: cpu == null || used == null ? null : (used - cpu) / watch.elapsedMilliseconds * 100,
      memoryMb: memory >> 20,
      dropped: await drops() - dropsBefore,
    );
  }
}
