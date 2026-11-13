part of 'app_controller.dart';

/// Seeking, live, the A-B loop, volume, quality and the sleep timer.
extension PlaybackControls on AppController {
  Future<void> toggleAudioOnly() async {
    final platform = player?.platform;
    if (platform is! NativePlayer) return;
    await platform.setProperty('vid', audioOnly ? 'auto' : 'no');
    _update(() => audioOnly = !audioOnly);
    _notice(audioOnly ? tr('Audio only; the picture is not decoded') : tr('Picture back on'));
  }

  Future<void> toggleSponsorBlock() async {
    await saveSettings(settings.copyWith(sponsorBlock: !settings.sponsorBlock));
    _notice(settings.sponsorBlock ? tr('SponsorBlock turned on') : tr('SponsorBlock turned off'));
  }

  /// Pauses playback after [after], or at the end of the current video when
  /// [afterCurrent]; null turns the timer off. From PiliNara's 定时关闭.
  void setSleepTimer(Duration? after, {bool afterCurrent = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = after == null ? null : Timer(after, () {
      unawaited(player?.pause());
      _update(() => sleepAt = null);
      _notice(tr('Sleep timer: playback paused'));
    });
    _update(() {
      sleepAt = after == null ? null : DateTime.now().add(after);
      sleepAfterCurrent = afterCurrent;
    });
  }

  /// yt-dlp's result for the playing video, when it was extracted already
  /// (storyboards and the replay heatmap come from it); null otherwise,
  /// for example when Piped or Invidious played it.
  Future<Map<String, dynamic>?> playingInfo() async {
    final id = playing?.id;
    final cached = id == null ? null : _repository?.streams.cached(id);
    if (cached == null) return null;
    try {
      return (await cached).info;
    } catch (_) {
      return null;
    }
  }

  /// Seeks by [offset], staying inside the video.
  Future<void> seekBy(Duration offset) async {
    final player = this.player;
    if (player == null) return;
    var target = player.state.position + offset;
    final duration = player.state.duration;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await seek(target);
  }

  /// Seeks the playing video to [target]. The split live stream holds only
  /// the fragments fetched so far, and a seek outside them would leave the
  /// decoder without a keyframe, broken until the next: forward then goes
  /// to the newest moment, backward stays where it is.
  Future<void> seek(Duration target) async {
    final player = this.player;
    if (player == null) return;
    if (_liveSplit != null && _liveSplit == playing?.id && !await _splitHolds(player, target)) {
      if (target > player.state.position) return goLive();
      _notice(tr('This live stream cannot go back further at this quality'));
      return;
    }
    await player.seek(target);
  }

  /// Whether libmpv's cache holds [target] of the split live stream.
  Future<bool> _splitHolds(Player player, Duration target) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return false;
    try {
      final cache = jsonDecode(await platform.getProperty('demuxer-cache-state'));
      final ranges = cache is Map ? cache['seekable-ranges'] : null;
      final at = target.inMilliseconds / 1000;
      return ranges is List && ranges.any((r) => r is Map && r['start'] is num && r['end'] is num && at >= (r['start'] as num) && at <= (r['end'] as num) - 1);
    } catch (_) {
      return false;
    }
  }

  /// Jumps a live stream to its newest moment, at normal speed, playing.
  /// The last seconds are left alone: libmpv at the very end of a live
  /// playlist waits for segments that do not exist yet.
  Future<void> goLive() async {
    final player = this.player;
    if (player == null) return;
    // The split stream cannot seek; it is opened again at the newest fragment.
    if (_liveSplit != null && _liveSplit == playing?.id) return reloadVideo();
    final duration = player.state.duration;
    if (duration > Duration.zero) {
      final target = duration - const Duration(seconds: 3);
      await player.seek(target < Duration.zero ? Duration.zero : target);
    }
    if (player.state.rate != 1) await player.setRate(1);
    if (!player.state.playing) await player.play();
  }

  /// Steps the A-B loop on at the current position: the first press marks
  /// A, the second B and starts the loop, the third clears it.
  Future<void> markLoop() async {
    final player = this.player;
    if (player == null) return;
    final now = player.state.position;
    if (loopA == null || loopB != null) {
      final clearing = loopB != null;
      _update(() {
        loopA = clearing ? null : now;
        loopB = null;
      });
      await _applyLoop();
      return;
    }
    // B before A swaps them, so the loop still runs forwards.
    final a = loopA!;
    _update(() {
      loopA = now < a ? now : a;
      loopB = now < a ? a : now;
    });
    if (loopB! - loopA! < const Duration(milliseconds: 500)) {
      _update(() => loopB = null);
      return;
    }
    await _applyLoop();
    await player.seek(loopA!);
  }

  Future<void> clearLoop() async {
    if (loopA == null && loopB == null) return;
    _update(() {
      loopA = null;
      loopB = null;
    });
    await _applyLoop();
  }

  Future<void> _applyLoop() async {
    final platform = player?.platform;
    if (platform is! NativePlayer) return;
    String at(Duration? d) => d == null || loopB == null ? 'no' : (d.inMilliseconds / 1000).toStringAsFixed(3);
    await platform.setProperty('ab-loop-a', at(loopA));
    await platform.setProperty('ab-loop-b', at(loopB));
  }

