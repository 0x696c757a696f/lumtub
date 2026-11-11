part of 'app_controller.dart';

/// Starting a video, following the player while it plays, and stopping it.
extension PlaybackEvents on AppController {
  /// Plays [item]; [from] is the list it was picked from and becomes the queue.
  /// Opens [item] on the watch page; [at] is where to start, else where
  /// it was left off. [keepMini] plays it in the mini player when that is
  /// where the last video was (the queue moving on by itself).
  Future<void> play(VideoItem item, {List<VideoItem>? from, PlayingList? list, Duration? at, bool keepMini = false, bool retryingStart = false}) async {
    final player = this.player;
    if (player == null) return;
    if (mini && playing?.id == item.id && at == null && !retryingStart) return expandMini();
    _ensureVideo(player);
    _startTimer?.cancel();
    if (!retryingStart) _startAttempts = 0;
    // A loop belongs to the video it was set in.
    if (playing?.id != item.id) unawaited(clearLoop());
    if (playing?.id != item.id) {
      _shownOptions.clear();
      unawaited(cast.stop());
      if (playing case final left?) {
        _played.removeWhere((v) => v.id == left.id);
        _played.add(left);
        if (_played.length > 50) _played.removeAt(0);
      }
      _remember();
      _finishWatching();
      _watching = item;
    }
    unawaited(account?.loadRating(item.id));
    _saveProgress();
    _countWatchTime(flush: true);
    _playbackChannel = null;
    _stopCurrentChat();
    final serial = ++_playSerial;
    _recoveryTimer?.cancel();
    _recovery.reset();
    final resume = preferences.resumePlayback ? library?.progressOf(item.id) : null;
    final start = at ?? (resume != null && resume.resumable ? resume.position : null);
    _update(() {
      playing = item;
      mini = keepMini && mini;
      if (list != null) {
        playingList = list;
        queue = List.unmodifiable(list.ordered);
      } else if (from != null) {
        playingList = null;
        queue = List.unmodifiable(from);
      }
      // A stream being waited for keeps saying so until it plays.
      if (!retryingStart) {
        playbackError = null;
        _waitingForStart = false;
      }
      details = null;
      loadingDetails = true;
      replayChat = const [];
      chatTicker = const [];
      loadingReplayChat = false;
      replayChatError = null;
      availableHeights = const [];
      availableFrameRates = const {};
      related?.dispose();
      related = null;
      _segments = const [];
      _skipped.clear();
      dislikes = null;
    });
    _syncDanmaku();
    _subtitlesSerial = serial;
    _subtitlesReady = Completer<void>();
    unawaited(_loadDetails(item, serial));
    if (settings.returnDislike) unawaited(_loadDislikes(item, serial));
    if (settings.sponsorBlock) unawaited(_loadSegments(item, serial));
    // Another video asked for meanwhile takes over its history and queue.
    // Held until a translated subtitle shown by itself is ready, so the
    // first lines are not missed; other subtitles load as it plays.
    final hold = preferences.autoPlay && settings.subtitleMode != SubtitleMode.off && !item.isLive;
    // Listened for before opening, so a length reported while it opens
    // still counts, and the last video's never does.
    final length = item.duration == null && !item.isLive ? player.stream.duration.firstWhere((length) => length > Duration.zero).timeout(const Duration(minutes: 1)) : null;
    unawaited(length?.then((_) {}, onError: (_) {}));
    if (await _open(item, serial, start: start, play: preferences.autoPlay && !hold) && serial == _playSerial) {
      if (hold) unawaited(_playOnceSubtitlesReady(serial));
      await _applyChannelPlayback(item, player);
      unawaited(_syncSilenceSkipping(player));
      // Marked live while it opened, when the list did not know.
      final opened = playing?.id == item.id ? playing! : item;
      if (preferences.recordHistory && !incognito) {
        await _history?.record(opened);
        // A link or a list without lengths leaves the card without one; the
        // player's own length is taken once this video reports it.
        if (length != null && opened.duration == null && !opened.isLive) unawaited(_fillDuration(opened.id, serial, length));
      }
      if (start != null && at == null) _notice(tr('Resume from {0}', [AppController._clock(start)]));
      final next = upNext.firstOrNull;
      if (next != null) prefetch(next);
      if (opened.isLive) {
        _startCurrentChat(opened, serial);
      } else if (item.liveStatus == 'was_live') {
        unawaited(_loadReplayChat(item, serial));
      }
    }
  }

