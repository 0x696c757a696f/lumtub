import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer;
import 'package:media_kit_video/media_kit_video.dart';

import '../app/app_controller.dart';
import '../app_preferences.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../shortcut_bindings.dart';
import 'lights_off.dart';
import 'theater_mode.dart';
import 'app_icons.dart';
import 'common.dart';

/// What [action] does, as the settings and the help name it.
String shortcutActionLabel(PlayerAction action, AppPreferences prefs) => switch (action) {
      PlayerAction.playPause => tr('Play or pause'),
      PlayerAction.seekBack => tr('Back {0} s', [prefs.seekSeconds]),
      PlayerAction.seekForward => tr('Forward {0} s', [prefs.seekSeconds]),
      PlayerAction.longSeekBack => tr('Back {0} s', [prefs.longSeekSeconds]),
      PlayerAction.longSeekForward => tr('Forward {0} s', [prefs.longSeekSeconds]),
      PlayerAction.volumeUp => tr('Volume up {0}%', [prefs.volumeStep]),
      PlayerAction.volumeDown => tr('Volume down {0}%', [prefs.volumeStep]),
      PlayerAction.mute => tr('Mute'),
      PlayerAction.slower => tr('Slow down playback'),
      PlayerAction.faster => tr('Speed up playback'),
      PlayerAction.fullscreen => tr('Fullscreen'),
      PlayerAction.exitFullscreen => tr('Exit fullscreen'),
      PlayerAction.previous => tr('Previous video'),
      PlayerAction.next => tr('Next video'),
      PlayerAction.frameBack => tr('Previous frame'),
      PlayerAction.frameForward => tr('Next frame'),
      PlayerAction.start => tr('Start'),
      PlayerAction.end => tr('End'),
      PlayerAction.lineBack => tr('Previous line'),
      PlayerAction.lineNext => tr('Next line'),
      PlayerAction.lineReplay => tr('Replay this line'),
      PlayerAction.copySubtitle => tr('Copy the current subtitle'),
      PlayerAction.theater => tr('Theater mode'),
      PlayerAction.lightsOff => tr('Lights off'),
      PlayerAction.screenshot => tr('Screenshot'),
      PlayerAction.stats => tr('Show or hide playback stats'),
      PlayerAction.captions => tr('Subtitles on or off'),
      PlayerAction.captionsBigger => tr('Larger subtitles'),
      PlayerAction.captionsSmaller => tr('Smaller subtitles'),
      PlayerAction.miniPlayer => tr('Mini player'),
      PlayerAction.danmaku => tr('Bullet chat on or off'),
      PlayerAction.chapterBack => tr('Previous chapter'),
      PlayerAction.chapterNext => tr('Next chapter'),
      PlayerAction.search => tr('Search'),
      PlayerAction.incognito => tr('Incognito mode'),
      PlayerAction.back => tr('Go back'),
      PlayerAction.top => tr('Scroll to the top'),
      PlayerAction.bottom => tr('Scroll to the bottom'),
      PlayerAction.pageDown => tr('Scroll down a page'),
      PlayerAction.pageUp => tr('Scroll up a page'),
      PlayerAction.help => tr('Keyboard shortcuts'),
    };

