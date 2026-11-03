part of 'app_controller.dart';

/// Decoders, cropping and keeping the picture smooth: dropped frames, stalls and memory.
extension PictureHealth on AppController {
  /// Asks the GPU what it decodes in hardware, once per graphics adapter
  /// and driver: the automatic codecs follow the answer.
  Future<void> _measureDecoders() async {
    try {
      final json = await Isolate.run(NativeCore.hwDecodersNow);
      if (json == null || _disposed) return;
      final probe = jsonDecode(json) as Map<String, dynamic>;
      final adapter = probe['adapter']?.toString() ?? '';
      if (adapter.isEmpty) return;
      int height(String key) => (probe[key] as num?)?.toInt() ?? 0;
      final results = {
        for (final key in ['h264', 'vp9', 'av1']) key: height(key) >= 1080 ? DecoderStatus.hardware(Platform.isWindows ? 'd3d11va' : 'vaapi') : const DecoderStatus.software(),
      };
      // Asked again at every start: a result saved earlier may have been
      // a one-off, such as a video decoded in software after the graphics
      // device was lost, and the automatic codecs would stay off for good.
      final same = adapter == settings.decoderAdapter &&
          results.entries.every((e) => (settings.decoderResults[e.key]?.isHardware ?? false) == e.value.isHardware);
      if (same) return;
      logInfo('Hardware decoding on $adapter: H.264 ${height('h264')}p, VP9 ${height('vp9')}p, AV1 ${height('av1')}p');
      _update(() => decodeStates = results);
      settings = settings.copyWith(decoderResults: results, decoderAdapter: adapter);
      await _settingsStore?.save(settings);
    } catch (e) {
      logError('Could not ask the GPU what it decodes', e);
    }
  }

  Future<void> inspectCurrentDecoder({Duration delay = Duration.zero}) async {
    final platform = player?.platform;
    if (platform is! NativePlayer) {
      _notice(tr('当前播放器无法读取 libmpv 解码状态。'));
      return;
    }
    try {
      await Future<void>.delayed(delay);
      final codec = (await platform.getProperty('video-codec')).trim().toLowerCase();
      final decoder = DecoderStatus.fromMpv(await platform.getProperty('hwdec-current'));
      final normalized = DecoderStatus.codecKey(codec);
      _update(() {
        currentCodec = codec.isEmpty ? tr('尚未验证') : codec;
        currentHwdec = decoder.label;
        if (normalized != null) decodeStates = {...decodeStates, normalized: decoder};
      });
      await _fitCrop(platform, hardware: decoder.kind == DecoderKind.hardware);
      // Kept as what this PC can do only when it decoded in hardware, or
      // nothing measured it: one video in software, as after a lost
      // graphics device or with hardware decoding off, says nothing about
      // the GPU.
      final measured = normalized != null && settings.decoderAdapter.isNotEmpty && (settings.decoderResults[normalized]?.isHardware ?? false);
      if (normalized != null && !(measured && decoder.kind != DecoderKind.hardware)) {
        settings = settings.copyWith(decoderResults: {...settings.decoderResults, normalized: decoder});
        unawaited(_settingsStore?.save(settings));
      }
      // A download older than its codec in the sidecar: only libmpv can
      // tell it is in a codec the playback rules disable.
      final item = playing;
      final fileCodec = VideoCodec.of(normalized);
      if (item != null && _openedLocal == item.id && !FormatPolicy.allows(settings, fileCodec)) {
        logWarn('The download of ${item.id} is ${fileCodec!.label}, a codec the playback rules disable; playing online instead');
        _notice(tr('下载的文件是 {0} 编码，已按播放规则改为在线播放', [fileCodec.label]));
        unawaited(_open(item, _playSerial, start: player?.state.position, allowLocal: false));
      }
    } catch (_) {
      _update(() => currentHwdec = tr('尚未验证'));
    }
  }

  /// Sets the `video-crop` for the picture now decoded. Set every time, as
  /// a crop kept from an earlier picture of another size is ignored.
  Future<void> _fitCrop(NativePlayer platform, {required bool hardware}) async {
    final width = int.tryParse(await platform.getProperty('video-params/w')) ?? 0;
    final height = int.tryParse(await platform.getProperty('video-params/h')) ?? 0;
    final crop = DecoderStatus.paddingCrop(width, height, hardware: hardware, fast: _fastScaling);
    await platform.setProperty('video-crop', crop);
    if (crop.isNotEmpty) logDebug(() => 'Cropping $crop of ${width}x$height to keep the decoder padding off the picture');
  }

