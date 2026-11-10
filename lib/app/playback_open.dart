part of 'app_controller.dart';

/// Opening a video in libmpv: the sources it can come from, the fallbacks, and recovery after failures.
extension PlaybackOpening on AppController {
  /// Opens [item] with the current format settings, from [start] if given.
  ///
  /// The video is resolved by yt-dlp first, usually already done for the
  /// watch page or while the pointer rested on its card. libmpv then plays
  /// the picked streams directly, or has its ytdl_hook pick formats and
  /// subtitles from the saved extraction without asking YouTube again.
  /// [resolved] false, or a failed resolution, leaves everything to
  /// ytdl_hook as before.
  Future<void> _fillDuration(String id, int serial, Future<Duration> reported) async {
    try {
      final length = await reported;
      if (serial == _playSerial && playing?.id == id) await _history?.fillDuration(id, length.inSeconds);
    } on Object {
      // Never reported: the card stays without a length.
    }
  }

  Future<bool> _open(VideoItem item, int serial, {Duration? start, bool play = true, bool resolved = true, bool piped = true, bool allowLocal = true}) async {
    // Opened again (reconnecting, another quality): the subtitles shown
    // come back, as the new file starts with none of the ones added.
    final kept = _tracking?.id == item.id ? _shownSubtitles() : null;
    final opened = await _openOnce(item, serial, start: start, play: play, resolved: resolved, piped: piped, allowLocal: allowLocal);
    if (opened && kept != null) unawaited(_restoreSubtitles(kept, serial));
    return opened;
  }

  /// The subtitles shown now: the main one by its label (empty: turned
  /// off) and the second one.
  ({String? main, SubtitleOption? second}) _shownSubtitles() {
    final track = player?.state.track.subtitle;
    final main = track == null || track.id == 'auto' ? null : track.id == 'no' ? '' : track.title;
    return (main: main, second: secondarySubtitle);
  }

