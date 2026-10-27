import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/player_settings.dart';
import 'package:lumtub/ui/lights_off.dart';
import 'package:lumtub/ui/pip_view.dart';
import 'package:lumtub/ui/player_controls.dart';
import 'package:lumtub/ui/theme.dart';
import 'package:lumtub/widgets/video_progress_bar.dart';

/// A player without libmpv: state changes are pushed through the streams
/// the controls listen to.
class FakePlayer implements Player {
  FakePlayer() {
    stream = PlayerStream(
      const Stream.empty(),
      _playing.stream,
      _completed.stream,
      _position.stream,
      const Stream.empty(),
      _volume.stream,
      _rate.stream,
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
      const Stream.empty(),
    );
  }

  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _volume = StreamController<double>.broadcast();
  final _rate = StreamController<double>.broadcast();

  @override
  PlayerState state = const PlayerState(duration: Duration(minutes: 10), position: Duration(minutes: 1), height: 1080, width: 1920);

  @override
  late final PlayerStream stream;

  final seeks = <Duration>[];

  @override
  PlatformPlayer? get platform => null;

  @override
  Future<void> playOrPause() async {
    state = state.copyWith(playing: !state.playing);
    _playing.add(state.playing);
  }

  @override
  Future<void> pause() async {
    state = state.copyWith(playing: false);
    _playing.add(false);
  }

  /// Unloads the video, as libmpv's stop does.
  @override
  Future<void> stop({bool open = false}) async {
    state = state.copyWith(playing: false);
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration duration) async {
    seeks.add(duration);
    state = state.copyWith(position: duration);
    _position.add(duration);
  }

  @override
  Future<void> setRate(double rate) async {
    state = state.copyWith(rate: rate);
    _rate.add(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume);
    _volume.add(volume);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppController controller;
  late FakePlayer player;

  setUp(() {
    controller = AppController();
    player = FakePlayer();
    controller.player = player;
    controller.playing = const VideoItem(id: 'dQw4w9WgXcQ', title: '测试视频标题', channel: '频道', url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Colors.red, Brightness.light),
      home: Scaffold(body: ColoredBox(color: Colors.black, child: PlayerControls(player: player, state: null, controller: controller))),
    ));
    await tester.pump();
  }

