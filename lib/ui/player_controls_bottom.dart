part of 'player_controls.dart';

extension _BottomBar on _PlayerControlsState {
  Widget _bottomBar(BuildContext context, bool fullscreen, bool phone, double extra, Color color, Gradient? gradient, Size box) {
    final c = _c;
    final compact = phone && !fullscreen;
    final narrow = compact || (fullscreen && phone && box.width < 600);
    final width = phone ? 44.0 : fullscreen ? 42.0 : 35.0;
    final progress = _ProgressSection(host: this, color: color, gradient: gradient);
    final fullscreenButton = _IconBtn(
      icon: compact || !fullscreen || fillingWindow.value ? AppIcons.cornersOut : AppIcons.cornersIn,
      size: 24,
      width: width,
      tooltip: compact || !fullscreen || fillingWindow.value ? tr('Fullscreen (F)') : tr('Exit fullscreen (F)'),
      onTap: () async {
        _showBars();
        if (compact) {
          await widget.state?.toggleFullscreen();
        } else {
          await toggleFullscreenFrom(widget.state);
        }
        _rebuild();
      },
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
        child: Row(children: [
          _PlayButton(host: this),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: progress)),
          _TimeText(host: this),
          _subtitleButtons(width),
          _learningButtons(width, few: true),
          fullscreenButton,
        ]),
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB((fullscreen ? 16 : 8) + extra, 16, (fullscreen ? 16 : 8) + extra, fullscreen ? 12 : 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: progress),
          const SizedBox(height: 2),
          Row(children: [
            _PlayButton(host: this),
            if (c.hasNext)
              _IconBtn(
                icon: AppIcons.skipForwardFill,
                width: width,
                tooltip: tr('Next (Shift+N)'),
                onTap: () {
                  _showBars();
                  unawaited(c.playNext());
                },
              ),
            if (!phone) _VolumeControl(host: this, width: width),
            SizedBox(width: phone ? 8 : 4),
            if (c.playing?.isLive == true) _LiveButton(host: this) else _TimeText(host: this),
            Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: _ChapterMenu(host: this))),
            if (c.hasDanmaku) _danmakuButtons(width, narrow),
            _subtitleButtons(width),
            _learningButtons(width, few: narrow),
            if (!narrow) _speedMenu(),
            if (!narrow) _qualityMenu(),
            if (!fullscreen && !phone)
              ListenableBuilder(
                listenable: Listenable.merge([theaterMode, theaterChatOpen]),
                builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
                  if (theaterMode.value && theaterPanelBeside && !theaterChatOpen.value)
                    _IconBtn(
                      icon: AppIcons.sidebar,
                      width: width,
                      tooltip: tr('Expand'),
                      onTap: () {
                        _showBars();
                        theaterChatOpen.value = true;
                      },
                    ),
                  _IconBtn(
                    icon: AppIcons.frameCorners,
                    width: width,
                    active: theaterMode.value,
                    tooltip: theaterMode.value ? tr('Exit theater mode (T)') : tr('Theater mode (T)'),
                    onTap: () {
                      _showBars();
                      theaterMode.value = !theaterMode.value;
                    },
                  ),
                ]),
              ),
            if (!touchFirst)
              ValueListenableBuilder<bool>(
                valueListenable: fillingWindow,
                builder: (context, filling, _) => !fullscreen || filling
                    ? _IconBtn(
                        icon: AppIcons.arrowsOutSimple,
                        width: width,
                        active: filling,
                        tooltip: tr('Fill the window (W)'),
                        onTap: () {
                          _showBars();
                          unawaited(toggleFillWindow(widget.state));
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            fullscreenButton,
          ]),
        ]),
      ),
    );
  }

  Widget _speedMenu() => StreamBuilder<double>(
        stream: _player.stream.rate,
        initialData: _player.state.rate,
        builder: (context, snapshot) {
          final rate = snapshot.data ?? _player.state.rate;
          return _TextMenu<double>(
            host: this,
            tooltip: tr('Speed'),
            label: '${trimSpeed(rate)}X',
            current: rate,
            rows: [for (final speed in _c.settings.speeds) (speed, '${trimSpeed(speed)}X')],
            onSelected: (speed) => unawaited(_player.setRate(speed)),
          );
        },
      );

  Widget _qualityMenu() => StreamBuilder<int?>(
        stream: _player.stream.height,
        initialData: _player.state.height,
        builder: (context, snapshot) {
          final c = _c;
          final state = _player.state;
          final height = snapshot.data ?? state.height ?? 0;
          final aspect = (state.width ?? 0) > 0 && height > 0 ? state.width! / height : null;
          final maxHeight = c.settings.maxHeight;
          final label = height > 0
              ? heightLabel(height, c.availableFrameRates[height], 'P', aspect)
              : maxHeight == 0 ? tr('Auto') : heightLabel(maxHeight, c.availableFrameRates[maxHeight], 'P');
          final choices = c.qualityChoices;
          final current = maxHeight == 0 && c.droppedCap > 0 ? -1 : choices.contains(maxHeight) ? maxHeight : height;
          return _TextMenu<int>(
            host: this,
            tooltip: tr('Quality'),
            label: label,
            current: current,
            rows: [for (final h in choices) (h, h == 0 ? tr('Auto') : heightLabel(h, c.availableFrameRates[h], 'P', aspect))],
            onSelected: (h) => unawaited(c.setMaxHeight(h)),
          );
        },
      );

  Widget _danmakuButtons(double width, bool narrow) {
    final c = _c;
    final settings = c.preferences.danmaku;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _IconBtn(
        icon: settings.enabled ? AppIcons.chatsFill : AppIcons.chatCircleSlash,
        width: width,
        tooltip: settings.enabled ? tr('Turn off bullet chat') : tr('Turn on bullet chat'),
        onTap: () {
          _showBars();
          unawaited(c.setDanmaku(settings.copyWith(enabled: !settings.enabled)));
        },
      ),
      if (settings.enabled && !narrow)
        _IconBtn(
          icon: AppIcons.slidersHorizontal,
          size: 20,
          width: width,
          tooltip: tr('Bullet chat settings'),
          onTap: () {
            _showBars();
            _menuOpened();
            unawaited(showDanmakuPanel(context, c).whenComplete(_menuClosed));
          },
        ),
    ]);
  }

  Widget _subtitleButtons(double width) => StreamBuilder<Track>(
        stream: _player.stream.track,
        initialData: _player.state.track,
        builder: (context, snapshot) {
          final track = snapshot.data ?? _player.state.track;
          final real = _player.state.tracks.subtitle.any((t) => t.id != 'auto' && t.id != 'no');
          final offered = real || (_c.details?.subtitles.isNotEmpty ?? false) || _c.playing?.isLive != true;
          if (!offered) return const SizedBox.shrink();
          final primaryOn = track.subtitle.id != 'no' && track.subtitle.id != 'auto';
          final secondaryOn = _c.secondaryTrackId != 'no';
          return Row(mainAxisSize: MainAxisSize.min, children: [
            _IconBtn(
              icon: primaryOn ? AppIcons.closedCaptioningFill : AppIcons.subtitlesSlash,
              width: width,
              active: secondaryOn,
              tooltip: tr('Subtitles'),
              onTap: () => _openSubtitles(context),
            ),
            if (primaryOn || secondaryOn)
              _IconBtn(
                icon: AppIcons.textAlignLeft,
                width: width,
                tooltip: tr('Subtitle list'),
                onTap: () {
                  _showBars();
                  _openSubtitleList(context);
                },
              ),
          ]);
        },
      );

  Widget _learningButtons(double width, {required bool few}) => ListenableBuilder(
        listenable: Listenable.merge([_c, _c.translationShown, _c.shadowStage]),
        builder: (context, _) {
          final c = _c;
          final settings = c.settings;
          final secondary = c.secondaryTrackId != 'no';
          final lines = settings.pauseEachLine && (_player.state.track.subtitle.id != 'no' || secondary);
          final blur = settings.blurSecondary && secondary;
          if (!lines && !blur) return const SizedBox.shrink();
          Widget button(IconData icon, String tooltip, VoidCallback action, {bool active = false}) => _IconBtn(
                icon: icon,
                size: 20,
                width: width,
                active: active,
                tooltip: tooltip,
                onTap: () {
                  _showBars();
                  action();
                },
              );
          final shown = c.translationShown.value;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            if (lines) ...[
              if (!few) button(AppIcons.skipBackFill, tr('Previous line'), () => unawaited(c.stepLine(-1))),
              button(AppIcons.arrowCounterClockwiseFill, tr('Replay this line'), () => unawaited(c.stepLine(0))),
              if (!few) button(AppIcons.skipForwardFill, tr('Next line'), () => unawaited(c.stepLine(1))),
              if (!few) button(AppIcons.repeatOnce, tr('Loop this line'), () => unawaited(c.toggleLineLoop()), active: c.loopB != null),
              _shadowButtons(width),
            ],
            if (blur) button(shown ? AppIcons.eye : AppIcons.eyeSlash, shown ? tr('Hide the translation') : tr('Show the translation'), c.toggleTranslation, active: shown),
          ]);
        },
      );

  Widget _shadowButtons(double width) {
    final c = _c;
    final stage = c.shadowStage.value;
    final recording = stage == ShadowStage.recording;
    final comparing = stage == ShadowStage.original || stage == ShadowStage.mine;
    final touch = touchFirst;
    final label = recording ? tr('Stop recording') : tr('Record yourself saying this line');
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _Pressable(
        tooltip: label,
        width: touch ? math.max(width, 44.0) : width,
        height: touch ? 44 : 34,
        onTap: () {
          _showBars();
          unawaited(c.toggleShadowing());
        },
        child: Icon(recording ? AppIcons.stopFill : AppIcons.microphoneFill, size: 20, color: recording ? const Color(0xFFFF4D4F) : Colors.white),
      ),
      if (c.hasShadowTake && !recording) ...[
        _IconBtn(
          icon: AppIcons.userSound,
          size: 20,
          width: width,
          active: comparing,
          tooltip: tr('Compare with the original'),
          onTap: () {
            _showBars();
            unawaited(comparing ? c.toggleShadowing() : c.compareShadowing());
          },
        ),
        Builder(
          builder: (anchor) => _IconBtn(
            icon: AppIcons.downloadSimple,
            size: 20,
            width: width,
            tooltip: tr('Save the recording'),
            onTap: () => unawaited(_pick<int>(
              anchor,
              title: tr('Save the recording'),
              current: -1,
              rows: [
                (0, tr('Only my recording')),
                (1, tr('The line, then my recording')),
                if (c.shadowTakeCount > 1) (2, tr('All {0} lines I recorded, each then mine', [c.shadowTakeCount])),
              ],
              onSelected: (index) => unawaited(c.saveShadowTake(ShadowExport.values[index])),
            )),
          ),
        ),
      ],
    ]);
  }
}