  /// Gets the first video ready while nothing else happens: reads the
  /// player's files from disk once they may be cold after an update,
  /// probes the hardware decoders, and makes the picture output when the
  /// mouse and keyboard have been still for a moment. Opening a video
  /// first does whatever is still left there and then.
  Future<void> _warmUp(Player player) async {
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (_disposed) return;
    final read = Stopwatch()..start();
    final folder = File(Platform.resolvedExecutable).parent.path;
    final mpv = paths?.mpv;
    // Android's executable is the system's app_process, in a folder apps may not list.
    final bytes = Platform.isAndroid || Platform.isIOS ? 0 : await Isolate.run(_readingPlayerFiles(folder, mpv));
    logDebug(() => 'Read ${bytes >> 20} MB of player files in ${read.elapsedMilliseconds} ms');
    final directories = this.directories;
    if (directories != null) {
      try {
        final shaders = Directory('${directories.cache.path}${Platform.pathSeparator}shaders').listSync().whereType<File>().length;
        logDebug(() => 'Shader cache holds $shaders shaders');
      } catch (e) {
        logDebug(() => 'Could not count the shader cache: $e');
      }
    }
    await _measureDecoders();
    var lastInput = DateTime.now();
    void touched(PointerEvent _) => lastInput = DateTime.now();
    bool pressed(KeyEvent _) {
      lastInput = DateTime.now();
      return false;
    }

    GestureBinding.instance.pointerRouter.addGlobalRoute(touched);
    HardwareKeyboard.instance.addHandler(pressed);
    try {
      while (!_disposed && videoController == null && this.player == player) {
        final still = DateTime.now().difference(lastInput);
        if (still >= const Duration(milliseconds: 1500)) {
          _ensureVideo(player);
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500) - still);
      }
    } finally {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(touched);
      HardwareKeyboard.instance.removeHandler(pressed);
    }
  }

  /// Makes the video's picture output, from [_warmUp] or when the first
  /// video plays. Made right at start it held up drawing the window for
  /// most of a second.
  void _ensureVideo(Player player) {
    if (videoController != null) return;
    final made = Stopwatch()..start();
    final controller = videoController = VideoController(player, configuration: VideoControllerConfiguration(hwdec: settings.hwdec));
    // It is made after the next frame, and an idle window draws none.
    WidgetsBinding.instance.scheduleFrame();
    unawaited(controller.platform.future.then((_) => logDebug(() => 'Video output made in ${made.elapsedMilliseconds} ms'), onError: (Object error) => logError('Video output failed', error)));
  }

  Future<bool> _openOnce(VideoItem item, int serial, {Duration? start, bool play = true, bool resolved = true, bool piped = true, bool allowLocal = true}) async {
    final player = this.player!;
    _ensureVideo(player);
    try {
      if (!_libmpvConfirmed) await _tools?.libmpv.markPlaying();
      if (settings.proxyMode == ProxyMode.system) await _refreshProxy(ifStale: true);
      final local = allowLocal && resolved && piped && !item.isLive ? await downloads?.localVideo(item.id) : null;
      _openedLocal = null;
      // A download in a codec the playback rules disable (AV1 decoded in
      // software, say) streams instead, in a codec the rules allow.
      final localCodec = local?.videoCodec;
      if (local != null && !FormatPolicy.allows(settings, localCodec)) {
        logWarn('The download of ${item.id} is ${localCodec!.label}, a codec the playback rules disable; playing online instead');
        _notice(tr('The downloaded file is {0}, which the playback rules disable; streaming instead', [localCodec.label]));
      } else if (local != null) {
        return await _openLocal(item, serial, local, start: start, play: play);
      }
      final format = _format;
      final formatSort = _formatSort;
      _openedVia = null;
      if (resolved && piped) {
        _recentErrors.clear();
        _relaysTried.clear();
        _youtubeRefused = null;
      }
      // Piped or Invidious first, as chosen in 播放来源.
      if (piped) {
        if (await _openViaRelays(item, serial, start: start, play: play)) return true;
        if (serial != _playSerial) return false;
      }
      ResolvedVideo? video;
      if (resolved) {
        try {
          final streams = _repository!.streams;
          // Android asks the core first: yt-dlp runs in Python there, which
          // costs a phone seconds of work, so it only steps in when the core
          // has no answer, and for live and members-only videos.
          if (Platform.isAndroid) {
            if (!item.isLive && !item.membersOnly) {
              try {
                video = await streams.quick(item.id, format, FormatPolicy.settingsJson(_playback));
              } catch (e) {
                logWarn('Quick start of ${item.id} failed: $e');
              }
            }
            if (video == null && streams.ytDlpPath.isEmpty) {
              throw StateError(item.isLive || item.membersOnly ? 'Live streams and members-only videos need yt-dlp, which could not be started' : 'YouTube gave no streams this version can play');
            }
          }
          var pending = video != null ? Future.value(video) : streams.resolve(item.id, format, formatSort: formatSort, membersOnly: item.membersOnly, live: item.isLive);
          // The first open of a video also asks YouTube directly; whichever
          // answers first starts it. A reopen after a failure waits for yt-dlp.
          if (video == null && !Platform.isAndroid && _quickSerial != serial && !item.isLive && !item.membersOnly && !streams.resolved(item.id, format)) {
            _quickSerial = serial;
            final full = pending;
            pending = Future.any([
              full,
              streams.quick(item.id, format, FormatPolicy.settingsJson(_playback)).then((quick) {
                if (quick == null) return full;
                streams.unhurried(item.id);
                return quick;
              }),
            ]);
          }
          video = await pending;
        } catch (e) {
          _recentErrors.add('$e');
          final failure = PlaybackFailure.classify(['$e']);
          if (!failure.retryable) {
            // libmpv's ytdl_hook would ask YouTube again and fail the same way.
            if (AppController._serversMayHelp(failure.kind)) return await _fallBack(item, serial, failure, start: start, play: play);
            if (serial == _playSerial) _fail(item, failure);
            return false;
          }
          // libmpv cannot start yt-dlp on Android.
          if (Platform.isAndroid) {
            if (serial == _playSerial) _fail(item, failure);
            return false;
          }
          logError('Prefetching ${item.id} failed, letting libmpv resolve it', e);
        }
        if (serial != _playSerial) return false;
      }
      // A list may not know a video is live; yt-dlp does.
      if (!item.isLive && video?.info['live_status'] == 'is_live') {
        item = item.withLiveStatus('is_live');
        if (playing?.id == item.id) _update(() => playing = item);
      }
      final live = item.isLive;
      // A live stream starts at its live edge, not at a remembered spot.
      if (live) start = null;
      // Through the relay, which reaches YouTube as libmpv would: directly
      // or through the proxy, a SOCKS one too.
      // A video whose stream broke through it is reopened without it.
      final relay = _unrelayed != item.id ? _relay : null;
      final agent = video?.userAgent;
      // Subtitles are added by the app (see _autoSubtitles), so they do not
      // need ytdl_hook: through it libmpv reads the streams itself, slowly
      // once its cache is full, and YouTube cuts those connections.
      final direct = video != null && video.format == format && !live
          ? video.directAddress(relay: relay == null ? null : (url, size) => relay.register(url, size: size, userAgent: agent, proxy: proxy.url))
          : null;
      _relayed = direct != null && relay != null ? item.id : null;
      _openedDirect = direct != null ? item.id : null;
      final split = live && video != null && relay != null && _liveSplitOff != item.id ? _liveSplitAddress(video, relay) : null;
      _liveSplit = split != null ? item.id : null;
      // Which TLS carries the streams: only the core's relay uses the
      // post-quantum setting.
      final path = split != null || _relayed == item.id
          ? (relay is NativeRelay ? "the core's relay" : "the Dart relay")
          : direct != null
              ? "libmpv's own connection"
              : "libmpv and yt-dlp's own connections";
      logInfo('Streams of ${item.id} go through $path');
      final platform = player.platform;
      if (platform is NativePlayer) {
        // A live stream plays from one HLS stream with picture and sound
        // together up to 1080p: a picture and a sound stream apart can
        // drift out of sync, so they are taken only above it.
        await platform.setProperty('ytdl-format', live ? FormatPolicy.liveExpression(_playback, format) : format);
        await platform.setProperty('ytdl-raw-options', PlayerOptionApplicator.ytdlRawOptions(settings, infoJson: direct == null ? video?.file.path : null, proxy: proxy.ytDlpValue(settings.proxyMode), formatSort: _formatSort));
        if (direct != null && agent != null) await platform.setProperty('user-agent', agent);
        // The relay asks YouTube in chunks and reads each reply to its end
        // itself; libmpv asking it in small pieces would only cut those
        // chunks short.
        await platform.setProperty('curl-max-request-size', _relayed == item.id ? '64MiB' : PlayerOptionApplicator.curlRequestSize);
      }
      _tracking = null;
      if (secondarySubtitle != null) {
        secondarySubtitle = null;
        if (platform is NativePlayer) unawaited(SecondarySubtitle.off(platform).catchError((_) {}));
      }
      _lastPosition = start ?? Duration.zero;
      _resumePoint.start(_lastPosition);
      _openedResolved = video == null ? null : item.id;
      _openedOrigin = video?.origin;
      if (video != null) {
        _update(() {
          availableHeights = video!.heightsFor(settings);
          availableFrameRates = video.frameRatesFor(settings);
        });
      }
      await AppController._forgetCrop(player);
      await player.open(Media(direct ?? split ?? item.url, start: start), play: play);
      if (serial == _playSerial) _tracking = item;
      _mpvLogLines = 0;
      _lastDrops = 0;
      _dropStreak = 0;
      _openedAt = DateTime.now();
      _openIssued = item.id;
      // The decoder is known once frames are shown; resolving the video
      // can take longer than any fixed delay.
      _decoderPending = true;
      _update(() {});
      return true;
    } catch (e) {
      logError('Could not open video ${item.id}', e);
      if (serial == _playSerial) _fail(item, PlaybackFailure.classify(['$e', ..._recentErrors]));
      return false;
    }
  }

  /// An mpv address playing [video]'s live picture above 1080p with its
  /// sound through [relay], or null when there is none within the cap.
  String? _liveSplitAddress(ResolvedVideo video, StreamRelay relay) {
    final split = LiveSplit.pick(video.info, _playback);
    if (split == null) return null;
    final pair = '${video.info['id']}-${DateTime.now().microsecondsSinceEpoch}';
    final proxy = this.proxy.url;
    final picture = relay.registerLive(split.videoUrl, pair: pair, userAgent: split.userAgent, proxy: proxy);
    final sound = relay.registerLive(split.audioUrl, pair: pair, userAgent: split.userAgent, proxy: proxy);
    if (picture == null || sound == null) return null;
    logInfo('Live ${video.info['id']} plays ${split.label} through the relay');
    return NativeCore.instance?.edl([picture, sound]);
  }

  /// Plays the downloaded file of [item] instead of asking YouTube.
  Future<bool> _openLocal(VideoItem item, int serial, LocalVideo local, {Duration? start, bool play = true}) async {
    final player = this.player!;
    _recentErrors.clear();
    _openedVia = null;
    _openedResolved = null;
    _tracking = null;
    if (secondarySubtitle != null) {
      secondarySubtitle = null;
      final platform = player.platform;
      if (platform is NativePlayer) unawaited(SecondarySubtitle.off(platform).catchError((_) {}));
    }
    _lastPosition = start ?? Duration.zero;
    _resumePoint.start(_lastPosition);
    _openedLocal = item.id;
    await AppController._forgetCrop(player);
    await player.open(Media(local.file.path, start: start), play: play);
    if (serial == _playSerial) _tracking = item;
    _mpvLogLines = 0;
    _lastDrops = 0;
    _dropStreak = 0;
    _openedAt = DateTime.now();
    _openIssued = item.id;
    _decoderPending = true;
    _update(() {});
    unawaited(_addLocalSubtitles(local, serial));
    return true;
  }

  /// The server network to try next for [item], or null for YouTube.
  /// Normally the one 播放来源 names, and only without subtitles, which
  /// these servers do not give libmpv. After YouTube refused the video
  /// (429, a bot check, a challenge yt-dlp could not solve, or an error
  /// that remained after resolving again) both are tried (that one first),
  /// subtitles or not, since playing beats failing.
  RelayKind? _nextRelay(VideoItem item) {
    if (item.isLive) return null;
    final preferred = settings.playbackSource.relay;
    final candidates = _youtubeRefused != null
        ? [if (preferred != null) preferred, ...RelayKind.values.where((k) => k != preferred)]
        : [if (preferred != null && settings.subtitleMode == SubtitleMode.off) preferred];
    return candidates.where((k) => !_relaysTried.contains(k)).firstOrNull;
  }

  /// Opens [item] from the next server [_nextRelay] names, moving on to the
  /// one after when a server cannot resolve it; false when none plays it.
  Future<bool> _openViaRelays(VideoItem item, int serial, {Duration? start, bool play = true}) async {
    final player = this.player!;
    while (true) {
      final kind = _nextRelay(item);
      if (kind == null) return false;
      _relaysTried.add(kind);
      final address = await _relayAddress(item, kind);
      if (serial != _playSerial) return false;
      if (address == null) continue;
      _tracking = null;
      _lastPosition = start ?? Duration.zero;
      _resumePoint.start(_lastPosition);
      _openedResolved = null;
      _openedVia = item.id;
      await AppController._forgetCrop(player);
      await player.open(Media(address, start: start), play: play);
      if (serial == _playSerial) _tracking = item;
      _mpvLogLines = 0;
      _lastDrops = 0;
      _dropStreak = 0;
      _openedAt = DateTime.now();
      _openIssued = item.id;
      _decoderPending = true;
      _update(() {});
      return true;
    }
  }

  /// YouTube would not play [item]: plays it from the Piped or Invidious
  /// server not yet tried, and only when there is none shows the error.
  Future<bool> _fallBack(VideoItem item, int serial, PlaybackFailure failure, {Duration? start, bool play = true}) async {
    if (failure.kind == FailureKind.rateLimited) _rateLimitedUntil = DateTime.now().add(const Duration(minutes: 10));
    if (_youtubeRefused == null) logWarn('YouTube would not play ${item.id} (${failure.kind.name}); trying Piped and Invidious');
    _youtubeRefused = failure;
    if (await _openViaRelays(item, serial, start: start, play: play)) return true;
    if (serial == _playSerial) _fail(item, PlaybackFailure(failure.kind, failure.detail, tried: [for (final k in _relaysTried) k == RelayKind.piped ? 'Piped' : 'Invidious']));
    return false;
  }

  /// The play address for [item] from a [kind] server, or null to go on.
  Future<String?> _relayAddress(VideoItem item, RelayKind kind) async {
    final watch = Stopwatch()..start();
    final name = kind == RelayKind.piped ? 'Piped' : 'Invidious';
    try {
      final source = settings.playbackSource;
      final named = source.relay == kind && source.isCustom ? (kind == RelayKind.piped ? settings.pipedServer : settings.invidiousServer) : '';
      final server = named.isEmpty ? null : named;
      final video = await (kind == RelayKind.piped ? _piped.fetch(item.id, server: server) : _invidious.fetch(item.id, server: server));
      final address = video.edl(_playback);
      if (address == null) return null;
      _update(() {
        availableHeights = video.heightsFor(settings);
        availableFrameRates = const {};
      });
      logInfo('Playing ${item.id} from $name ${video.server}, took ${watch.elapsedMilliseconds} ms');
      return address;
    } catch (e) {
      logWarn('$e; not using $name');
      return null;
    }
  }

  /// Shows why [item] cannot play and acts on the cause.
  void _fail(VideoItem item, PlaybackFailure failure) {
    _recoveryTimer?.cancel();
    _recovery.cancelPending();
    logError('Playback failed ${item.id} (${failure.kind.name}): ${failure.detail}');
    if (failure.kind == FailureKind.noFormat) failure = PlaybackFailure(failure.kind, failure.detail, disabled: FormatPolicy.disabledNames(settings));
    if (failure.kind == FailureKind.membersOnly) failure = PlaybackFailure(failure.kind, failure.detail, signedIn: webSignIn?.signedIn == true);
    switch (failure.kind) {
      case FailureKind.rateLimited:
        _rateLimitedUntil = DateTime.now().add(const Duration(minutes: 10));
      case FailureKind.challenge:
        if (!_updateCheckedForChallenge) {
          _updateCheckedForChallenge = true;
          unawaited(checkUpdates());
        }
      case FailureKind.upcoming:
        _waitForStart(item);
      default:
    }
    _update(() {
      playbackError = failure.message;
      _waitingForStart = failure.kind == FailureKind.upcoming;
    });
  }

  /// Opens [item] again once it may have started: at its scheduled time
  /// when that is still ahead, otherwise every half minute, then less often.
  void _waitForStart(VideoItem item) {
    _startTimer?.cancel();
    final serial = _playSerial;
    final scheduled = (playing?.id == item.id ? scheduledStart : item.scheduledStart)?.difference(DateTime.now());
    final delay = scheduled != null && scheduled > const Duration(minutes: 1)
        ? scheduled + const Duration(seconds: 15)
        : Duration(seconds: min(30 * (1 << min(_startAttempts, 2)), 120));
    _startAttempts++;
    logWarn('${item.id} has not started, opening it again in ${delay.inSeconds} s');
    _startTimer = Timer(delay, () {
      if (_disposed || serial != _playSerial || playing?.id != item.id || !waitingForStart) return;
      unawaited(play(item, keepMini: true, retryingStart: true));
    });
  }

  /// Reopens the current video where it stopped after the network failed,
  /// or shows [message] once the attempts are used up.
  Future<void> _recover(String message) async {
    final item = _tracking;
    if (item == null || _recovering) return;
    final position = _resumePoint.beforeFailure;
    if (!_recovery.tryAttempt(position: position)) {
      logError('Playback interrupted, gave up reconnecting ${item.id}: $message');
      _fail(item, PlaybackFailure.classify([message, ..._recentErrors]));
      return;
    }
    logWarn('Playback interrupted, reconnecting ${item.id} at ${AppController._clock(position)}: $message');
    if (_relayed == item.id) {
      _unrelayed = item.id;
      logWarn('Playing ${item.id} without the local chunked relay');
    }
    // A split live stream that broke at once twice is played from HLS; one
    // that played a while, or broke once, gets new addresses and stays
    // split.
    if (_liveSplit == item.id && DateTime.now().difference(_openedAt) < const Duration(minutes: 1)) {
      if (_liveSplitBroke == item.id) {
        _liveSplitOff = item.id;
        logWarn('Playing live ${item.id} from HLS, up to 1080p');
      } else {
        _liveSplitBroke = item.id;
      }
    }
    _notice(tr('Connection lost, reconnecting from {0}…', [AppController._clock(position)]));
    _recovering = true;
    _recoveryTimer?.cancel();
    final serial = _playSerial;
    try {
      // A new open also asks yt-dlp again, which replaces stream addresses
      // that expired while the video sat paused.
      _repository?.streams.forget(item.id);
      final opened = await _open(item, serial, start: position);
      if (!opened || serial != _playSerial) return;
      _recoveryTimer = Timer.periodic(PlaybackRecovery.stallTimeout, (_) {
        if (serial != _playSerial || !_recovery.awaitingProgress) {
          _recoveryTimer?.cancel();
        } else if (_recovery.stalled && player!.state.playing) {
          unawaited(_recover('Playback did not advance after reopening'));
        }
      });
    } finally {
      _recovering = false;
    }
  }

  /// The graphics device went away (a driver reset, say), so libmpv's
  /// hardware-decoded frames no longer reach the picture, which flickers or
  /// freezes. The video output is made again, on a new Direct3D device, and
  /// the video reopened where it was. When that happens again soon after,
  /// hardware decoding stays off until Lumtub restarts.
  Future<void> _remakeVideoOutput(Player player, String reason) async {
    final old = videoController;
    if (_remakingOutput || _disposed || old == null || this.player != player) return;
    _remakingOutput = true;
    final item = _tracking ?? playing;
    final position = _lastPosition;
    final now = DateTime.now();
    _outputRemade.removeWhere((at) => now.difference(at) > const Duration(minutes: 10));
    if (_outputRemade.length >= 3) {
      if (_outputRemade.length == 3) {
        _outputRemade.add(now);
        logError('The graphics device keeps getting lost; leaving the video output as it is', reason);
        _notice(tr('The graphics driver keeps resetting; please restart Lumtub'));
      }
      _remakingOutput = false;
      return;
    }
    final again = _outputRemade.isNotEmpty;
    logWarn('The graphics device was lost ($reason); making the video output again${again ? ' and decoding in software' : ''}');
    _recovering = true;
    try {
      await player.pause();
      await old.release();
      if (_disposed || this.player != player) return;
      videoController = null;
      _ensureVideo(player);
      _outputRemade.add(now);
      _update(() {});
      _notice(again ? tr('The graphics driver reset again; decoding in software until Lumtub restarts') : tr('The graphics driver reset; the picture was made again'));
      await videoController?.platform.future;
      // Making the output sets hwdec from the settings again.
      final platform = player.platform;
      if (again && platform is NativePlayer) await platform.setProperty('hwdec', 'no');
      if (item != null && !_disposed && playing?.id == item.id) await _open(item, _playSerial, start: position > Duration.zero ? position : null);
    } catch (e) {
      logError('Could not make the video output again', e);
    } finally {
      _recovering = false;
      _remakingOutput = false;
    }
  }
}