/// Keys shown in the shortcut help, in display order, with the keys and
/// steps from [prefs].
List<(String, String)> playerShortcutHelp(AppPreferences prefs) {
  final keys = shortcutKeys(prefs.shortcutKeys);
  String of(PlayerAction action) => keys[action]!.map((k) => k.label).join(', ');
  String pair(PlayerAction a, PlayerAction b) => [of(a), of(b)].where((k) => k.isNotEmpty).join(' / ');
  final rows = <(String, String)>[
    (of(PlayerAction.playPause), tr('Play or pause')),
    (pair(PlayerAction.seekBack, PlayerAction.seekForward), tr('Seek back or forward {0} seconds', [prefs.seekSeconds])),
    (pair(PlayerAction.longSeekBack, PlayerAction.longSeekForward), tr('Seek back or forward {0} seconds', [prefs.longSeekSeconds])),
    (pair(PlayerAction.volumeUp, PlayerAction.volumeDown), tr('Volume up/down {0}%', [prefs.volumeStep])),
    (pair(PlayerAction.slower, PlayerAction.faster), tr('Slow down or speed up playback')),
    (tr('Hold on the video'), tr('Hold for 2x speed')),
    (keyNames(tr('Ctrl + wheel')), tr('Slow down or speed up playback')),
    (of(PlayerAction.mute), tr('Mute')),
    (of(PlayerAction.fullscreen), tr('Fullscreen')),
    (of(PlayerAction.exitFullscreen), tr('Exit fullscreen')),
    if (prefs.rightClickBack) (tr('Right click on the video'), tr('Exit fullscreen, or else go back')),
    (of(PlayerAction.next), tr('Next video')),
    (of(PlayerAction.previous), tr('Previous video')),
    (pair(PlayerAction.frameBack, PlayerAction.frameForward), tr('Step back or forward one frame while paused')),
    ('0 - 9', tr('Jump to 0% - 90% of the video')),
    (pair(PlayerAction.start, PlayerAction.end), tr('Jump to the start or end')),
    (pair(PlayerAction.lineBack, PlayerAction.lineNext), tr('Previous or next subtitle line')),
    (of(PlayerAction.lineReplay), tr('Replay this line')),
    (of(PlayerAction.copySubtitle), tr('Copy the current subtitle')),
    (of(PlayerAction.theater), tr('Theater mode')),
    (of(PlayerAction.lightsOff), tr('Lights off')),
    (of(PlayerAction.screenshot), tr('Screenshot')),
    (of(PlayerAction.stats), tr('Show or hide playback stats')),
    (of(PlayerAction.captions), tr('Subtitles on or off')),
    (pair(PlayerAction.captionsBigger, PlayerAction.captionsSmaller), tr('Larger or smaller subtitles')),
    (of(PlayerAction.miniPlayer), tr('Mini player')),
    (of(PlayerAction.danmaku), tr('Bullet chat on or off')),
    (pair(PlayerAction.chapterBack, PlayerAction.chapterNext), tr('Previous or next chapter')),
    ([of(PlayerAction.back), tr('mouse back button')].where((k) => k.isNotEmpty).join(' / '), tr('Go back')),
    (of(PlayerAction.search), tr('Search')),
    (of(PlayerAction.incognito), tr('Incognito mode')),
    (pair(PlayerAction.top, PlayerAction.bottom), tr('Scroll a list to the top or bottom')),
    (pair(PlayerAction.pageUp, PlayerAction.pageDown), tr('Scroll a list up or down a page')),
    (of(PlayerAction.help), tr('Show these shortcuts')),
  ];
  return [for (final row in rows) if (row.$1.isNotEmpty) row];
}

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
    onFeedback?.call(seconds < 0 ? AppIcons.rewindFill : AppIcons.fastForwardFill, seconds < 0 ? tr('Back {0} s', [-seconds]) : tr('Forward {0} s', [seconds]));
  }
  void changeVolume(double delta) {
    unawaited(controller.changeVolume(delta).then((_) => onFeedback?.call(AppIcons.speakerHighFill, '${player.state.volume.round()}%')));
  }
  void playOrPause() => unawaited(player.playOrPause());
  // Steps through 倍速选项 like YouTube's Shift+< and Shift+>.
  void stepSpeed(int direction) {
    final next = nextSpeed(controller.settings.speeds, player.state.rate, direction);
    if (next == null) return;
    unawaited(player.setRate(next));
    onFeedback?.call(direction > 0 ? AppIcons.fastForwardFill : AppIcons.speedometer, '${_trim(next)}x');
  }
  // 0-9 jump to that tenth of the video, as on YouTube.
  void jumpToTenth(int tenth) {
    final duration = player.state.duration;
    if (duration <= Duration.zero) return;
    unawaited(controller.seek(duration * (tenth / 10)));
    onFeedback?.call(AppIcons.skipForwardFill, '${tenth * 10}%');
  }
  void jumpTo(bool end) {
    if (end && controller.playing?.isLive == true) {
      unawaited(controller.goLive());
      onFeedback?.call(AppIcons.caretLineRight, tr('Live'));
      return;
    }
    final duration = player.state.duration;
    unawaited(controller.seek(end ? duration : Duration.zero));
    onFeedback?.call(end ? AppIcons.caretLineRight : AppIcons.caretLineLeft, end ? tr('End') : tr('Start'));
  }
  // One frame at a time, only while paused, as on YouTube.
  void stepFrame(bool forward) {
    final platform = player.platform;
    if (player.state.playing || platform is! NativePlayer) return;
    unawaited(platform.command([forward ? 'frame-step' : 'frame-back-step']).catchError((_) {}));
    onFeedback?.call(forward ? AppIcons.skipForwardFill : AppIcons.skipBackFill, forward ? tr('Next frame') : tr('Previous frame'));
  }
  // Line by line through the main subtitle, as Language Reactor's A and D.
  void subtitleStep(int skip) {
    final platform = player.platform;
    if (platform is! NativePlayer || player.state.track.subtitle.id == 'no') return;
    unawaited(platform.command(['sub-seek', '$skip']).catchError((_) {}));
    onFeedback?.call(
      skip < 0 ? AppIcons.skipBackFill : skip > 0 ? AppIcons.skipForwardFill : AppIcons.arrowCounterClockwiseFill,
      skip < 0 ? tr('Previous line') : skip > 0 ? tr('Next line') : tr('Replay this line'),
    );
  }
  void copySubtitle() {
    final text = controller.currentSubtitleText;
    if (text.isEmpty) return;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    onFeedback?.call(AppIcons.copy, tr('Subtitle copied'));
  }
  void previous() {
    if (controller.hasPrevious) unawaited(controller.playPrevious());
  }
  void next() => unawaited(controller.playNext());
  void mute() {
    unawaited(controller.toggleMute().then((_) {
      final muted = player.state.volume == 0;
      onFeedback?.call(muted ? AppIcons.speakerSlash : AppIcons.speakerHighFill, muted ? tr('Mute') : '${player.state.volume.round()}%');
    }));
  }
  void exitFullscreen() {
    final state = video();
    if (state != null && state.isFullscreen()) unawaited(state.exitFullscreen());
  }  void captions() {
    unawaited(controller.toggleSubtitles().then((on) {
      if (on != null) onFeedback?.call(on ? AppIcons.closedCaptioningFill : AppIcons.subtitlesSlash, on ? tr('Subtitles on') : tr('Subtitles off'));
    }));
  }
  void captionSize(int direction) {
    final now = controller.settings.subtitleScale;
    final next = ((now * 10).round() + direction).clamp(5, 30) / 10;
    if (next == now) return;
    unawaited(controller.saveSettings(controller.settings.copyWith(subtitleScale: next)));
    onFeedback?.call(AppIcons.closedCaptioningFill, '${next.toStringAsFixed(1)}×');
  }
  void mini() {
    if (controller.mini) {
      controller.expandMini();
    } else {
      exitFullscreen();
      controller.enterMini();
    }
  }
  void danmaku() {
    if (!controller.hasDanmaku) return;
    final settings = controller.preferences.danmaku;
    unawaited(controller.setDanmaku(settings.copyWith(enabled: !settings.enabled)));
    onFeedback?.call(settings.enabled ? AppIcons.chatCircleSlash : AppIcons.chatsFill, settings.enabled ? tr('Bullet chat off') : tr('Bullet chat on'));
  }
  void chapter(int direction) {
    final chapters = controller.details?.chapters ?? const <Chapter>[];
    if (chapters.isEmpty) return;
    final position = player.state.position;
    final current = Chapter.at(chapters, position);
    final index = current == null ? -1 : chapters.indexOf(current);
    // Back from more than 3 s into a chapter goes to its start, as YouTube does.
    final target = direction > 0
        ? (index + 1 < chapters.length ? chapters[index + 1] : null)
        : (current != null && position - current.start > const Duration(seconds: 3) ? current : index > 0 ? chapters[index - 1] : current);
    if (target == null) return;
    unawaited(controller.seek(target.start));
    onFeedback?.call(direction > 0 ? AppIcons.skipForwardFill : AppIcons.skipBackFill, target.title.isEmpty ? (direction > 0 ? tr('Next chapter') : tr('Previous chapter')) : target.title);
  }

  VoidCallback? run(PlayerAction action) => switch (action) {
        PlayerAction.playPause => playOrPause,
        PlayerAction.seekBack => () => seek(-prefs.seekSeconds),
        PlayerAction.seekForward => () => seek(prefs.seekSeconds),
        PlayerAction.longSeekBack => () => seek(-prefs.longSeekSeconds),
        PlayerAction.longSeekForward => () => seek(prefs.longSeekSeconds),
        PlayerAction.volumeUp => () => changeVolume(volume),
        PlayerAction.volumeDown => () => changeVolume(-volume),
        PlayerAction.mute => mute,
        PlayerAction.slower => () => stepSpeed(-1),
        PlayerAction.faster => () => stepSpeed(1),
        PlayerAction.fullscreen => () => unawaited(video()?.toggleFullscreen()),
        PlayerAction.exitFullscreen => exitFullscreen,
        PlayerAction.previous => previous,
        PlayerAction.next => next,
        PlayerAction.frameBack => () => stepFrame(false),
        PlayerAction.frameForward => () => stepFrame(true),
        PlayerAction.start => () => jumpTo(false),
        PlayerAction.end => () => jumpTo(true),
        PlayerAction.lineBack => () => subtitleStep(-1),
        PlayerAction.lineNext => () => subtitleStep(1),
        PlayerAction.lineReplay => () => subtitleStep(0),
        PlayerAction.copySubtitle => copySubtitle,
        PlayerAction.theater => () => theaterMode.value = !theaterMode.value,
        PlayerAction.lightsOff => () => lightsOff.value = !lightsOff.value,
        PlayerAction.screenshot => onScreenshot,
        PlayerAction.stats => controller.toggleStats,
        PlayerAction.captions => captions,
        PlayerAction.captionsBigger => () => captionSize(1),
        PlayerAction.captionsSmaller => () => captionSize(-1),
        PlayerAction.miniPlayer => mini,
        PlayerAction.danmaku => danmaku,
        PlayerAction.chapterBack => () => chapter(-1),
        PlayerAction.chapterNext => () => chapter(1),
        // Pages' own, bound by the app shell.
        PlayerAction.search || PlayerAction.incognito || PlayerAction.back || PlayerAction.top || PlayerAction.bottom || PlayerAction.pageDown || PlayerAction.pageUp || PlayerAction.help => null,
      };
  const digits = [LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9];
  const numpad = [LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9];
  final bindings = <ShortcutActivator, VoidCallback>{
    for (final MapEntry(:key, :value) in shortcutKeys(prefs.shortcutKeys).entries)
      if (run(key) case final callback?)
        for (final combo in value) combo.activator: callback,
    for (var i = 0; i < 10; i++) ...{
      SingleActivator(digits[i]): () => jumpToTenth(i),
      SingleActivator(numpad[i]): () => jumpToTenth(i),
    },
    const SingleActivator(LogicalKeyboardKey.mediaPlayPause): playOrPause,
    const SingleActivator(LogicalKeyboardKey.mediaPlay): () => unawaited(player.play()),
    const SingleActivator(LogicalKeyboardKey.mediaPause): () => unawaited(player.pause()),
    const SingleActivator(LogicalKeyboardKey.mediaTrackNext): next,
    const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): previous,
  };
  return {for (final MapEntry(:key, :value) in bindings.entries) NotWhileTyping(key): value};
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
        // The list is taller than a small window; it scrolls above the button.
        scrollable: true,
        title: Text(tr('Keyboard shortcuts')),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (keys, action) in playerShortcutHelp(prefs))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(action)),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
                    child: Text(keys, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Got it')))],
      ),
    );

/// [activator], except while a text field has the focus, so typing a
/// comment or a search inside the watch page types instead of seeking.
class NotWhileTyping extends ShortcutActivator {
  const NotWhileTyping(this.activator);
  final ShortcutActivator activator;

  static bool get typing {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null && (context.widget is EditableText || context.findAncestorStateOfType<EditableTextState>() != null);
  }

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) => !typing && activator.accepts(event, state);

  @override
  Iterable<LogicalKeyboardKey>? get triggers => activator.triggers;

  @override
  String debugDescribeKeys() => activator.debugDescribeKeys();
}
