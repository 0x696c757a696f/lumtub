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
  CastMedia? _media;
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
    _media = media;
    title = media.title;
    this.videoId = videoId;
    status = CastStatus(state: CastState.loading, position: media.offset + media.start, duration: media.duration ?? Duration.zero);
    _seenPlaying = false;
    _misses = 0;
    _startPolling();
    _notify();
  }

  Future<void> _refresh() async {
    final current = device;
    if (current == null) return;
    var next = await current.status();
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
    final media = _media;
    if (media != null && (media.offset > Duration.zero || media.duration != null)) {
      next = CastStatus(state: next.state, position: media.offset + next.position, duration: media.duration ?? next.duration);
    }
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
      logWarn('Cast action failed: $e');
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
        final restart = _media?.restart;
        if (restart != null) {
          // The stream the app joins cannot be seeked in; it starts again
          // from the keyframe before [position].
          final CastMedia media;
          try {
            media = await restart(position);
          } catch (e) {
            throw CastException('$e');
          }
          if (device != d) return;
          _seenPlaying = false;
          await d.load(media);
          _media = media;
          status = CastStatus(state: CastState.loading, position: media.offset, duration: media.duration ?? status?.duration ?? Duration.zero);
          return;
        }
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
    logInfo('Stopped casting to ${current.name}');
    return at;
  }

  /// Ends the session; the device is told to stop only with [stopDevice].
  Future<void> end({bool stopDevice = false}) async {
    _poll?.cancel();
    _poll = null;
    final current = device;
    device = null;
    _media = null;
    if (current != null) {
      try {
        await (stopDevice ? current.stop() : current.close());
      } on CastException catch (e) {
        logInfo('Error while ending the cast: $e');
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
