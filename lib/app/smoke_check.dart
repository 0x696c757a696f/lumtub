part of 'app_controller.dart';

/// A check of the packaged app on a build machine, run only when
/// LUMTUB_SMOKE names a file to write the results to: it plays the video in
/// LUMTUB_SMOKE_VIDEO, then, if given, the YouTube video LUMTUB_SMOKE_YOUTUBE,
/// saves a picture of each and quits, with exit code 0 only when the local
/// video played.
extension SmokeCheck on AppController {
  static String? get _outFile => Platform.environment['LUMTUB_SMOKE'];

  static bool get requested => _outFile?.isNotEmpty == true;

  Future<void> runSmokeCheck() async {
    final out = File(_outFile!);
    final results = <String, Object?>{'version': appVersion, 'system': Platform.operatingSystemVersion};
    var passed = false;
    try {
      final player = this.player;
      if (player == null) throw StateError('No player: ${error ?? status}');
      final local = Platform.environment['LUMTUB_SMOKE_VIDEO'];
      if (local != null && local.isNotEmpty) {
        _ensureVideo(player);
        await player.open(Media(local));
        results['local'] = await _smokeWatch(player, '${out.path}.local.png');
        passed = (results['local'] as Map)['played'] == true;
      }
      final youtube = Platform.environment['LUMTUB_SMOKE_YOUTUBE'];
      if (youtube != null && youtube.isNotEmpty) {
        try {
          unawaited(play(VideoItem(id: youtube, title: youtube, channel: '', url: 'https://www.youtube.com/watch?v=$youtube')));
          results['youtube'] = await _smokeWatch(player, '${out.path}.youtube.png', wait: const Duration(seconds: 120));
        } catch (e) {
          results['youtube'] = {'played': false, 'error': '$e'};
        }
      }
    } catch (e, stack) {
      results['error'] = '$e\n$stack';
    }
    results['passed'] = passed;
    final text = const JsonEncoder.withIndent('  ').convert(results);
    logInfo('Smoke check: $text');
    await out.writeAsString(text);
    try {
      await shutdown(install: false).timeout(const Duration(seconds: 20));
    } catch (_) {}
    exit(passed ? 0 : 1);
  }

  /// Waits until [player] is three seconds into a video with a picture.
  Future<Map<String, Object?>> _smokeWatch(Player player, String picture, {Duration wait = const Duration(seconds: 60)}) async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < wait && !(player.state.position >= const Duration(seconds: 3) && (player.state.width ?? 0) > 0)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final played = player.state.position >= const Duration(seconds: 3) && (player.state.width ?? 0) > 0;
    final result = <String, Object?>{
      'played': played,
      'seconds': clock.elapsedMilliseconds / 1000,
      'position': player.state.position.inMilliseconds / 1000,
      'size': '${player.state.width}x${player.state.height}',
      'error': playbackError,
    };
    final native = player.platform;
    if (native is NativePlayer) {
      for (final name in ['hwdec-current', 'video-codec', 'current-vo', 'current-ao', 'path']) {
        try {
          result[name] = await native.getProperty(name);
        } catch (_) {}
      }
    }
    try {
      final shot = await player.screenshot(format: 'image/png');
      if (shot != null) await File(picture).writeAsBytes(shot);
      result['picture'] = shot?.length;
    } catch (e) {
      result['picture'] = '$e';
    }
    await player.stop();
    return result;
  }
}