  /// Plays [item] at its channel's remembered speed and volume, else at
  /// 默认倍速 and the volume chosen last.
  Future<void> _applyChannelPlayback(VideoItem item, Player player) async {
    _playbackChannel = null;
    final key = ChannelPlayback.keyOf(item);
    final saved = preferences.rememberChannelPlayback && key != null ? channelPlayback?.of(key) : null;
    final rate = saved?.rate ?? settings.defaultSpeed;
    if (rate != player.state.rate) await player.setRate(rate);
    // Said once, so a speed that came back on its own is not a surprise.
    if (saved?.rate case final kept? when kept != settings.defaultSpeed) _notice(tr('This channel plays at its last speed, {0}x', [rateText(kept)]));
    final volume = saved?.volume?.toDouble() ?? _sessionVolume;
    if (volume != null && volume != player.state.volume) await player.setVolume(volume.clamp(0.0, settings.volumeMax.toDouble()).toDouble());
    if (this.player == player && playing?.id == item.id) _playbackChannel = key;
  }

  /// Keeps a speed or volume chosen while a channel plays for its next
  /// videos. Mute is not a volume to come back to.
  void _rememberPlayback({double? rate, double? volume}) {
    final key = _playbackChannel;
    if (volume != null && volume > 0 && key != null) _sessionVolume = volume;
    if (key == null || !preferences.rememberChannelPlayback) return;
    final store = channelPlayback;
    if (store == null) return;
    if (rate != null) {
      if (rate == store.of(key)?.rate) return;
      store.remember(key, rate: rate, forgetRate: rate == settings.defaultSpeed);
    } else if (volume != null && volume > 0 && volume.round() != store.of(key)?.volume) {
      store.remember(key, volume: volume.round());
    }
  }

  Future<void> changeVolume(double delta) async {
    final player = this.player;
    if (player != null) await player.setVolume((player.state.volume + delta).clamp(0.0, settings.volumeMax.toDouble()).toDouble());
  }

  /// Brightens or darkens the video by [delta] and returns the new value;
  /// saved, and shown to the rest of the app, once the changes pause, not
  /// at every wheel notch or slide step.
  Future<int> changeBrightness(int delta) async {
    final value = (brightness + delta).clamp(-pictureLimit('brightness'), pictureLimit('brightness'));
    settings = settings.copyWith(picture: {...settings.picture, 'brightness': value});
    _brightnessSave?.cancel();
    _brightnessSave = Timer(const Duration(seconds: 1), () {
      _update(() {});
      unawaited(_settingsStore?.save(settings));
    });
    final platform = player?.platform;
    if (platform is NativePlayer) await platform.setProperty('brightness', '$value');
    return value;
  }

  Future<void> toggleMute() async {
    final player = this.player;
    if (player == null) return;
    final volume = player.state.volume;
    if (volume > 0) {
      _volumeBeforeMute = volume;
      await player.setVolume(0);
    } else {
      await player.setVolume(_volumeBeforeMute);
    }
  }

  /// Saves the quality limit and reloads the current video where it was.
  /// Sets the quality cap; [asDefault] when it was chosen in the settings
  /// rather than for the video playing.
  Future<void> setMaxHeight(int height, {bool asDefault = false}) async {
    // 自动 again lifts the quality lowered for dropped frames.
    if (height == 0 && _droppedCap > 0) {
      _droppedCap = 0;
      if (settings.maxHeight == 0) return reloadVideo();
    }
    if (height == settings.maxHeight) return;
    // Automatic codecs follow the quality: above 1080p VP9 stays enabled.
    final next = settings.copyWith(maxHeight: height);
    if (height > 1080) {
      final usable = [VideoCodec.vp9, VideoCodec.av1].where((codec) => !next.disabledCodecs.contains(codec));
      if (usable.isEmpty) {
        if (asDefault) _notice(tr('VP9 and AV1 are both disabled, and H.264 stops at 1080p'));
      } else if (!usable.any((codec) => FormatPolicy.hardware(next, codec))) {
        _notice(tr('This PC cannot decode VP9 or AV1 in hardware, so 1440p and 4K are decoded on the CPU and use a lot of it'));
      }
    }
    await reloadVideo(next);
  }

  /// Saves [next], if given, and reopens the current video where it was,
  /// so format choices take effect at once.
  Future<void> reloadVideo([PlayerSettings? next]) async {
    if (next != null) await saveSettings(next);
    final item = playing;
    final player = this.player;
    if (item == null || player == null) return;
    final position = player.state.position;
    final wasPlaying = player.state.playing;
    _update(() => playbackError = null);
    if (await _open(item, _playSerial, start: position) && !wasPlaying) await player.pause();
  }

  /// The audio language the playing video is asked for: the one chosen for
  /// it here, else the one the settings give; empty for the original.
  String get audioLanguage => _audioLanguageFor(playing?.id);

  /// Plays the playing video in the audio language [language] ('' for its
  /// original sound) from where it is, for this video only.
  Future<void> chooseAudioLanguage(String language) async {
    final id = playing?.id;
    if (id == null) return;
    _audioPick = (id, language);
    await reloadVideo();
  }

  Future<void> setAutoplayNext(bool value) => setPlayOrder(value ? PlayOrder.autoPlayRelated : PlayOrder.pause);

  Future<void> setPlayOrder(PlayOrder order) => saveSettings(settings.copyWith(playOrder: order));
}
