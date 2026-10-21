import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_log.dart';
import 'cast_device.dart';

/// The one cast session at a time: the device, what it last reported, and
/// the controls the casting bar uses. Polls the device while it is active.
class CastController extends ChangeNotifier {
  CastDevice? device;
  CastStatus? status;
  /// The last failure, in a short message; cleared by the next action.
  String? error;
  /// The title being cast.
  String? title;
  /// The id of the video being cast.
  String? videoId;
  Timer? _poll;
  var _seenPlaying = false;
  var _misses = 0;
  var _disposed = false;
  var _hidden = false;

  /// How often the device is asked for its status: slower while the window
  /// is hidden, when nobody sees the progress bar.
  Duration get pollInterval => Duration(seconds: _hidden ? 5 : 1);

  /// Whether the app window is hidden or minimised.
  set windowHidden(bool value) {
    if (_hidden == value) return;
    _hidden = value;
    if (_poll != null) _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(pollInterval, (_) => unawaited(_refresh()));
  }

  bool get active => device != null;

  /// Casts [media] to [target], replacing any session; throws
  /// [CastException] when the device refuses.
  Future<void> start(CastDevice target, CastMedia media, {String? videoId}) async {
    await end();
    error = null;
    try {
      await target.load(media);
    } catch (e) {
      await target.close();
      throw e is CastException ? e : CastException('$e');
    }
    device = target;
    title = media.title;
    this.videoId = videoId;
    status = CastStatus(state: CastState.loading, position: media.start);
    _seenPlaying = false;
    _misses = 0;
    _startPolling();
    _notify();
  }

  Future<void> _refresh() async {
    final current = device;
    if (current == null) return;
    final next = await current.status();
    if (device != current) return;
    if (next == null) {
      // A device that stays silent has gone away.
      if (++_misses >= 8) {
        error = 'connection lost';
        await end();
      }
      return;
    }
    _misses = 0;
    if (next.state == CastState.playing) _seenPlaying = true;
    if (next.state == CastState.stopped && _seenPlaying) {
      // Finished on the device, or stopped with its remote.
      await end();
      return;
    }
    status = next;
    _notify();
  }

  Future<void> _run(Future<void> Function(CastDevice device) action) async {
    final current = device;
    if (current == null) return;
    error = null;
    try {
      await action(current);
    } on CastException catch (e) {
      logInfo('投屏操作失败：$e');
      error = e.message;
    }
    _notify();
  }

  /// Pauses or resumes the device, by what it last reported.
  Future<void> togglePlay() => _run((d) async {
        final playing = status?.state == CastState.playing;
        await (playing ? d.pause() : d.play());
        final s = status;
        if (s != null) status = CastStatus(state: playing ? CastState.paused : CastState.playing, position: s.position, duration: s.duration);
      });

  Future<void> seek(Duration position) => _run((d) async {
        await d.seek(position);
        final s = status;
        if (s != null) status = CastStatus(state: s.state, position: position, duration: s.duration);
      });

  /// Stops the device and ends the session; returns where it was, so local
  /// playback can carry on from there.
  Future<Duration?> stop() async {
    final current = device;
    if (current == null) return null;
    final at = status?.position;
    await end(stopDevice: true);
    logInfo('已停止投屏到 ${current.name}');
    return at;
  }

  /// Ends the session; the device is told to stop only with [stopDevice].
  Future<void> end({bool stopDevice = false}) async {
    _poll?.cancel();
    _poll = null;
    final current = device;
    device = null;
    if (current != null) {
      try {
        await (stopDevice ? current.stop() : current.close());
      } on CastException catch (e) {
        logInfo('结束投屏时出错：$e');
      }
    }
    status = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    unawaited(device?.close());
    super.dispose();
  }
}
