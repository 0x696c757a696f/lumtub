import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:media_kit_video/media_kit_video.dart';

import '../app/app_controller.dart';
import '../app_preferences.dart';
import '../l10n/l10n.dart';
import 'lights_off.dart';
import 'theater_mode.dart';

/// Keys shown in the shortcut help, in display order, with the steps from
/// [prefs].
List<(String, String)> playerShortcutHelp(AppPreferences prefs) => [
      (tr('空格 / K'), tr('播放或暂停')),
      ('← / →', tr('后退或前进 {0} 秒', [prefs.seekSeconds])),
      ('J / L', tr('后退或前进 {0} 秒', [prefs.longSeekSeconds])),
      ('↑ / ↓', tr('音量加减 {0}%', [prefs.volumeStep])),
      ('Shift + < / >', tr('减速或加速播放')),
      (tr('按住画面'), tr('临时 2 倍速')),
      (tr('Ctrl + 滚轮'), tr('减速或加速播放')),
      ('M', tr('静音')),
      ('F', tr('全屏')),
      ('Esc', tr('退出全屏')),
      ('Shift + N / ]', tr('下一个视频')),
      ('Shift + P / [', tr('上一个视频')),
      (', / .', tr('暂停时逐帧后退或前进')),
      ('0 - 9', tr('跳到视频的 0% - 90%')),
      ('Home / End', tr('跳到开头或结尾')),
      ('A / D', tr('上一句或下一句字幕')),
      ('R', tr('重听这一句')),
      ('Ctrl + C', tr('复制当前字幕')),
      ('T', tr('剧场模式')),
      ('B', tr('关灯')),
      ('S', tr('截图')),
      ('I', tr('显示或隐藏播放统计')),
      (tr('Alt + ← / 鼠标后退键'), tr('返回上一页')),
      ('Ctrl + K', tr('搜索')),
    ];

