import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app/app_controller.dart';
import '../app_window.dart';
import '../l10n/l10n.dart';
import '../widgets/video_progress_bar.dart';
import 'accessibility.dart';
import 'app_icons.dart';
import 'common.dart';
import 'motion.dart';
import 'pages/watch_page.dart' show subtitleViewFor;
import 'player_shortcuts.dart';
import 'video_box.dart';
import 'warm_layer.dart';

/// The whole content of the small always-on-top window the app becomes in
/// picture in picture: the video, with controls while the mouse is over it.
class PipView extends StatefulWidget {
  const PipView({super.key, required this.controller});
  final AppController controller;

  @override
  State<PipView> createState() => _PipViewState();
}

class _PipViewState extends State<PipView> {
  final _subscriptions = <StreamSubscription<int?>>[];
  Timer? _hide;
  bool _controlsShown = false;

  /// The controls stay built only while they show or fade, so hidden ones
  /// cost nothing.
  bool _controlsBuilt = false;

  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    final player = _controller.player!;
    // Another video may have another ratio: the window follows it.
    void reshape(int? _) => _controller.updatePipAspect();
    _subscriptions
      ..add(player.stream.width.listen(reshape))
      ..add(player.stream.height.listen(reshape));
  }

  @override
  void dispose() {
    _hide?.cancel();
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  void _show() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), _hideNow);
    if (!_controlsShown) {
      setState(() {
        _controlsShown = true;
        _controlsBuilt = true;
      });
    }
  }

  void _hideNow() {
    _hide?.cancel();
    if (mounted && Accessibility.screenReader(context)) return;
    if (mounted && _controlsShown) setState(() => _controlsShown = false);
  }

  @override
  Widget build(BuildContext context) {
    final player = _controller.player!;
    final settings = _controller.settings;
    final window = MediaQuery.sizeOf(context);
    if (!_controlsShown && Accessibility.screenReader(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _show() : null);
    }
    final video = VideoBox(
      controller: _controller,
      smallSubtitles: true,
      subtitlesOff: (_) => !settings.pipSubtitles,
      child: WarmLayer(
        child: Video(
          controller: _controller.videoController!,
          controls:
              null, // No on-video controls; the vendored NoVideoControls constant is untyped (dynamic).
          pauseUponEnteringBackgroundMode: false,
          subtitleViewConfiguration: settings.pipSubtitles
              ? subtitleViewFor(settings,
                  smallWindow: window,
                  secondary: _controller.secondarySubtitle?.label,
                  byHeight: Platform.isAndroid || Platform.isIOS,
                  libass: _controller.libassDraws,
                  mainLanguage: _controller.mainSubtitleLanguage,
                  secondLanguage: _controller.secondSubtitleLanguage)
              : const SubtitleViewConfiguration(visible: false),
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        ...playerShortcuts(_controller, () => null),
        const SingleActivator(LogicalKeyboardKey.escape): () => _controller.setPip(false),
      },
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: Colors.black,
          child: MouseRegion(
            onEnter: (_) => _show(),
            onHover: (_) => _show(),
            onExit: (_) => _hideNow(),
            child: Stack(fit: StackFit.expand, children: [
              RepaintBoundary(child: video),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => AppWindow.startDrag(),
                onTap: () => unawaited(player.playOrPause()),
                onDoubleTap: () => _controller.setPip(false),
              ),
              AnimatedOpacity(
                opacity: _controlsShown ? 1 : 0,
                duration: Motion.of(Ease.fade),
                onEnd: () {
                  if (!_controlsShown && mounted) setState(() => _controlsBuilt = false);
                },
                child: _controlsBuilt
                    ? IgnorePointer(
                        ignoring: !_controlsShown,
                        child: PipControls(
                            controller: _controller,
                            player: player,
                            scale: (window.shortestSide / 280).clamp(0.6, 2.0)),
                      )
                    : const SizedBox.shrink(),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                width: 18,
                height: 18,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeDownRight,
                  child: GestureDetector(
                      behavior: HitTestBehavior.opaque, onPanStart: (_) => AppWindow.startResize()),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// What picture in picture shows over the video: the title and a button to
/// leave on top, seek and play buttons in the middle, the progress bar below.
class PipControls extends StatefulWidget {
  const PipControls({super.key, required this.controller, required this.player, this.scale = 1});
  final AppController controller;
  final Player player;
  final double scale;

  @override
  State<PipControls> createState() => _PipControlsState();
}

class _PipControlsState extends State<PipControls> {
  final _positions = KeptPositions();

  AppController get controller => widget.controller;
  Player get player => widget.player;
  double get scale => widget.scale;

  String get _title {
    final details = controller.details?.title;
    return details != null && details.isNotEmpty ? details : controller.playing?.title ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final style = IconButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: const Color(0xB3000000),
      padding: const EdgeInsets.all(4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final seek = controller.preferences.longSeekSeconds;
    return Column(children: [
      GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => AppWindow.startDrag(),
        onDoubleTap: () => controller.setPip(false),
        child: DecoratedBox(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent])),
          child: Row(children: [
            const SizedBox(width: 8),
            Expanded(
                child: Text(_title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12))),
            IconButton(
                style: style,
                tooltip: tr('Leave picture in picture'),
                iconSize: 18,
                icon: Icon(AppIcons.arrowsOutSimple),
                onPressed: () => controller.setPip(false)),
          ]),
        ),
      ),
      Expanded(
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                style: style,
                tooltip: tr('Back {0} s', [seek]),
                iconSize: 26 * scale,
                icon: Icon(AppIcons.clockCounterClockwise),
                onPressed: () => unawaited(controller.seekBy(Duration(seconds: -seek)))),
            StreamBuilder<bool>(
              stream: player.stream.playing,
              initialData: player.state.playing,
              builder: (context, snapshot) => IconButton(
                style: style,
                tooltip: snapshot.data ?? false ? tr('Pause (Space)') : tr('Play (Space)'),
                iconSize: 38 * scale,
                icon: Icon(snapshot.data ?? false ? AppIcons.pauseCircle : AppIcons.playCircleFill),
                onPressed: () => unawaited(player.playOrPause()),
              ),
            ),
            IconButton(
                style: style,
                tooltip: tr('Forward {0} s', [seek]),
                iconSize: 26 * scale,
                icon: Icon(AppIcons.clockClockwise),
                onPressed: () => unawaited(controller.seekBy(Duration(seconds: seek)))),
          ]),
        ),
      ),
      // The right padding keeps the bar clear of the resize corner.
      Container(
        color: const Color(0xB3000000),
        padding: const EdgeInsets.fromLTRB(4, 0, 16, 2),
        child: StreamBuilder<Duration>(
          stream: _positions.of(player),
          initialData: player.state.position,
          builder: (context, _) => VideoProgressBar(
            position: player.state.position,
            buffered: player.state.buffer,
            total: player.state.duration,
            color: Colors.white,
            onSeek: (time) => unawaited(controller.seek(time)),
          ),
        ),
      ),
    ]);
  }
}