  /// Records where the current video is, so it can resume later.
  /// [now] writes it to disk at once, for when playback stops.
  void _saveProgress({bool now = false}) {
    final item = _tracking;
    final player = this.player;
    if (item == null || player == null || !preferences.recordProgress || incognito) return;
    final duration = player.state.duration;
    if (duration <= Duration.zero) return;
    library?.recordProgress(item.id, player.state.position, duration);
    if (now) unawaited(library?.flush());
  }

  Future<void> _loadSegments(VideoItem item, int serial) async {
    try {
      final local = await downloads?.localVideo(item.id);
      final saved = [for (final s in local?.segments ?? const <SkipSegment>[]) if (settings.sponsorCategories.contains(s.category)) s];
      final segments = saved.isNotEmpty ? saved : await _sponsorBlock.segments(item.id, settings.sponsorCategories);
      if (serial == _playSerial) _update(() => _segments = segments);
    } catch (_) {
      // Playback does not depend on SponsorBlock being reachable.
    }
  }

  Future<void> _loadDislikes(VideoItem item, int serial) async {
    try {
      final count = await _returnDislike.votes(item.id);
      if (serial == _playSerial) _update(() => dislikes = count);
    } catch (_) {
      // The page shows the likes without it.
    }
  }

  void _skipSegments(Duration position) {
    for (final segment in _segments) {
      if (_skipped.contains(segment) || !segment.contains(position)) continue;
      // Each segment is skipped once, so seeking back into it plays it.
      _skipped.add(segment);
      unawaited(player?.seek(segment.end));
      if (settings.sponsorNotice) _notice(tr('Skipped {0}', [sponsorCategories[segment.category] ?? tr('Segments')]));
      return;
    }
  }

  Future<void> retryPlayback() async {
    final item = playing;
    if (item != null) await play(item);
  }