  /// The picture changed size within a video (another quality): its crop
  /// is fitted again once the size has settled.
  void _refitCrop(Player player) {
    final platform = player.platform;
    if (_cropFitting || _decoderPending || platform is! NativePlayer) return;
    _cropFitting = true;
    unawaited(Future<void>.delayed(const Duration(milliseconds: 300), () async {
      _cropFitting = false;
      if (!identical(player, this.player)) return;
      final hardware = DecoderStatus.fromMpv(await platform.getProperty('hwdec-current')).kind == DecoderKind.hardware;
      await _fitCrop(platform, hardware: hardware);
    }).catchError((Object _) {}));
  }

  /// Logs playback timing when frames are being dropped, at most once a
  /// minute, so the log shows why a video stutters.
  Future<void> _checkDrops() async {
    final platform = player?.platform;
    if (platform is! NativePlayer || _tracking == null || !(player?.state.playing ?? false)) return;
    await _logMemory(platform);
    try {
      final drops = int.tryParse(await platform.getProperty('frame-drop-count')) ?? 0;
      final added = drops - _lastDrops;
      _lastDrops = drops;
      // Read every time, so the timings cover these 10 seconds.
      final frames = await _frameStats(platform);
      await _watchPicture(platform, frames);
      if (DateTime.now().difference(_openedAt) >= const Duration(seconds: 20)) {
        await _lightenIfBusy(platform, frames);
        await _stepDownIfDropping(platform, added);
      }
      if (added < 20 || DateTime.now().difference(_lastDropLog) < const Duration(minutes: 1)) {
        // Smooth playback is logged too, every few minutes, so a stutter can
        // be compared with how the same machine plays normally.
        if (frames != null && DateTime.now().difference(_lastFrameLog) >= const Duration(minutes: 3)) {
          _lastFrameLog = DateTime.now();
          logDebug(() => 'Frames in 10 s, $added dropped: $frames');
        }
        return;
      }
      _lastDropLog = DateTime.now();
      final values = <String>[];
      for (final name in ['avsync', 'estimated-vf-fps', 'container-fps', 'display-fps', 'vo-delayed-frame-count', 'mistimed-frame-count', 'decoder-frame-drop-count', 'hwdec-current', 'video-sync', 'speed', 'video-params/w', 'video-params/h', 'time-pos', 'audio-pts', 'audio-params/samplerate', 'audio-out-params/samplerate', 'current-ao', 'd3d11va-zero-copy', 'vd-lavc-dr', 'video-codec', 'video-out-params/pixelformat']) {
        values.add('$name=${await platform.getProperty(name)}');
      }
      logDebug(() => 'Dropped $added frames in 10 s ($drops total): ${values.join(' ')}${frames == null ? '' : ' · frames $frames'}');
    } catch (_) {
      // Statistics are best effort.
    }
  }

  /// Brings back a picture that stopped while the sound plays on: when no
  /// frame was drawn in 10 s, the decoder is restarted from here; when
  /// frames were drawn but none reached the screen, the texture is
  /// registered again. Only while the video is on screen, at most once a
  /// minute.
  Future<void> _watchPicture(NativePlayer platform, String? frames) async {
    final match = frames == null ? null : RegExp(r'frames=(\d+)/(\d+)').firstMatch(frames);
    final outputSize = _outputSize;
    if (match == null || outputSize == null || !outputSize.onScreen || audioOnly || _backgroundAudioOnly || _windowHidden) return;
    if ((player?.state.width ?? 0) == 0 || DateTime.now().difference(_lastPictureFix) < const Duration(minutes: 1)) return;
    final drawn = int.parse(match[1]!), shown = int.parse(match[2]!);
    if (drawn > 0 && shown > 0) return;
    _lastPictureFix = DateTime.now();
    // A video stream that broke off, or a restart that brought nothing
    // back, needs the video opened again at the same place.
    if (drawn == 0 && (_streamLostIn == _playSerial || _pictureRestartedIn == _playSerial)) {
      logWarn('Picture stalled while playing ($frames); the video stream is gone, reopening');
      _pictureRestartedIn = null;
      _streamLostIn = null;
      unawaited(_recover('The video stream stopped while the sound played on'));
      return;
    }
    logWarn('Picture stalled while playing ($frames); ${drawn == 0 ? 'restarting the decoder' : 'registering the texture again'}');
    try {
      if (drawn == 0) {
        _pictureRestartedIn = _playSerial;
        await platform.command(['seek', '0', 'relative+exact']);
      } else {
        await outputSize.refresh();
      }
    } catch (e) {
      logWarn('Could not bring the picture back: $e');
    }
  }

  /// Whether mpv scales the cheap way: 低资源占用优先, or [_lightRendering].
  bool get _fastScaling => _lightRendering != null || (settings.strategy == PlaybackStrategy.lowResource && !settings.customOptions.containsKey('scale'));

