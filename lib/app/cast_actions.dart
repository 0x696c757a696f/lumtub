part of 'app_controller.dart';

/// The stream handed to a cast device, and the relay that serves it.
extension CastActions on AppController {
  /// What to cast of [playing] to [device]: the picture and sound streams
  /// joined by lumtub_core when YouTube has a better picture apart than
  /// together (up to 1080p), else one progressive mp4 with sound, from the
  /// yt-dlp extraction or from a Piped or Invidious server.
  Future<CastMedia> castMedia(Duration start, CastDevice device) async {
    final item = playing;
    if (item == null || item.isLive || _repository == null) throw CastException(tr('No stream can be cast (a single MP4 address with sound is needed)'));
    final title = details?.title.isNotEmpty == true ? details!.title : item.title;
    // What is shown now goes to the TV too: one subtitle, or two.
    final subtitles = await castSubtitleCues();
    if (subtitles.cues.isNotEmpty) logInfo('Cast: with ${subtitles.cues.length} subtitle lines');
    CastSource? source;
    Map<String, dynamic>? info;
    try {
      info = (await _repository!.streams.resolve(item.id, _format, formatSort: _formatSort)).info;
      source = castSourceFromYtDlp(info, settings: _playback);
    } catch (e) {
      logWarn('Cast: yt-dlp could not resolve: $e');
    }
    if (info != null) {
      final split = castSplitFromYtDlp(info, maxHeight: preferences.castMaxHeight);
      if (split != null && split.height > (source?.height ?? 0)) {
        try {
          return await _joinedCast(split, device, start, title, info, subtitles);
        } catch (e) {
          logWarn('Cast: could not join the ${split.height}p picture with its sound: $e');
        }
      }
    }
    for (final kind in RelayKind.values) {
      if (source != null) break;
      try {
        source = castSourceFromRelay(await (kind == RelayKind.piped ? _piped.fetch(item.id) : _invidious.fetch(item.id)), settings: _playback);
      } catch (e) {
        logWarn('Cast: $kind could not resolve: $e');
      }
    }
    if (source == null) throw CastException(tr('No stream can be cast (a single MP4 address with sound is needed)'));
    logInfo('Casting the ${source.height}p file with picture and sound together');
    CastSubtitles? lines;
    if (subtitles.cues.isNotEmpty) {
      try {
        lines = await CastSubtitleServer.instance.register(subtitles.cues, host: await AppController._addressFacing(device), language: subtitles.language);
      } catch (e) {
        logWarn('Cast: could not serve the subtitles: $e');
      }
    }
    return CastMedia(url: source.url, title: title, mime: source.mime, start: start, subtitles: lines);
  }

