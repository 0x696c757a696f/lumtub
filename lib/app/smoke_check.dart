part of 'app_controller.dart';

/// A check of the packaged app on a build machine, run only when
/// LUMTUB_SMOKE names a file to write the results to: it plays the video in
/// LUMTUB_SMOKE_VIDEO, then, if given, the YouTube video LUMTUB_SMOKE_YOUTUBE,
/// saves a picture of each and quits, with exit code 0 only when the local
/// video played.
extension SmokeCheck on AppController {
  static String? get _outFile => Platform.environment['LUMTUB_SMOKE'];

  static bool get requested => _outFile?.isNotEmpty == true || _showcase?.isNotEmpty == true;

  /// A folder to fill with pictures of the main pages, for the README. The
  /// app asks for each picture by writing `want-<name>` there and waits for
  /// the build script to take it as `<name>.png`.
  static String? get _showcase => Platform.environment['LUMTUB_SHOWCASE'];

  Future<void> runShowcase() async {
    final folder = Directory(_showcase!);
    Future<void> shot(String name, {Duration settle = const Duration(seconds: 25)}) async {
      await Future<void>.delayed(settle);
      final want = File('${folder.path}/want-$name');
      final picture = File('${folder.path}/$name.png');
      await want.writeAsString(name);
      final clock = Stopwatch()..start();
      while (!picture.existsSync() && clock.elapsed < const Duration(seconds: 30)) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      logInfo('Showcase $name: ${picture.existsSync() ? 'taken' : 'missed'}');
    }

    try {
      for (final dark in [false, true]) {
        await saveAppearance(appearance.copyWith(themeMode: dark ? ThemeMode.dark : ThemeMode.light));
        final theme = dark ? 'dark' : 'light';
        navigate(PageMode.home);
        await shot('home-$theme', settle: Duration(seconds: dark ? 8 : 40));
        clearSearch();
        navigate(PageMode.explore);
        await shot('explore-$theme');
        if (dark) continue;
        await search('Blender open movie');
        await shot('search-$theme');
        openChannel(const ChannelRef('UCSMOQeBJ2RAnuFungnQOxLg', 'Blender'));
        await shot('channel-$theme');
        navigate(PageMode.settings);
        await shot('settings-$theme', settle: const Duration(seconds: 5));
      }
      if (Platform.environment['LUMTUB_TOUR'] == '1') {
        await _tour(folder);
      }
      final player = this.player;
      if (player != null) {
        unawaited(play(VideoItem(id: 'aqz-KE-bpKQ', title: 'Big Buck Bunny', channel: 'Blender', url: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ')));
        final clock = Stopwatch()..start();
        while (clock.elapsed < const Duration(seconds: 120) && player.state.position < const Duration(seconds: 5)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        await player.seek(const Duration(minutes: 1, seconds: 40));
        await shot('watch-dark', settle: const Duration(seconds: 12));
      }
    } catch (e) {
      logError('Showcase failed', e);
    }
    try {
      await shutdown(install: false).timeout(const Duration(seconds: 20));
    } catch (_) {}
    exit(0);
  }

  /// A recorded walk through the app's pages for the promo video; no video
  /// plays, as the build machine has no graphics card to play one smoothly.
  /// The build script starts recording to the file `rec-start` names and
  /// stops at `rec-stop`; it runs each `xdo-*` file's text as xdotool
  /// arguments on the window (%W stands for it). Each scene's start, in
  /// milliseconds since the recording began, goes to scenes.txt.
  Future<void> _tour(Directory folder) async {
    final scenes = File('${folder.path}/scenes.txt');
    final clock = Stopwatch();
    var step = 0;
    Future<void> wait(num seconds) => Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));
    Future<void> scene(String name) => scenes.writeAsString('$name ${clock.elapsedMilliseconds}\n', mode: FileMode.append);
    Future<void> signal(String name, [String text = '']) async {
      final file = File('${folder.path}/$name');
      await file.writeAsString(text);
      final waited = Stopwatch()..start();
      while (file.existsSync() && waited.elapsed < const Duration(seconds: 10)) {
        await wait(0.1);
      }
    }

    Future<void> xdo(String args) => signal('xdo-${(step++).toString().padLeft(3, '0')}', args);
    final start = appearance;
    try {
      await saveAppearance(start.copyWith(themeMode: ThemeMode.dark, palette: ''));
      navigate(PageMode.home);
      await wait(4);
      await signal('rec-start', 'tour.mp4');
      clock.start();
      await wait(1);

      await scene('home');
      await wait(1.5);
      await xdo('mousemove --window %W 640 420 click --repeat 5 --delay 400 5');
      await wait(2.5);
      await xdo('mousemove --window %W 640 420 click --repeat 5 --delay 300 4');

      clearSearch();
      navigate(PageMode.explore);
      await wait(0.5);
      await scene('explore');
      await wait(5);

      openChannel(const ChannelRef('UCSMOQeBJ2RAnuFungnQOxLg', 'Blender'));
      await wait(4);
      await scene('palettes');
      final looks = <(String, ThemeMode)>[
        ('', ThemeMode.light),
        ('ricePaper', ThemeMode.light),
        ('inkBamboo', ThemeMode.light),
        ('rime', ThemeMode.light),
        ('sandstone', ThemeMode.light),
        ('fallingPetals', ThemeMode.light),
        ('candlelight', ThemeMode.dark),
        ('nightVoyage', ThemeMode.dark),
        ('pineSoot', ThemeMode.dark),
        ('duskHills', ThemeMode.dark),
        ('', ThemeMode.dark),
      ];
      for (final (palette, mode) in looks) {
        await saveAppearance(appearance.copyWith(palette: palette, themeMode: mode));
        await wait(1.2);
      }

      navigate(PageMode.settings);
      await wait(1);
      await scene('languages');
      for (final tag in ['en', 'zh-Hans', 'ja', 'ko', 'es', 'fr', 'de', 'ru', 'ar', 'hi', 'pt', 'he', 'th', 'vi', 'uk', 'el', 'bn', 'fa', 'my', 'ka', 'am', 'eo', 'la', 'en']) {
        setLanguage(AppLanguage(tag));
        _update(() {});
        await wait(0.8);
      }
      await scene('end');
      await wait(1);
      await signal('rec-stop');
    } catch (e) {
      logError('Tour failed', e);
      await signal('rec-stop');
    }
    setLanguage(start.language);
    await saveAppearance(start);
  }

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
        // Reported only; YouTube often refuses build machines.
        try {
          final checks = await runNetworkCheck((_) {}).timeout(const Duration(minutes: 3));
          results['network'] = [for (final c in checks) '${c.name}: ${c.skipped ? 'skipped' : c.ok ? 'ok' : 'failed'} ${c.ms ?? ''} ms · ${c.route} · ${c.detail}'];
          final samples = await runPlaybackTest((_) {}, seconds: 5).timeout(const Duration(minutes: 4));
          results['playbackTest'] = [for (final s in samples) '${s.codec.label}: ${s.error ?? '${s.picture} ${s.decoder} cpu ${s.cpuPercent?.round()}% ${s.memoryMb} MB dropped ${s.dropped}'}'];
        } catch (e) {
          results['diagnostics'] = '$e';
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