  /// In 智能自动, switches mpv to the cheapest scaling (as 低资源占用优先
  /// does) on battery or with battery saver, and once drawing a frame takes
  /// most of its time: on a weak or busy GPU the filters cost dropped
  /// frames, and at window size the difference is hard to see.
  Future<void> _lightenIfBusy(NativePlayer platform, String? frames) async {
    final player = this.player;
    if (player == null) return;
    if (_lightRendering == 'battery' && !Power.saving) {
      _lightRendering = null;
      await PlayerOptionApplicator.apply(player, settings);
      _applied = settings;
      _refitCrop(player);
      logInfo('Plugged in again; scaling back to normal');
      return;
    }
    // Filters the person turned on are kept.
    if (_lightRendering != null || settings.strategy != PlaybackStrategy.auto || settings.scale != const PlayerSettings().scale || settings.deband || settings.interpolation) return;
    String reason;
    if (Power.saving) {
      reason = 'battery';
    } else {
      final busy = frames == null ? null : drawBusy(frames, double.tryParse(await platform.getProperty('container-fps')) ?? 0);
      if (busy == null) return;
      reason = 'busy';
      logDebug(() => 'Frames take ${busy.toStringAsFixed(1)} ms to draw, most of their time');
    }
    _lightRendering = reason;
    for (final MapEntry(:key, :value) in PlayerOptionApplicator.fastRendering.entries) {
      if (settings.customOptions.containsKey(key)) continue;
      try {
        await platform.setProperty(key, value);
      } catch (_) {}
    }
    _refitCrop(player);
    logInfo(reason == 'battery' ? 'On battery; scaling switched to the fast kind' : 'Scaling switched to the fast kind');
  }

  /// With automatic quality, a video that keeps dropping frames (a tenth
  /// of them for 30 seconds, after the cheap scaling above) is reopened one
  /// quality lower, such as 1080p60 at 720p60, and later videos of this run
  /// stay at most there. Choosing 自动 again lifts it.
  Future<void> _stepDownIfDropping(NativePlayer platform, int added) async {
    if (settings.maxHeight != 0 || settings.strategy == PlaybackStrategy.quality) return;
    final fps = double.tryParse(await platform.getProperty('container-fps')) ?? 0;
    _dropStreak = fps > 0 && added >= fps ? _dropStreak + 1 : 0;
    if (_dropStreak < 3) return;
    _dropStreak = 0;
    final height = int.tryParse(await platform.getProperty('video-params/h')) ?? 0;
    final lower = stepDownHeight(height, availableHeights);
    if (lower == null) return;
    _droppedCap = lower;
    logWarn('Frames kept dropping at ${height}p${fps.round()}; automatic quality lowered to ${lower}p for this run');
    _notice(tr('播放一直掉帧，自动画质已降到 {0}p（本次运行有效，重新选“自动”可恢复）', ['$lower']));
    await reloadVideo();
  }

  Future<String?> _frameStats(NativePlayer platform) async {
    try {
      final stats = await AppController._videoChannel.invokeMethod<String>('VideoOutputManager.Stats', {'handle': '${await platform.handle}'});
      return stats == null || stats.isEmpty ? null : stats;
    } catch (_) {
      // An older plugin without timings.
      return null;
    }
  }

  /// Logs the app's memory and what libmpv's cache holds every two minutes
  /// while a video plays, so the log shows where memory goes.
  Future<void> _logMemory(NativePlayer platform) async {
    if (DateTime.now().difference(_lastMemoryLog) < const Duration(minutes: 2)) return;
    _lastMemoryLog = DateTime.now();
    try {
      String mb(Object? bytes) => bytes is num ? '${(bytes / (1 << 20)).round()} MB' : '?';
      final cache = jsonDecode(await platform.getProperty('demuxer-cache-state'));
      final ahead = cache is Map ? cache['fw-bytes'] : null;
      final total = cache is Map ? cache['total-bytes'] : null;
      final values = <String>[];
      for (final name in ['video-params/w', 'video-params/h', 'video-codec', 'hwdec-current', 'video-out-params/pixelformat']) {
        values.add('$name=${await platform.getProperty(name)}');
      }
      logDebug(() => 'Memory: process ${mb(ProcessInfo.currentRss)} (peak ${mb(ProcessInfo.maxRss)}) · playback cache ${mb(total)} (ahead ${mb(ahead)}) · image cache ${mb(PaintingBinding.instance.imageCache.currentSizeBytes)} · ${values.join(' ')}');
    } catch (_) {
      // Statistics are best effort.
    }
  }

  Future<void> _readWindowsVideoInfo() async {
    final info = await WindowsVideoInfo.read();
    _update(() => windowsVideoInfo = info);
  }

  /// Reads optional Windows Media Foundation codec extensions only when the
  /// decoder-status settings section is opened. libmpv itself does not use
  /// these extensions.
  void refreshWindowsVideoInfo() => unawaited(_readWindowsVideoInfo());
}
