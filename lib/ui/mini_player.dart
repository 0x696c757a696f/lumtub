import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app/app_controller.dart';
import '../app_window.dart' show pipAspectOf;
import '../l10n/l10n.dart';
import '../widgets/video_progress_bar.dart';
import 'accessibility.dart';
import 'app_icons.dart';
import 'common.dart';
import 'motion.dart';
import 'pages/watch_page.dart' show subtitleViewFor;
import 'video_box.dart';
import 'warm_layer.dart';

enum MiniCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Subtitles are left out of a card whose short side is under this.
const miniSubtitlesFrom = 120.0;

/// The top left of a card of [size] sitting in [corner] of [area].
Offset miniPosition(MiniCorner corner, Size area, Size size, {double margin = MiniPlayer.margin}) {
  final left = corner == MiniCorner.topLeft || corner == MiniCorner.bottomLeft;
  final top = corner == MiniCorner.topLeft || corner == MiniCorner.topRight;
  return Offset(left ? margin : area.width - size.width - margin, top ? margin : area.height - size.height - margin);
}

/// The corner a card whose top left is at [offset] is nearest to, by its centre.
MiniCorner nearestMiniCorner(Offset offset, Size area, Size size) {
  final centre = offset + Offset(size.width / 2, size.height / 2);
  final left = centre.dx < area.width / 2;
  final top = centre.dy < area.height / 2;
  return top ? (left ? MiniCorner.topLeft : MiniCorner.topRight) : (left ? MiniCorner.bottomLeft : MiniCorner.bottomRight);
}

/// The card's size: [MiniPlayer.width] wide in the video's ratio, made
/// smaller to fit [area] with its margins.
Size miniSize(double aspect, Size area) {
  const margin = MiniPlayer.margin;
  final ratio = pipAspectOf(aspect);
  var width = math.min(MiniPlayer.width, math.max(0.0, area.width - 2 * margin));
  final room = area.height - 2 * margin;
  if (width / ratio > room) width = room * ratio;
  return Size(width, width / ratio);
}