  void _listenTo(Player player) {
    void videoSize(_) {
      _outputSize?.video = Size((player.state.width ?? 0).toDouble(), (player.state.height ?? 0).toDouble());
      if ((player.state.width ?? 0) > 0) _refitCrop(player);
    }
    final platform = player.platform;
    if (platform is NativePlayer) {
      // The subtitles shown are followed as mpv reports them, as it can
      // change either by itself; the panel and the list read them here.
      // media_kit waits for these listeners before it reads the next mpv
      // event, so they only schedule the work: awaiting the player here
      // would stall playback (and deadlock on the player's lock).
      unawaited(platform.observeProperty('sid', (_) async => _followSubtitles(player)).catchError((Object e) => logWarn('Could not follow the subtitle: $e')));
      unawaited(platform.observeProperty('secondary-sid', (value) async {
        secondaryTrackId = value.isEmpty || value == 'false' ? 'no' : value;
        _followSubtitles(player);
      }).catchError((Object e) => logWarn('Could not follow the second subtitle: $e')));
      // Only schedules the speed change, like the listeners above.
      unawaited(platform.observeProperty(SilenceSkipper.property, (value) async => _onSilenceMetadata(player, value)).catchError((Object e) => logWarn('Could not watch for silence: $e')));
    }
    _playerSubscriptions.addAll([
      player.stream.width.listen(videoSize),
      player.stream.height.listen(videoSize),
      // While libmpv draws subtitles, the second one moves up as the main
      // one gains lines, as the Flutter view stacks them.
      player.stream.subtitle.listen((lines) => _placeSecondary(player, lines)),
      player.stream.playing.listen((_) {
        _updateEfficiency();
        _countWatchTime();
      }),
      player.stream.rate.listen((rate) {
        if (_silence.observeRate(rate)) _rememberPlayback(rate: rate);
      }),
      player.stream.volume.listen((volume) => _rememberPlayback(volume: volume)),
      // A second of playback proves a downloaded libmpv works on this PC.
      player.stream.position.listen((position) {
        if (_tracking == null) return;
        if (position > Duration.zero) {
          if (waitingForStart) {
            _update(() {
              _waitingForStart = false;
              playbackError = null;
            });
          }
          if (_recovery.observeProgress(position,
            playing: player.state.playing,
            buffering: player.state.buffering,
            decoded: audioOnly || _backgroundAudioOnly || (player.state.width ?? 0) > 0,
            rate: player.state.rate,
          )) {
            _recoveryTimer?.cancel();
            logInfo('Playback recovered after ten seconds of decoded progress');
          }
          _lastPosition = position;
          _resumePoint.observe(position, rate: player.state.rate);
        }
        if (_decoderPending && position > const Duration(milliseconds: 500) && (player.state.width ?? 0) > 0) {
          _decoderPending = false;
          unawaited(inspectCurrentDecoder(delay: const Duration(milliseconds: 500)));
        }
        if (_segments.isNotEmpty && settings.sponsorBlock) _skipSegments(position);
        _countWatchTime();
        final now = DateTime.now();
        if (now.difference(_lastProgressSave) > const Duration(seconds: 5)) {
          _lastProgressSave = now;
          _saveProgress();
        }
        if (_libmpvConfirmed || position < const Duration(seconds: 1)) return;
        _libmpvConfirmed = true;
        unawaited(_tools?.libmpv.confirm());
      }),
      player.stream.completed.listen((done) {
        if (!done || playing == null) return;
        // A live stream through the relay ends only when its fragments
        // stopped coming.
        if (_tracking != null && (_liveSplit == _tracking!.id || PlaybackRecovery.endedEarly(_lastPosition, player.state.duration))) {
          unawaited(_recover(tr('Video ended unexpectedly at {0}', [AppController._clock(_lastPosition)])));
          return;
        }
        _saveProgress();
        unawaited(_playAfterEnd());
      }),
      // libmpv reports failures that happen after open() returned, such as
      // yt-dlp finding no playable format, only through this stream. Errors
      // once the video has loaded (a broken subtitle track) are not fatal.
      player.stream.error.listen((message) {
        if (playing == null || message.isEmpty) return;
        if (isSubtitleError(message)) {
          logWarn('Subtitles failed to load, video keeps playing: $message');
          return;
        }
        // FFmpeg may log the HTTP status before naming the request. Keep
        // it diagnostic-only; media URL failures, EOF and stalls drive recovery.
        if (isUnattributedHttpError(message)) return;
        _onPlayerError(player, message, loaded: player.state.duration > Duration.zero);
      }),
      // libmpv's warnings go to the log, a limited number per video, so
      // problems such as dropped frames can be read after the fact.
      player.stream.log.listen((log) {
        final text = log.text.trim();
        final subtitle = isSubtitleError(text) || log.prefix == 'sub' || log.prefix.startsWith('sub/');
        if ((log.level == 'error' || log.prefix == 'ytdl_hook') && _recentErrors.length < 20 && !subtitle && !isUnattributedHttpError(text)) _recentErrors.add(text);
        // curl gave up on a stream; when it was the video's, the sound
        // plays on over the last picture.
        final lost = log.prefix == 'curl' && text.startsWith('transfer failed');
        if (lost) _streamLostIn = _playSerial;
        // Data cut off mid-frame, after curl lost a stream, leaves the
        // decoder failing on every frame over a still picture.
        if (log.prefix == 'vd' && text.startsWith('Error while decoding frame')) {
          final now = DateTime.now();
          _decodeErrors
            ..add(now)
            ..removeWhere((at) => now.difference(at) > const Duration(seconds: 10));
        }
        // Opened again at once rather than after the picture watch notices.
        if ((lost || _decodeErrors.length >= 3) && player.state.playing && DateTime.now().difference(_lastBrokenReopen) > const Duration(seconds: 30)) {
          _lastBrokenReopen = DateTime.now();
          _decodeErrors.clear();
          unawaited(_recover(lost ? 'libmpv gave up on a stream' : 'The video data broke and frames stopped decoding'));
        }
        if (PlaybackRecovery.graphicsLost(text)) unawaited(_remakeVideoOutput(player, text));
        // The same line for every frame says nothing new.
        if (text == _lastMpvLine) return;
        _lastMpvLine = text;
        if (_mpvLogLines >= (AppLog.level == LogLevel.debug ? 2000 : 200)) return;
        _mpvLogLines++;
        final line = 'mpv [${log.prefix}] ${log.level}: $text';
        switch (log.level) {
          case 'fatal' || 'error':
            logError(line);
          case 'warn':
            logWarn(line);
          default:
            logDebug(() => line);
        }
      }),
      // A stream that stops delivering data leaves mpv buffering forever.
      player.stream.buffering.listen((buffering) {
        _stallTimer?.cancel();
        if (!buffering || _tracking == null) return;
        _stallTimer = Timer(PlaybackRecovery.stallTimeout, () {
          if (player.state.buffering && player.state.playing) unawaited(_recover('No buffering progress for over ${PlaybackRecovery.stallTimeout.inSeconds} seconds'));
        });
      }),
    ]);
  }