  testWidgets('shows the title, time and PiliNara bottom bar', (tester) async {
    await pump(tester);
    expect(find.text('测试视频标题'), findsOneWidget);
    expect(find.text('1:00 / 10:00'), findsOneWidget);
    expect(find.text('1X'), findsOneWidget, reason: '倍速');
    expect(find.text('1080P'), findsOneWidget, reason: '画质');
    expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the top bar is PiliNara\'s: back and home, then the switches', (tester) async {
    await pump(tester);
    for (final tip in ['返回', '主页', '投屏', '画中画', '更多设置']) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picture-in-picture buttons play, seek and show the way back', (tester) async {
    tester.view.physicalSize = const Size(498, 280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Colors.red, Brightness.light),
      home: Scaffold(body: ColoredBox(color: Colors.black, child: PipControls(controller: controller, player: player))),
    ));
    await tester.pump();
    expect(find.text('测试视频标题'), findsOneWidget);
    expect(find.byTooltip('退出画中画'), findsOneWidget);
    expect(find.byTooltip('主页'), findsNothing);
    await tester.tap(find.byTooltip('播放/暂停 (空格)'));
    await tester.pump();
    expect(player.state.playing, isTrue);
    await tester.tap(find.byIcon(Icons.pause_circle_rounded));
    await tester.pump();
    expect(player.state.playing, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the subtitle panel puts the first and second subtitle side by side', (tester) async {
    controller.details = const VideoDetails(title: '测试视频标题', channel: '频道', subtitles: [
      SubtitleOption(language: 'en', name: 'English', url: 'https://yt.example/api/timedtext?v=1&lang=en'),
      SubtitleOption(language: 'ja', name: '', url: 'https://yt.example/api/timedtext?v=1&lang=ja', kind: SubtitleKind.automatic),
      SubtitleOption(language: 'fr', name: '', url: 'https://yt.example/api/timedtext?v=1&lang=en&tlang=fr', kind: SubtitleKind.translated),
    ]);
    controller.settings = controller.settings.copyWith(subtitleLanguage: SubtitleLanguage.zh);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Colors.red, Brightness.light),
      home: Scaffold(body: ColoredBox(color: Colors.black, child: PlayerControls(player: player, state: null, controller: controller))),
    ));
    await tester.pump();
    await tester.tap(find.byTooltip('字幕'));
    await tester.pumpAndSettle();
    expect(find.text('第一字幕'), findsOneWidget);
    expect(find.text('第二字幕（上方）'), findsOneWidget);
    expect(find.text('视频自带'), findsNWidgets(2));
    // The automatic Japanese is the video's own language, first on each side.
    expect(find.text('原语言：日语（自动生成）'), findsNWidgets(2));
    expect(find.text('自动生成'), findsNothing);
    expect(find.text('简体中文（YouTube 翻译）'), findsNWidgets(2));
    // YouTube's translations wait behind a button on each side.
    expect(find.textContaining('法语'), findsNothing);
    await tester.tap(find.textContaining('更多语言').first);
    await tester.pump();
    expect(find.text('YouTube 自动翻译'), findsNWidgets(2));
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2), reason: 'both sides start off');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('第一字幕'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('字幕列表 opens from 更多设置 and asks for a subtitle first', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('更多设置'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('字幕列表'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('字幕列表'));
    await tester.pumpAndSettle();
    expect(find.text('先打开一条字幕'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the speed menu uses the speeds from settings', (tester) async {
    await pump(tester);
    await tester.tap(find.text('1X'));
    await tester.pumpAndSettle();
    for (final speed in ['0.5X', '0.75X', '1.25X', '1.5X', '1.75X', '2X', '3X']) {
      expect(find.text(speed), findsOneWidget);
    }
    await tester.tap(find.text('1.5X'));
    await tester.pumpAndSettle();
    expect(player.state.rate, 1.5);
    expect(find.text('1.5X'), findsOneWidget);
  });

  testWidgets('the fit choice in 更多设置 changes the picture fit', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('更多设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('16:9'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('16:9'));
    await tester.pumpAndSettle();
    expect(videoFit.value, VideoFit.ratio16x9);
    videoFit.value = VideoFit.contain;
  });

  testWidgets('clicking the progress bar seeks', (tester) async {
    await pump(tester);
    final bar = tester.getRect(find.byType(VideoProgressBar));
    await tester.tapAt(Offset(bar.left + bar.width / 2, bar.center.dy));
    await tester.pump();
    expect(player.seeks.single.inSeconds, closeTo(300, 2));
  });

  testWidgets('keys seek by the configured step and show feedback', (tester) async {
    await controller.savePreferences(controller.preferences.copyWith(seekSeconds: 7));
    await pump(tester);
    await tester.tap(find.byType(PlayerControls), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('快进7秒'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('快进7秒'), findsNothing);
  });

  testWidgets('the more panel applies choices and stays open', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('更多设置'));
    await tester.pumpAndSettle();
    final panel = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    for (final item in ['窗口置顶', '听视频', '空降助手', '播放信息', '镜像翻转', '画质', '画面比例']) {
      expect(find.text(item), findsWidgets, reason: item);
    }
    await tester.scrollUntilVisible(find.text('30 分钟'), 60, scrollable: panel);
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 分钟'));
    await tester.pumpAndSettle();
    expect(controller.sleepAt, isNotNull);
    // Still open, with the time left in the label.
    expect(find.textContaining('分钟后暂停'), findsOneWidget);
    await tester.ensureVisible(find.text('不开启'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不开启'));
    await tester.pumpAndSettle();
    expect(controller.sleepAt, isNull);
    for (final item in ['播放策略', '禁用视频编码', '字幕', '截图 (S)', '重载视频', '快捷键']) {
      await tester.scrollUntilVisible(find.text(item), 60, scrollable: panel);
      expect(find.text(item), findsWidgets, reason: item);
    }
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('播放策略'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wheel sets brightness on the left and volume on the right', (tester) async {
    await pump(tester);
    player.state = player.state.copyWith(volume: 50);
    final controls = tester.getRect(find.byType(PlayerControls));
    tester.binding.handlePointerEvent(PointerScrollEvent(position: controls.centerRight - const Offset(100, 0), scrollDelta: const Offset(0, -100)));
    await tester.pump();
    expect(player.state.volume, greaterThan(50));
    tester.binding.handlePointerEvent(PointerScrollEvent(timeStamp: const Duration(seconds: 1), position: controls.centerLeft + const Offset(100, 0), scrollDelta: const Offset(0, -100)));
    await tester.pump();
    expect(controller.brightness, 5);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl + wheel steps the speed instead of the volume', (tester) async {
    await pump(tester);
    player.state = player.state.copyWith(volume: 50, rate: 1);
    final controls = tester.getRect(find.byType(PlayerControls));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    tester.binding.handlePointerEvent(PointerScrollEvent(position: controls.centerRight - const Offset(100, 0), scrollDelta: const Offset(0, -100)));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(player.state.rate, greaterThan(1));
    expect(player.state.volume, 50);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the lights button toggles 关灯', (tester) async {
    await pump(tester);
    lightsOff.value = false;
    await tester.tap(find.byType(PlayerControls), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.byTooltip('关灯 (B)'));
    await tester.pump();
    expect(lightsOff.value, isTrue);
    expect(find.byTooltip('开灯 (B)'), findsOneWidget);
    lightsOff.value = false;
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a touch shows the lock, and locked taps do nothing', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(PlayerControls), warnIfMissed: false);
    await tester.pump();
    final playing = player.state.playing;
    await tester.tap(find.byTooltip('锁定'));
    await tester.pump();
    expect(find.byTooltip('解锁'), findsOneWidget);
    expect(find.byTooltip('更多设置'), findsNothing);
    await tester.tapAt(tester.getRect(find.byType(PlayerControls)).center + const Offset(150, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(player.state.playing, playing);
    await tester.tap(find.byTooltip('解锁'));
    await tester.pump();
    expect(find.byTooltip('更多设置'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a finger\'s double tap on the sides skips 10 s', (tester) async {
    await pump(tester);
    final rect = tester.getRect(find.byType(PlayerControls));
    Future<void> doubleTap(Offset at) async {
      await tester.tapAt(at, kind: PointerDeviceKind.touch);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at, kind: PointerDeviceKind.touch);
      await tester.pump(const Duration(milliseconds: 400));
    }

    await doubleTap(rect.centerRight - const Offset(60, 0));
    expect(player.seeks.last, const Duration(minutes: 1, seconds: 10));
    await doubleTap(rect.centerLeft + const Offset(60, 0));
    expect(player.seeks.last, const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });

  test('A-B loop: A, then B, then off; B before A swaps them', () async {
    player.state = player.state.copyWith(position: const Duration(seconds: 30));
    await controller.markLoop();
    expect(controller.loopA, const Duration(seconds: 30));
    expect(controller.loopB, isNull);
    player.state = player.state.copyWith(position: const Duration(seconds: 10));
    await controller.markLoop();
    expect((controller.loopA, controller.loopB), (const Duration(seconds: 10), const Duration(seconds: 30)));
    expect(player.seeks.last, const Duration(seconds: 10));
    await controller.markLoop();
    expect((controller.loopA, controller.loopB), (null, null));
  });
}