/// Player key bindings, used both on the watch page and inside the player
/// controls, which keep focus while the video is fullscreen. [onFeedback]
/// is told what a key did, for the indicator over the video.
Map<ShortcutActivator, VoidCallback> playerShortcuts(AppController controller, VideoState? Function() video, {void Function(IconData icon, String text)? onFeedback, VoidCallback? onScreenshot}) {
  final player = controller.player;
  final prefs = controller.preferences;
  if (player == null || !prefs.keyboardShortcuts) return const {};
  final volume = prefs.volumeStep.toDouble();
  void seek(int seconds) {
    unawaited(controller.seekBy(Duration(seconds: seconds)));
    onFeedback?.call(seconds < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded, seconds < 0 ? tr('快退{0}秒', [-seconds]) : tr('快进{0}秒', [seconds]));
  }
  void changeVolume(double delta) {
    unawaited(controller.changeVolume(delta).then((_) => onFeedback?.call(Icons.volume_up_rounded, '${player.state.volume.round()}%')));
  }
  void playOrPause() => unawaited(player.playOrPause());
  // Steps through 倍速选项 like YouTube's Shift+< and Shift+>.
  void stepSpeed(int direction) {
    final next = nextSpeed(controller.settings.speeds, player.state.rate, direction);
    if (next == null) return;
    unawaited(player.setRate(next));
    onFeedback?.call(direction > 0 ? Icons.fast_forward_rounded : Icons.slow_motion_video_rounded, '${_trim(next)}x');
  }
  // 0-9 jump to that tenth of the video, as on YouTube.
  void jumpToTenth(int tenth) {
    final duration = player.state.duration;
    if (duration <= Duration.zero) return;
    unawaited(player.seek(duration * (tenth / 10)));
    onFeedback?.call(Icons.skip_next_rounded, '${tenth * 10}%');
  }
  void jumpTo(bool end) {
    final duration = player.state.duration;
    unawaited(player.seek(end ? duration : Duration.zero));
    onFeedback?.call(end ? Icons.last_page_rounded : Icons.first_page_rounded, end ? tr('结尾') : tr('开头'));
  }
  // One frame at a time, only while paused, as on YouTube.
  void stepFrame(bool forward) {
    final platform = player.platform;
    if (player.state.playing || platform is! NativePlayer) return;
    unawaited(platform.command([forward ? 'frame-step' : 'frame-back-step']).catchError((_) {}));
    onFeedback?.call(forward ? Icons.skip_next_rounded : Icons.skip_previous_rounded, forward ? tr('下一帧') : tr('上一帧'));
  }
  // Line by line through the main subtitle, as Language Reactor's A and D.
  void subtitleStep(int skip) {
    final platform = player.platform;
    if (platform is! NativePlayer || player.state.track.subtitle.id == 'no') return;
    unawaited(platform.command(['sub-seek', '$skip']).catchError((_) {}));
    onFeedback?.call(
      skip < 0 ? Icons.skip_previous_rounded : skip > 0 ? Icons.skip_next_rounded : Icons.replay_rounded,
      skip < 0 ? tr('上一句') : skip > 0 ? tr('下一句') : tr('重听这一句'),
    );
  }
  void copySubtitle() {
    final text = controller.currentSubtitleText;
    if (text.isEmpty) return;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    onFeedback?.call(Icons.content_copy_rounded, tr('已复制字幕'));
  }
  void previous() {
    if (controller.hasPrevious) unawaited(controller.playPrevious());
  }
  void next() => unawaited(controller.playNext());
  const digits = [LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9];
  const numpad = [LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9];
  return {
    for (var i = 0; i < 10; i++) ...{
      SingleActivator(digits[i]): () => jumpToTenth(i),
      SingleActivator(numpad[i]): () => jumpToTenth(i),
    },
    const SingleActivator(LogicalKeyboardKey.home): () => jumpTo(false),
    const SingleActivator(LogicalKeyboardKey.end): () => jumpTo(true),
    const SingleActivator(LogicalKeyboardKey.comma): () => stepFrame(false),
    const SingleActivator(LogicalKeyboardKey.period): () => stepFrame(true),
    const SingleActivator(LogicalKeyboardKey.bracketLeft): previous,
    const SingleActivator(LogicalKeyboardKey.bracketRight): next,
    const SingleActivator(LogicalKeyboardKey.keyP, shift: true): previous,
    const SingleActivator(LogicalKeyboardKey.keyT): () => theaterMode.value = !theaterMode.value,
    const SingleActivator(LogicalKeyboardKey.keyB): () => lightsOff.value = !lightsOff.value,
    const SingleActivator(LogicalKeyboardKey.keyA): () => subtitleStep(-1),
    const SingleActivator(LogicalKeyboardKey.keyD): () => subtitleStep(1),
    const SingleActivator(LogicalKeyboardKey.keyR): () => subtitleStep(0),
    const SingleActivator(LogicalKeyboardKey.keyC, control: true): copySubtitle,
    if (onScreenshot != null) const SingleActivator(LogicalKeyboardKey.keyS): onScreenshot,
    const SingleActivator(LogicalKeyboardKey.space): playOrPause,
    const SingleActivator(LogicalKeyboardKey.keyK): playOrPause,
    const SingleActivator(LogicalKeyboardKey.mediaPlayPause): playOrPause,
    const SingleActivator(LogicalKeyboardKey.mediaPlay): () => unawaited(player.play()),
    const SingleActivator(LogicalKeyboardKey.mediaPause): () => unawaited(player.pause()),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () => seek(-prefs.seekSeconds),
    const SingleActivator(LogicalKeyboardKey.arrowRight): () => seek(prefs.seekSeconds),
    const SingleActivator(LogicalKeyboardKey.keyJ): () => seek(-prefs.longSeekSeconds),
    const SingleActivator(LogicalKeyboardKey.keyL): () => seek(prefs.longSeekSeconds),
    const SingleActivator(LogicalKeyboardKey.arrowUp): () => changeVolume(volume),
    const SingleActivator(LogicalKeyboardKey.arrowDown): () => changeVolume(-volume),
    const SingleActivator(LogicalKeyboardKey.keyM): () {
      unawaited(controller.toggleMute().then((_) {
        final muted = player.state.volume == 0;
        onFeedback?.call(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, muted ? tr('静音') : '${player.state.volume.round()}%');
      }));
    },
    const SingleActivator(LogicalKeyboardKey.keyF): () => unawaited(video()?.toggleFullscreen()),
    const SingleActivator(LogicalKeyboardKey.escape): () {
      final state = video();
      if (state != null && state.isFullscreen()) unawaited(state.exitFullscreen());
    },
    const SingleActivator(LogicalKeyboardKey.keyN, shift: true): () => unawaited(controller.playNext()),
    const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () => unawaited(controller.playNext()),
    const SingleActivator(LogicalKeyboardKey.keyI): controller.toggleStats,
    const SingleActivator(LogicalKeyboardKey.period, shift: true): () => stepSpeed(1),
    const SingleActivator(LogicalKeyboardKey.comma, shift: true): () => stepSpeed(-1),
  };
}

/// The speed in [speeds] after [rate], up for a positive [direction], down
/// otherwise; the end of the list when there is none further.
double? nextSpeed(List<double> speeds, double rate, int direction) {
  final sorted = [...speeds]..sort();
  if (sorted.isEmpty) return null;
  return direction > 0 ? sorted.where((s) => s > rate + 0.001).firstOrNull ?? sorted.last : sorted.lastWhere((s) => s < rate - 0.001, orElse: () => sorted.first);
}

String _trim(double speed) => speed == speed.roundToDouble() ? speed.toStringAsFixed(1) : speed.toString();

Future<void> showShortcutHelp(BuildContext context, AppPreferences prefs) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('快捷键')),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (keys, action) in playerShortcutHelp(prefs))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Text(action)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
                    child: Text(keys, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('知道了')))],
      ),
    );