/// A text in the bar that opens a choice of values.
class _TextMenu<T> extends StatelessWidget {
  const _TextMenu({required this.host, required this.tooltip, required this.label, required this.current, required this.rows, required this.onSelected});
  final _PlayerControlsState host;
  final String tooltip;
  final String label;
  final T current;
  final List<(T, String)> rows;
  final void Function(T value) onSelected;

  @override
  Widget build(BuildContext context) => Builder(
        builder: (anchor) => _Pressable(
          tooltip: tooltip,
          height: touchFirst ? 44 : 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onTap: () {
            host._showBars();
            unawaited(host._pick<T>(anchor, title: tooltip, rows: rows, current: current, onSelected: onSelected));
          },
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      );
}

class _PlayButton extends StatefulWidget {
  const _PlayButton({required this.host});
  final _PlayerControlsState host;

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> with SingleTickerProviderStateMixin {
  late final AnimationController _icon = AnimationController(vsync: this, duration: Motion.of(Ease.fade), value: widget.host._player.state.playing ? 1 : 0);
  StreamSubscription<bool>? _subscription;
  late bool _playing = widget.host._player.state.playing;

  @override
  void initState() {
    super.initState();
    _subscription = widget.host._player.stream.playing.listen((playing) {
      // The name says what a press does now, for the screen reader.
      if (playing != _playing && mounted) setState(() => _playing = playing);
      if (playing) {
        unawaited(_icon.forward());
      } else {
        unawaited(_icon.reverse());
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _icon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final touch = touchFirst;
    return _Pressable(
      tooltip: _playing ? tr('Pause (Space)') : tr('Play (Space)'),
      width: touch ? 48 : 42,
      height: touch ? 40 : 34,
      onTap: () {
        widget.host._showBars();
        unawaited(widget.host._player.playOrPause());
      },
      child: AnimatedIcon(icon: AnimatedIcons.play_pause, progress: _icon, size: touch ? 26 : 20, color: Colors.white),
    );
  }
}

/// `position / duration`, redrawn when the whole second changes.
class _TimeText extends StatefulWidget {
  const _TimeText({required this.host});
  final _PlayerControlsState host;

  @override
  State<_TimeText> createState() => _TimeTextState();
}

class _TimeTextState extends State<_TimeText> {
  late int _seconds = widget.host._player.state.position.inSeconds;
  late Duration _duration = widget.host._player.state.duration;
  final _subscriptions = <StreamSubscription<Duration>>[];

  @override
  void initState() {
    super.initState();
    final stream = widget.host._player.stream;
    _subscriptions.add(stream.position.listen((position) {
      if (position.inSeconds != _seconds) setState(() => _seconds = position.inSeconds);
    }));
    _subscriptions.add(stream.duration.listen((duration) {
      if (duration != _duration) setState(() => _duration = duration);
    }));
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        '${formatPlaybackTime(Duration(seconds: _seconds))} / ${formatPlaybackTime(_duration)}',
        maxLines: 1,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
      );
}

/// The live stream's way back to the newest moment.
class _LiveButton extends StatelessWidget {
  const _LiveButton({required this.host});
  final _PlayerControlsState host;

  @override
  Widget build(BuildContext context) {
    final player = host._player;
    return StreamBuilder<Duration>(
      stream: host._livePositions.of(player),
      initialData: player.state.position,
      builder: (context, _) {
        final behind = player.state.duration - player.state.position > AppController.liveBehind;
        return _Pressable(
          tooltip: tr('Jump to the newest moment (End)'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          onTap: () {
            host._showBars();
            unawaited(host._c.goLive());
          },
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: behind ? Colors.white54 : const Color(0xFFFF2D2D)),
            ),
            const SizedBox(width: 6),
            Text(behind ? tr('Back to live') : tr('Live'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        );
      },
    );
  }
}

/// The volume button, with its slider opening beside it.
class _VolumeControl extends StatefulWidget {
  const _VolumeControl({required this.host, required this.width});
  final _PlayerControlsState host;
  final double width;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  bool _hover = false;
  bool _focused = false;
  bool _tapped = false;
  bool _reported = false;
  Timer? _timer;

  bool get _open => _hover || _focused || _tapped;

  void _sync() {
    if (_open == _reported) return;
    _reported = _open;
    if (_open) {
      widget.host._menuOpened();
    } else {
      widget.host._menuClosed();
    }
  }

  void _change(void Function() update) {
    setState(update);
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_reported) widget.host._menuClosed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final player = host._player;
    return MouseRegion(
      onEnter: (_) => _change(() => _hover = true),
      onExit: (_) => _change(() => _hover = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => _change(() => _focused = focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional),
        child: StreamBuilder<double>(
          stream: player.stream.volume,
          initialData: player.state.volume,
          builder: (context, snapshot) {
            final volume = snapshot.data ?? player.state.volume;
            final max = host._c.settings.volumeMax.toDouble();
            return Row(mainAxisSize: MainAxisSize.min, children: [
              _IconBtn(
                icon: volume == 0 ? AppIcons.speakerSlash : volume < 50 ? AppIcons.speakerLowFill : AppIcons.speakerHighFill,
                width: widget.width,
                tooltip: volume == 0 ? tr('Unmute (M)') : tr('Mute (M)'),
                onTap: () {
                  host._showBars();
                  unawaited(host._c.toggleMute());
                  _timer?.cancel();
                  _timer = Timer(const Duration(seconds: 4), () {
                    if (mounted) _change(() => _tapped = false);
                  });
                  _change(() => _tapped = true);
                },
              ),
              AnimatedSize(
                duration: Motion.of(Ease.fade),
                alignment: Alignment.centerLeft,
                child: _open
                    ? SizedBox(
                        width: 96,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: SliderComponentShape.noOverlay,
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white30,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            min: 0,
                            max: max,
                            value: volume.clamp(0.0, max),
                            onChanged: (value) => unawaited(player.setVolume(value)),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// The current chapter, opening the list of them.
class _ChapterMenu extends StatefulWidget {
  const _ChapterMenu({required this.host});
  final _PlayerControlsState host;

  @override
  State<_ChapterMenu> createState() => _ChapterMenuState();
}

class _ChapterMenuState extends State<_ChapterMenu> {
  int _index = -1;
  StreamSubscription<Duration>? _subscription;

  List<Chapter> get _chapters => widget.host._c.details?.chapters ?? const [];

  /// The last chapter starting at or before [position], as [Chapter.at]
  /// finds it: most ticks stay in the chapter they were in, and a jump is
  /// found by halving.
  int _indexAt(Duration position) {
    final chapters = _chapters;
    final i = _index;
    if (i >= 0 && i < chapters.length && chapters[i].start <= position && (i + 1 == chapters.length || chapters[i + 1].start > position)) return i;
    var low = 0, high = chapters.length - 1, found = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (chapters[mid].start <= position) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }

  @override
  void initState() {
    super.initState();
    final player = widget.host._player;
    _index = _indexAt(player.state.position);
    _subscription = coarse(player.stream.position, step: const Duration(milliseconds: 500)).listen((position) {
      final index = _indexAt(position);
      if (index != _index) setState(() => _index = index);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final c = host._c;
    return ValueListenableBuilder<int>(
      valueListenable: c.chaptersChanged,
      builder: (context, _, __) {
        final chapters = _chapters;
        if (chapters.isEmpty) return const SizedBox.shrink();
        final translated = c.translatedChapters;
        String translation(int i) {
          final text = translated != null && i < translated.length ? translated[i] : '';
          return text.isNotEmpty && text != chapters[i].title ? text : '';
        }

        final index = _index.clamp(0, chapters.length - 1);
        final shown = translation(index).isNotEmpty ? translation(index) : chapters[index].title;
        final bilingual = c.preferences.bilingualTranslation;
        String menuTitle(int i) => translation(i).isNotEmpty && bilingual ? '${translation(i)} · ${chapters[i].title}' : translation(i).isNotEmpty ? translation(i) : chapters[i].title;
        return Builder(
          builder: (anchor) => _Pressable(
            tooltip: tr('Chapters'),
            height: touchFirst ? 44 : 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onTap: () {
              host._showBars();
              unawaited(host._pick<int>(
                anchor,
                title: tr('Chapters'),
                current: _index < 0 ? 0 : _index,
                rows: [
                  for (var i = 0; i < chapters.length; i++) (i, '${formatPlaybackTime(chapters[i].start)}  ${menuTitle(i)}'),
                  if (translated == null) (-1, c.translatingChapters ? tr('Translating chapter names…') : tr('Translate chapter names')),
                ],
                onSelected: (i) {
                  if (i < 0) {
                    unawaited(c.translateChapters());
                  } else {
                    unawaited(c.seek(chapters[i].start));
                  }
                },
              ));
            },
            child: Text('·  $shown  ›', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        );
      },
    );
  }
}

/// The seek bar with everything the controller knows to draw on it.
class _ProgressSection extends StatefulWidget {
  const _ProgressSection({required this.host, required this.color, required this.gradient});
  final _PlayerControlsState host;
  final Color color;
  final Gradient? gradient;

  @override
  State<_ProgressSection> createState() => _ProgressSectionState();
}

class _ProgressSectionState extends State<_ProgressSection> {
  final _subscriptions = <StreamSubscription<Object?>>[];
  Duration? _last;

  @override
  void initState() {
    super.initState();
    final host = widget.host;
    final stream = host._player.stream;
    _subscriptions.add(stream.position.listen(_onPosition));
    _subscriptions.add(stream.duration.listen((_) => _refresh()));
    _subscriptions.add(stream.buffer.listen((_) {
      if (host._bars.value > 0 && _last == null) _refresh();
    }));
    host._bars.addStatusListener(_onBars);
  }

  @override
  void dispose() {
    widget.host._bars.removeStatusListener(_onBars);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  void _onBars(AnimationStatus status) {
    if (status == AnimationStatus.forward) _refresh();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onPosition(Duration position) {
    final host = widget.host;
    if (host._bars.value == 0) return;
    final total = host._player.state.duration.inMilliseconds;
    final step = Duration(milliseconds: (total / 1500).clamp(40, 500).round());
    final last = _last;
    if (last != null && position >= last && position - last < step) return;
    _last = position;
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final c = host._c;
    final player = host._player;
    final chapters = c.details?.chapters ?? const <Chapter>[];
    final loopA = c.loopA;
    final heat = host._heat;
    return VideoProgressBar(
      position: player.state.position,
      buffered: player.state.buffer,
      total: player.state.duration,
      color: widget.color,
      playedGradient: widget.gradient,
      segments: [
        for (final segment in c.segments) ProgressSegment(segment.start, segment.end, _sponsorColors[segment.category] ?? const Color(0xFF00D400)),
        if (loopA != null) ProgressSegment(loopA, c.loopB ?? loopA + const Duration(seconds: 1), const Color(0xCCFFFFFF)),
      ],
      chapterStarts: [for (final chapter in chapters) chapter.start],
      preview: host._preview,
      heatmap: c.preferences.showHeatmap && heat != null ? heat.values : null,
      labelOf: chapters.isEmpty ? null : (time) => '${formatPlaybackTime(time)} · ${Chapter.at(chapters, time)?.title ?? ''}',
      onSeek: (time) => unawaited(c.seek(time)),
    );
  }
}