  Future<CastMedia> _joinedCast(CastSplit split, CastDevice device, Duration start, String title, Map<String, dynamic> info, ({List<SubtitleCue> cues, String? language}) subtitles) async {
    final core = NativeCore.instance;
    final videoId = playing?.id;
    if (core == null || videoId == null) throw StateError('no lumtub_core');
    // The cast server fetches YouTube itself, directly or through the proxy.
    final port = core.castStart();
    if (port == 0) throw StateError('the cast server could not listen');
    final here = await AppController._addressFacing(device);
    // Apple's players take a transport stream only as HLS; TVs take it whole.
    // A format chosen for the device wins; TS and HLS carry H.264 and AAC only.
    final kind = switch (preferences.castFormats[device.id]) {
      'ts' || 'hls' when !split.fitsTransportStream => 'mp4',
      final String chosen => chosen,
      null when device.protocol == CastProtocol.dlna && split.fitsTransportStream => device is DlnaDevice && device.apple ? 'hls' : 'ts',
      null when device.protocol == CastProtocol.airplay && split.fitsTransportStream => 'hls',
      null => 'mp4',
    };
    // HLS and MKV carry the lines inside the stream, timed from the start
    // of the video; there no other subtitle file goes with them.
    final inside = (kind == 'hls' || kind == 'mkv') && subtitles.cues.isNotEmpty;
    final agent = info['http_headers'] is Map ? (info['http_headers'] as Map)['User-Agent']?.toString() : null;
    final duration = info['duration'] is num ? Duration(milliseconds: ((info['duration'] as num) * 1000).round()) : null;
    Map<String, dynamic> target(String url, int size) => {'url': url, 'size': size, if (agent != null) 'userAgent': agent, if (proxy.url != null) 'proxy': proxy.url};
    var current = split;
    var renewing = false;
    Future<void> renew() async {
      renewing = true;
      try {
        _repository!.streams.forget(videoId);
        final fresh = (await _repository!.streams.resolve(videoId, _format, formatSort: _formatSort)).info;
        final next = current.renewedFrom(fresh);
        if (next == null) {
          logWarn('Cast: the new extraction lacks formats ${current.videoFormat}+${current.audioFormat}');
          return;
        }
        final taken = core.castRenew({current.video: next.video, current.audio: next.audio});
        logInfo('Cast: renewed the stream addresses ($taken streams)');
        current = next;
      } catch (e) {
        logWarn('Cast: could not renew the stream addresses: $e');
      } finally {
        renewing = false;
      }
    }

    _castWatch?.cancel();
    // The device may take a while to load; the watch ends once it was seen
    // casting this video and no longer is, or if it never started.
    var seen = false;
    var asked = false;
    _castWatch = Timer.periodic(const Duration(seconds: 5), (timer) {
      for (final line in (jsonDecode(core.castLog() ?? '[]') as List).cast<String>()) {
        asked |= line.contains(' asked ');
        logInfo(line);
      }
      if (!asked && timer.tick == 4) {
        logWarn('Cast: ${device.name} has not asked for the stream in 20 s');
        _notice(tr('The TV has not asked Lumtub for the video yet. If it does not start, a firewall on this computer may be blocking Lumtub; allow it on this network.'));
      }
      final casting = cast.active && cast.videoId == videoId;
      seen |= casting;
      if (!casting && (seen || timer.tick > 12)) {
        timer.cancel();
        if (identical(_castWatch, timer)) _castWatch = null;
        return;
      }
      final expires = current.expires;
      final soon = expires != null && expires.difference(DateTime.now()) < const Duration(minutes: 20);
      if (!renewing && (soon || core.castExpired())) unawaited(renew());
    });
    Future<CastMedia> from(Duration at, {bool again = false}) async {
      final split = current;
      final ask = jsonEncode({
        'video': target(split.video, split.videoSize),
        'audio': target(split.audio, split.audioSize),
        'startMs': at.inMilliseconds,
        'kind': kind,
        if (duration != null) 'durationMs': duration.inMilliseconds,
        if (inside)
          'subtitles': {
            'language': subtitles.language ?? '',
            'cues': [for (final cue in subtitles.cues) [cue.start.inMilliseconds, cue.end.inMilliseconds, cue.text]],
          },
      });
      final answer = jsonDecode(await AppController._castRegister(ask)) as Map<String, dynamic>;
      // An address YouTube refuses at once is asked for anew, once.
      if (!again && answer['path'] is! String && '${answer['error']}'.contains(RegExp(r'answered 4(03|10)'))) {
        logWarn('Cast: YouTube refused the stream addresses (${answer['error']}); resolving again');
        final before = current;
        await renew();
        if (!identical(before, current)) return from(at, again: true);
      }
      final path = answer['path'];
      if (path is! String) throw StateError('${answer['error']}');
      final begins = Duration(milliseconds: (((answer['start'] as num?) ?? 0) * 1000).round());
      logInfo('Casting ${split.height}p${split.fps} ${split.codec} joined by lumtub_core from ${begins.inSeconds} s as ${const {'hls': 'HLS', 'ts': 'MPEG-TS', 'mkv': 'MKV'}[kind] ?? 'MP4'}${inside ? ' with ${subtitles.cues.length} subtitle lines inside' : ''}');
      // The device counts time from where this stream begins.
      CastSubtitles? lines;
      if (subtitles.cues.isNotEmpty && !(inside && device.protocol != CastProtocol.chromecast)) {
        try {
          lines = await CastSubtitleServer.instance.register(subtitles.cues, host: here, offset: begins, language: subtitles.language);
        } catch (e) {
          logWarn('Cast: could not serve the subtitles: $e');
        }
      }
      return CastMedia(url: 'http://$here:$port$path', title: title, mime: const {'hls': 'application/vnd.apple.mpegurl', 'ts': 'video/mpeg', 'mkv': 'video/x-matroska'}[kind] ?? 'video/mp4', offset: begins, duration: duration, restart: from, subtitles: lines);
    }

    return from(start);
  }

  /// lumtub_core's relay, or the Dart one when it cannot start; null when
  /// neither can, and streams connect directly.
  Future<StreamRelay?> _startRelay() async {
    for (final relay in [if (NativeCore.instance case final core?) NativeRelay(core), ChunkedRelay()]) {
      try {
        await relay.start();
        if (relay is ChunkedRelay) logInfo('Using the Dart chunked relay');
        return relay;
      } catch (e) {
        logError('Could not start the local chunked relay', e);
      }
    }
    logInfo('Streams connect directly');
    return null;
  }
}
