import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../player_settings.dart';

/// Player toolbar below the video: quality, speed, audio track and subtitle
/// menus.
///
/// The speed menu and compact buttons are adapted from PiliNara's
/// media_kit/libmpv player. Copyright (C) PiliNara contributors.
/// Adapted for YTPlus under GPL-3.0-or-later without Bilibili or GetX state.
/// Play, seek, volume and fullscreen live in media_kit's on-video controls.
class PiliNaraPlayerToolbar extends StatelessWidget {
  const PiliNaraPlayerToolbar({super.key, required this.player, required this.maxHeight, required this.onQualitySelected, this.trailing = const []});

  final Player player;
  /// The quality limit, 0 for automatic.
  final int maxHeight;
  final ValueChanged<int> onQualitySelected;
  final List<Widget> trailing;

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) => StreamBuilder<Tracks>(
        stream: player.stream.tracks,
        initialData: player.state.tracks,
        builder: (context, _) => StreamBuilder<Track>(
          stream: player.stream.track,
          initialData: player.state.track,
          builder: (context, _) {
            final tracks = player.state.tracks;
            final selected = player.state.track;
            final audio = tracks.audio.where((t) => t.id != 'no').toList();
            final subtitles = tracks.subtitle;
            return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StreamBuilder<int?>(
                stream: player.stream.height,
                initialData: player.state.height,
                builder: (context, snapshot) {
                  final height = snapshot.data ?? 0;
                  final current = height > 0 ? '${height}p' : null;
                  return _MenuChip<int>(
                    icon: Icons.high_quality_outlined,
                    label: maxHeight == 0 ? (current == null ? '自动' : '自动 · $current') : (current ?? '${maxHeight}p'),
                    tooltip: '画质',
                    selected: maxHeight,
                    values: qualityHeights,
                    labelOf: (value) => value == 0 ? '自动' : '${value}p',
                    onSelected: onQualitySelected,
                  );
                },
              ),
              StreamBuilder<double>(
                stream: player.stream.rate,
                initialData: player.state.rate,
                builder: (context, snapshot) {
                  final rate = snapshot.data ?? 1.0;
                  return _MenuChip<double>(
                    icon: Icons.speed_rounded,
                    label: rate == 1.0 ? '倍速' : '${_trimRate(rate)}×',
                    tooltip: '播放速度',
                    selected: rate,
                    values: _speeds,
                    labelOf: (value) => value == 1.0 ? '正常' : '${_trimRate(value)}×',
                    onSelected: player.setRate,
                  );
                },
              ),
              if (audio.length > 1)
                _MenuChip<AudioTrack>(
                  icon: Icons.audiotrack_rounded,
                  label: _trackLabel(selected.audio.id, selected.audio.title, selected.audio.language, fallback: '音轨'),
                  tooltip: '音轨',
                  selected: selected.audio,
                  values: audio,
                  labelOf: (track) => _trackLabel(track.id, track.title, track.language),
                  onSelected: player.setAudioTrack,
                ),
              _MenuChip<SubtitleTrack>(
                icon: Icons.closed_caption_outlined,
                label: selected.subtitle.id == 'no' ? '字幕' : _trackLabel(selected.subtitle.id, selected.subtitle.title, selected.subtitle.language),
                tooltip: '字幕',
                selected: selected.subtitle,
                values: subtitles.isEmpty ? [SubtitleTrack.no()] : subtitles,
                labelOf: (track) => _trackLabel(track.id, track.title, track.language),
                onSelected: player.setSubtitleTrack,
              ),
              ...trailing,
            ]);
          },
        ),
      );

  static String _trimRate(double rate) => rate.toString().replaceFirst(RegExp(r'\.0$'), '');

  static String _trackLabel(String id, String? title, String? language, {String? fallback}) {
    if (id == 'auto') return fallback ?? '自动';
    if (id == 'no') return '关闭';
    final parts = [if (title != null && title.isNotEmpty) title, if (language != null && language.isNotEmpty) language];
    return parts.isEmpty ? '轨道 $id' : parts.join(' · ');
  }
}

class _MenuChip<T> extends StatelessWidget {
  const _MenuChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.values,
    required this.labelOf,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final T selected;
  final List<T> values;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => MenuAnchor(
        menuChildren: [
          for (final value in values)
            MenuItemButton(
              leadingIcon: SizedBox(width: 20, child: value == selected ? const Icon(Icons.check_rounded, size: 18) : null),
              onPressed: () => onSelected(value),
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: Text(labelOf(value), overflow: TextOverflow.ellipsis)),
            ),
        ],
        builder: (context, menu, _) => Tooltip(
          message: tooltip,
          child: FilledButton.tonalIcon(
            style: const ButtonStyle(visualDensity: VisualDensity(horizontal: -1, vertical: -1)),
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            icon: Icon(icon, size: 18),
            label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(label, overflow: TextOverflow.ellipsis)),
          ),
        ),
      );
}
