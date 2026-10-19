import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app/app_controller.dart';
import '../app_preferences.dart';

/// Keys shown in the shortcut help, in display order, with the steps from
/// [prefs].
List<(String, String)> playerShortcutHelp(AppPreferences prefs) => [
      ('空格 / K', '播放或暂停'),
      ('← / →', '后退或前进 ${prefs.seekSeconds} 秒'),
      ('J / L', '后退或前进 ${prefs.longSeekSeconds} 秒'),
      ('↑ / ↓', '音量加减 ${prefs.volumeStep}%'),
      ('M', '静音'),
      ('F', '全屏'),
      ('Esc', '退出全屏'),
      ('Shift + N', '下一个视频'),
      ('I', '显示或隐藏播放统计'),
      ('Alt + ← / 鼠标后退键', '返回上一页'),
      ('Ctrl + K', '搜索'),
    ];

/// Player key bindings, used both on the watch page and inside media_kit's
/// controls, which keep focus while the video is fullscreen.
Map<ShortcutActivator, VoidCallback> playerShortcuts(AppController controller, GlobalKey<VideoState> video) {
  final player = controller.player!;
  final prefs = controller.preferences;
  if (!prefs.keyboardShortcuts) return const {};
  final volume = prefs.volumeStep.toDouble();
  void seek(int seconds) => unawaited(controller.seekBy(Duration(seconds: seconds)));
  void playOrPause() => unawaited(player.playOrPause());
  return {
    const SingleActivator(LogicalKeyboardKey.space): playOrPause,
    const SingleActivator(LogicalKeyboardKey.keyK): playOrPause,
    const SingleActivator(LogicalKeyboardKey.mediaPlayPause): playOrPause,
    const SingleActivator(LogicalKeyboardKey.mediaPlay): () => unawaited(player.play()),
    const SingleActivator(LogicalKeyboardKey.mediaPause): () => unawaited(player.pause()),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () => seek(-prefs.seekSeconds),
    const SingleActivator(LogicalKeyboardKey.arrowRight): () => seek(prefs.seekSeconds),
    const SingleActivator(LogicalKeyboardKey.keyJ): () => seek(-prefs.longSeekSeconds),
    const SingleActivator(LogicalKeyboardKey.keyL): () => seek(prefs.longSeekSeconds),
    const SingleActivator(LogicalKeyboardKey.arrowUp): () => unawaited(controller.changeVolume(volume)),
    const SingleActivator(LogicalKeyboardKey.arrowDown): () => unawaited(controller.changeVolume(-volume)),
    const SingleActivator(LogicalKeyboardKey.keyM): () => unawaited(controller.toggleMute()),
    const SingleActivator(LogicalKeyboardKey.keyF): () => unawaited(video.currentState?.toggleFullscreen()),
    const SingleActivator(LogicalKeyboardKey.escape): () {
      final state = video.currentState;
      if (state != null && state.isFullscreen()) unawaited(state.exitFullscreen());
    },
    const SingleActivator(LogicalKeyboardKey.keyN, shift: true): () => unawaited(controller.playNext()),
    const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () => unawaited(controller.playNext()),
    const SingleActivator(LogicalKeyboardKey.keyI): controller.toggleStats,
  };
}

Future<void> showShortcutHelp(BuildContext context, AppPreferences prefs) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('快捷键'),
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
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
      ),
    );
