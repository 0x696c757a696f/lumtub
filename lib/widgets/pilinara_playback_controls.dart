import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Playback controls adapted from PiliNara's media_kit/libmpv player.
///
/// Copyright (C) PiliNara contributors.
/// Adapted for YTPlus under GPL-3.0-or-later without Bilibili or GetX state.
class PiliNaraPlaybackControls extends StatelessWidget {
  const PiliNaraPlaybackControls({
    super.key,
    required this.player,
    required this.timeLabel,
  });

  final Player player;
  final String Function(Duration value) timeLabel;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
        stream: player.stream.position,
        builder: (context, snapshot) {
          final position = snapshot.data ?? player.state.position;
          final duration = player.state.duration;
          final maximum = duration.inMilliseconds <= 0 ? 1.0 : duration.inMilliseconds.toDouble();
          final value = position.inMilliseconds.clamp(0, maximum.toInt()).toDouble();
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Column(
                children: [
                  Slider(
                    value: value,
                    max: maximum,
                    onChanged: duration.inMilliseconds <= 0
                        ? null
                        : (milliseconds) => player.seek(Duration(milliseconds: milliseconds.round())),
                  ),
                  Row(
                    children: [
                      PiliNaraPlayOrPauseButton(player: player),
                      _ControlButton(
                        tooltip: '快退 5 秒',
                        icon: Icons.replay_5_rounded,
                        onPressed: () => player.seek(position - const Duration(seconds: 5)),
                      ),
                      _ControlButton(
                        tooltip: '快进 5 秒',
                        icon: Icons.forward_5_rounded,
                        onPressed: () => player.seek(position + const Duration(seconds: 5)),
                      ),
                      Text('${timeLabel(position)} / ${timeLabel(duration)}', style: const TextStyle(color: Colors.white60)),
                      const Spacer(),
                      PopupMenuButton<double>(
                        tooltip: '播放速度',
                        initialValue: player.state.rate,
                        onSelected: player.setRate,
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 0.5, child: Text('0.5×')),
                          PopupMenuItem(value: 0.75, child: Text('0.75×')),
                          PopupMenuItem(value: 1.0, child: Text('正常速度')),
                          PopupMenuItem(value: 1.25, child: Text('1.25×')),
                          PopupMenuItem(value: 1.5, child: Text('1.5×')),
                          PopupMenuItem(value: 2.0, child: Text('2×')),
                        ],
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(Icons.speed_rounded),
                        ),
                      ),
                      StreamBuilder<double>(
                        stream: player.stream.volume,
                        builder: (context, snapshot) {
                          final volume = snapshot.data ?? player.state.volume;
                          return _ControlButton(
                            tooltip: volume == 0 ? '取消静音' : '静音',
                            icon: volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            onPressed: () => player.setVolume(volume == 0 ? 100 : 0),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
}

/// Adapted from PiliNara's animated PlayOrPauseButton with the external
/// controller removed.
class PiliNaraPlayOrPauseButton extends StatefulWidget {
  const PiliNaraPlayOrPauseButton({super.key, required this.player});

  final Player player;

  @override
  State<PiliNaraPlayOrPauseButton> createState() => _PiliNaraPlayOrPauseButtonState();
}

class _PiliNaraPlayOrPauseButtonState extends State<PiliNaraPlayOrPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late final StreamSubscription<bool> _playing;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      value: widget.player.state.playing ? 1 : 0,
      duration: const Duration(milliseconds: 200),
    );
    _playing = widget.player.stream.playing.listen((playing) {
      if (playing) {
        _animation.forward();
      } else {
        _animation.reverse();
      }
    });
  }

  @override
  void dispose() {
    _playing.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 42,
        height: 34,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.player.state.playing ? widget.player.pause() : widget.player.play(),
          child: Center(
            child: AnimatedIcon(
              semanticLabel: widget.player.state.playing ? '暂停' : '播放',
              progress: _animation,
              icon: AnimatedIcons.play_pause,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      );
}

/// Adapted from PiliNara's ComBtn: a compact desktop player control target.
class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.tooltip, required this.icon, required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 34,
          height: 34,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Icon(icon, size: 20),
          ),
        ),
      );
}