/// The video kept playing over the page after leaving the watch page: a
/// card that can be dragged between the corners on a computer or tablet,
/// a bar above the navigation on a phone. Place it in a Stack that fills
/// the page area.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key, required this.controller, this.videoBuilder});
  final AppController controller;

  /// The picture in place of the real video.
  final WidgetBuilder? videoBuilder;

  static const width = 320.0;

  /// As tall as LibreTube's and NewPipe's.
  static const barHeight = 64.0;
  static const margin = 12.0;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  MiniCorner _corner = MiniCorner.bottomRight;
  Offset? _dragging;
  bool _videoReady = false;
  bool _controlsShown = false;
  bool _controlsBuilt = false;
  Timer? _mount;
  Timer? _hide;
  Player? _watched;
  final _linePositions = KeptPositions();
  final _barPositions = KeptPositions();
  final _subscriptions = <StreamSubscription<int?>>[];

  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // The watch page's video is still fading out; two views of one controller
    // must not overlap.
    _mount = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _videoReady = true);
    });
  }

  @override
  void dispose() {
    _mount?.cancel();
    _hide?.cancel();
    _unwatch();
    super.dispose();
  }

  void _unwatch() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _watched = null;
  }

  /// Another video may have another ratio.
  void _watch(Player player) {
    if (identical(_watched, player)) return;
    _unwatch();
    _watched = player;
    void changed(int? _) {
      if (mounted) setState(() {});
    }
    _subscriptions
      ..add(player.stream.width.listen(changed))
      ..add(player.stream.height.listen(changed));
  }

  void _showControls() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), _hideControls);
    if (_controlsShown && _controlsBuilt) return;
    setState(() => _controlsShown = _controlsBuilt = true);
  }

  void _hideControls() {
    _hide?.cancel();
    // Nothing to hover with a screen reader: its buttons stay.
    if (mounted && Accessibility.screenReader(context)) return;
    if (mounted && _controlsShown) setState(() => _controlsShown = false);
  }

  String get _title {
    final details = _controller.details?.title;
    return details != null && details.isNotEmpty ? details : _controller.playing?.title ?? '';
  }

  String get _channel {
    final details = _controller.details?.channel;
    return details != null && details.isNotEmpty ? details : _controller.playing?.channel ?? '';
  }

  Widget _picture(BuildContext context, Size size) {
    if (!_videoReady) return const SizedBox.expand();
    final builder = widget.videoBuilder;
    if (builder != null) return builder(context);
    final video = _controller.videoController;
    if (video == null) return const SizedBox.expand();
    final settings = _controller.settings;
    final subtitles = settings.miniPlayerSubtitles && size.shortestSide >= miniSubtitlesFrom;
    return VideoBox(
      controller: _controller,
      smallSubtitles: true,
      subtitlesOff: (box) => !settings.miniPlayerSubtitles || box.shortestSide < miniSubtitlesFrom,
      child: WarmLayer(
        child: Video(
          controller: video,
          controls: NoVideoControls,
          pauseUponEnteringBackgroundMode: false,
          subtitleViewConfiguration: subtitles
              ? subtitleViewFor(settings, smallWindow: size, secondary: _controller.secondarySubtitle?.label, byHeight: Platform.isAndroid || Platform.isIOS, libass: _controller.libassDraws, mainLanguage: _controller.mainSubtitleLanguage, secondLanguage: _controller.secondSubtitleLanguage)
              : const SubtitleViewConfiguration(visible: false),
        ),
      ),
    );
  }

  Widget _progressLine(BuildContext context, Player player) {
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: RepaintBoundary(
        child: StreamBuilder<Duration>(
          stream: _linePositions.of(player),
          initialData: player.state.position,
          builder: (context, _) {
            final total = player.state.duration.inMilliseconds;
            final value = total <= 0 ? 0.0 : (player.state.position.inMilliseconds / total).clamp(0.0, 1.0);
            return LinearProgressIndicator(value: value, minHeight: 2, color: colors.inversePrimary, backgroundColor: Colors.white24);
          },
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, Player player) {
    ButtonStyle style() => IconButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: const Color(0xB3000000),
          padding: const EdgeInsets.all(4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
    return AnimatedOpacity(
      opacity: _controlsShown ? 1 : 0,
      duration: Motion.of(Ease.fade),
      onEnd: () {
        if (!_controlsShown && mounted) setState(() => _controlsBuilt = false);
      },
      child: IgnorePointer(
        ignoring: !_controlsShown,
        child: Column(children: [
          Stack(children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent]))),
              ),
            ),
            Row(children: [
              const SizedBox(width: 8),
              Expanded(
                child: IgnorePointer(child: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12))),
              ),
              IconButton(style: style(), tooltip: tr('Back to the watch page'), iconSize: 18, icon: Icon(AppIcons.arrowsOutSimple), onPressed: _controller.expandMini),
              const SizedBox(width: 4),
              IconButton(style: style(), tooltip: tr('Close the mini player and stop playback'), iconSize: 18, icon: Icon(AppIcons.x), onPressed: _controller.stopWatching),
              const SizedBox(width: 4),
            ]),
          ]),
          Expanded(
            child: Center(
              child: StreamBuilder<bool>(
                stream: player.stream.playing,
                initialData: player.state.playing,
                builder: (context, snapshot) => IconButton(
                  style: style(),
                  tooltip: snapshot.data ?? false ? tr('Pause (Space)') : tr('Play (Space)'),
                  iconSize: 40,
                  icon: Icon(snapshot.data ?? false ? AppIcons.pauseCircle : AppIcons.playCircleFill),
                  onPressed: () => unawaited(player.playOrPause()),
                ),
              ),
            ),
          ),
          Container(
            color: const Color(0xB3000000),
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
            child: StreamBuilder<Duration>(
              stream: _barPositions.of(player),
              initialData: player.state.position,
              builder: (context, _) => VideoProgressBar(
                position: player.state.position,
                buffered: player.state.buffer,
                total: player.state.duration,
                color: Colors.white,
                onSeek: (time) => unawaited(_controller.seek(time)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _card(BuildContext context, Player player, Size area) {
    final size = miniSize(_controller.videoAspect, area);
    final position = _dragging ?? miniPosition(_corner, area, size);
    return AnimatedPositioned(
      left: position.dx,
      top: position.dy,
      width: size.width,
      height: size.height,
      duration: _dragging != null ? Duration.zero : Motion.of(Ease.fade),
      curve: Ease.curve,
      child: Entrance(
        child: MouseRegion(
          onEnter: (_) => _showControls(),
          onHover: (_) => _showControls(),
          onExit: (_) => _hideControls(),
          child: Material(
            color: Colors.black,
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Stack(fit: StackFit.expand, children: [
              _picture(context, size),
              Positioned(left: 0, right: 0, bottom: 0, child: _progressLine(context, player)),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  unawaited(player.playOrPause());
                  _showControls();
                },
                onDoubleTap: _controller.expandMini,
                onPanStart: (_) => setState(() => _dragging = miniPosition(_corner, area, size)),
                onPanUpdate: (details) {
                  final at = (_dragging ?? position) + details.delta;
                  setState(() => _dragging = Offset(at.dx.clamp(0.0, math.max(0.0, area.width - size.width)), at.dy.clamp(0.0, math.max(0.0, area.height - size.height))));
                },
                onPanEnd: (_) => setState(() {
                  _corner = nearestMiniCorner(_dragging ?? position, area, size);
                  _dragging = null;
                }),
                onPanCancel: () => setState(() => _dragging = null),
              ),
              if (_controlsBuilt) _controls(context, player),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, Player player) {
    final theme = Theme.of(context);
    const line = 2.0;
    const thumb = MiniPlayer.barHeight - line;
    final size = const Size(thumb * 16 / 9, thumb);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Entrance(
        scale: 0.96,
        child: GestureDetector(
          onTap: _controller.expandMini,
          onVerticalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (v < -200) _controller.expandMini();
            if (v > 200) _controller.stopWatching();
          },
          child: Material(
            color: theme.colorScheme.surfaceContainerHigh,
            elevation: 4,
            child: SizedBox(
              height: MiniPlayer.barHeight,
              child: Column(children: [
                _progressLine(context, player),
                Expanded(
                  child: Row(children: [
                    SizedBox(width: size.width, height: size.height, child: ColoredBox(color: Colors.black, child: _picture(context, size))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(
                        button: true,
                        hint: tr('Back to the watch page'),
                        onTap: _controller.expandMini,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        if (_channel.isNotEmpty) Text(_channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                      ])),
                    ),
                    StreamBuilder<bool>(
                      stream: player.stream.playing,
                      initialData: player.state.playing,
                      builder: (context, snapshot) => IconButton(
                        tooltip: snapshot.data ?? false ? tr('Pause (Space)') : tr('Play (Space)'),
                        iconSize: 28,
                        icon: Icon(snapshot.data ?? false ? AppIcons.pauseFill : AppIcons.playFill),
                        onPressed: () => unawaited(player.playOrPause()),
                      ),
                    ),
                    IconButton(tooltip: tr('Close the mini player and stop playback'), iconSize: 24, icon: Icon(AppIcons.x), onPressed: _controller.stopWatching),
                    const SizedBox(width: 4),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = _controller.player;
    if (player == null) return const SizedBox.shrink();
    _watch(player);
    if (isPhone(context)) return _bar(context, player);
    if (!_controlsShown && Accessibility.screenReader(context)) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _showControls() : null);
    return LayoutBuilder(builder: (context, constraints) => Stack(children: [_card(context, player, constraints.biggest)]));
  }
}