  /// An mpv error that was not about a subtitle.
  void _onPlayerError(Player player, String message, {required bool loaded}) {
    if (!loaded) {
      final item = playing!;
      final viaRelay = _openedVia == item.id;
      _openedVia = null;
      // What a server's address says is not what YouTube said earlier.
      final failure = PlaybackFailure.classify(viaRelay ? [message] : [message, ..._recentErrors]);
      final position = _lastPosition > Duration.zero ? _lastPosition : null;
      if (viaRelay) {
        if (!failure.retryable && !_mayFallBack(failure.kind)) {
          _fail(item, failure);
          return;
        }
        final limited = _youtubeRefused;
        logWarn('Piped or Invidious address did not play ($message); ${limited != null ? 'trying the next server' : 'connecting to YouTube directly'}');
        unawaited(limited != null ? _fallBack(item, _playSerial, limited, start: position) : _open(item, _playSerial, start: position, piped: false));
        return;
      }
      if (!failure.retryable) {
        _mayFallBack(failure.kind) ? unawaited(_fallBack(item, _playSerial, failure, start: position)) : _fail(item, failure);
        return;
      }
      if (_openedResolved == item.id) {
        // Addresses resolved ahead may have gone stale; let libmpv's
        // ytdl_hook resolve the video itself once.
        _openedResolved = null;
        _repository?.streams.forget(item.id);
        logWarn('Prefetched address did not play ($message; $_openedOrigin); libmpv resolves ${item.id} again');
        unawaited(_open(item, _playSerial, start: _lastPosition > Duration.zero ? _lastPosition : null, resolved: false));
        return;
      }
      // Resolved again and still refused: the servers are the last way.
      _mayFallBack(failure.kind) ? unawaited(_fallBack(item, _playSerial, failure, start: position)) : _fail(item, failure);
    } else if (PlaybackRecovery.isNetworkError(message)) {
      final failure = PlaybackFailure.classify([message, ..._recentErrors]);
      if (failure.retryable) {
        unawaited(_recover(message));
      } else {
        _fail(playing!, failure);
      }
    }
  }

  /// Follows [PlayerSettings.playOrder] once a video ends. Single cycle is
  /// mpv's loop-file, so a looping video never ends.
  Future<void> _playAfterEnd() async {
    final done = playing;
    if (done != null && preferences.watchLaterAutoRemove) library?.removeWatchLater(done.id);
    if (sleepAfterCurrent) {
      _update(() => sleepAfterCurrent = false);
      _notice(tr('Sleep timer: current video finished'));
      return;
    }
    if (await playQueued()) return;
    switch (settings.playOrder) {
      case PlayOrder.pause || PlayOrder.singleCycle:
        return;
      case PlayOrder.listOrder:
        if (upNext.isNotEmpty) await play(upNext.first, keepMini: true);
      case PlayOrder.listCycle:
        if (upNext.isNotEmpty) {
          await play(upNext.first, keepMini: true);
        } else if (queue.isNotEmpty) {
          await play(queue.first, keepMini: true, at: mini && queue.first.id == playing?.id ? Duration.zero : null);
        } else if (playing != null) {
          await play(playing!, keepMini: true, at: Duration.zero);
        }
      case PlayOrder.autoPlayRelated:
        await playNext(keepMini: true);
    }
  }

  /// Hidden and not playing, Lumtub runs in Windows' efficiency mode; any
  /// playback (a media key while hidden, too) turns it off.
  void _updateEfficiency() {
    final on = _windowHidden && !(player?.state.playing ?? false);
    if (on == _efficient) return;
    _efficient = on;
    NativeCore.efficiencyMode(on);
  }

  /// While the window is minimised or in the tray with the setting on, mpv
  /// decodes no picture; [hidden] false brings it back. A user's own 听视频
  /// choice is left alone.
  Future<void> setBackgroundAudioOnly(bool hidden) async {
    _outputSize?.hidden = hidden;
    _windowHidden = hidden;
    _updateEfficiency();
    final platform = player?.platform;
    if (platform is! NativePlayer) return;
    if (hidden) {
      if (!preferences.audioOnlyInBackground || audioOnly || _backgroundAudioOnly || !player!.state.playing) return;
      _backgroundAudioOnly = true;
      await platform.setProperty('vid', 'no');
    } else if (_backgroundAudioOnly) {
      _backgroundAudioOnly = false;
      if (audioOnly) return;
      await platform.setProperty('vid', 'auto');
      // The decoder starts again at the next keyframe, which in a stream can
      // be far off: until then the last picture stays. An exact seek to
      // here decodes up to now at once.
      try {
        await platform.command(['seek', '0', 'relative+exact']);
      } catch (e) {
        logWarn('Could not refresh the picture after restoring: $e');
      }
    }
  }

  /// Counts the time played up to now into 观看统计, before it is shown.
  void flushWatchTime() => _countWatchTime(flush: true);

  /// Adds the time played since the last call to 观看统计, a minute or
  /// a pause at a time; nothing in 无痕模式 or with history off.
  void _countWatchTime({bool flush = false}) {
    final player = this.player;
    final item = _tracking;
    final now = DateTime.now();
    final last = _watchTick;
    final playing = player != null && player.state.playing && !player.state.buffering && item != null;
    _watchTick = playing ? now : null;
    if (last != null) {
      final gap = now.difference(last).inMilliseconds;
      // A long gap is a sleep or a stall, not watching.
      if (gap > 0 && gap < 5000) _watchMs += gap;
    }
    if (_watchMs < 60000 && !(flush || !playing) || _watchMs < 1000) return;
    final seconds = _watchMs ~/ 1000;
    _watchMs -= seconds * 1000;
    final key = item == null ? null : ChannelPlayback.keyOf(item);
    if (key == null || !preferences.recordHistory || incognito) return;
    watchTime?.add(key, item!.channel, seconds);
  }

  /// Stops the video and closes the watch page or the mini player.
  void stopWatching() {
    _stopCurrentChat();
    setPip(false);
    _finishWatching();
    _saveProgress(now: true);
    _countWatchTime(flush: true);
    _playbackChannel = null;
    _tracking = null;
    _recoveryTimer?.cancel();
    _startTimer?.cancel();
    _recovery.reset();
    ++_playSerial;
    _update(() {
      playing = null;
      mini = false;
      playbackError = null;
      _waitingForStart = false;
    });
    _unload();
  }

  /// Closes the video in libmpv rather than pausing it, so its cache,
  /// decoded frames and textures are freed, then hands the freed memory back
  /// to the system. Coming back to the video opens it again where it was left.
  void _unload() {
    final player = this.player;
    if (player == null) return;
    unawaited(player.stop().then((_) => releaseMemory()));
  }

  /// Hands memory freed by closed videos back to the system.
  void releaseMemory() {
    final before = ProcessInfo.currentRss;
    releaseFreedMemory();
    logDebug(() => 'Released idle memory: ${before >> 20} MB → ${ProcessInfo.currentRss >> 20} MB');
  }
}
