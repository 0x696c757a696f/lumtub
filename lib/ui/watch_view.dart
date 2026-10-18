import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app/app_controller.dart';
import '../widgets/pilinara_playback_controls.dart';
import 'common.dart';
import 'theme.dart';

class WatchView extends StatelessWidget {
  const WatchView({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final current = controller.playing!;
    final player = controller.player!;
    return SingleChildScrollView(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1200),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 8, 26, 36),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextButton.icon(onPressed: controller.stopWatching, icon: const Icon(Icons.arrow_back), label: const Text('返回列表')),
          const SizedBox(height: 10),
          AspectRatio(aspectRatio: 16 / 9, child: ClipRRect(borderRadius: BorderRadius.circular(15), child: ColoredBox(color: Colors.black, child: Video(controller: controller.videoController!)))),
          const SizedBox(height: 8),
          PiliNaraPlaybackControls(player: player, timeLabel: formatPlaybackTime),
          const SizedBox(height: 8),
          _TrackSelectors(player: player),
          const SizedBox(height: 20),
          Text(current.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22)),
          const SizedBox(height: 8),
          Text(current.channel, style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 17),
          const Text('使用 libmpv 直接播放；播放异常时可以检查 yt-dlp / Deno 更新。', style: TextStyle(color: Colors.white38, fontSize: 12)),
          if (controller.error != null) ErrorBanner(controller.error!),
        ]),
      ),
    )));
  }
}

class _TrackSelectors extends StatelessWidget {
  const _TrackSelectors({required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) => StreamBuilder<Tracks>(
        stream: player.stream.tracks,
        initialData: player.state.tracks,
        builder: (context, snapshot) {
          final tracks = snapshot.data ?? player.state.tracks;
          final selected = player.state.track;
          final audio = [...tracks.audio];
          final subtitles = [...tracks.subtitle];
          if (!audio.contains(selected.audio)) audio.insert(0, selected.audio);
          if (!subtitles.contains(selected.subtitle)) subtitles.insert(0, selected.subtitle);
          return Card(
            color: AppColors.surface,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              child: LayoutBuilder(builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;
                final audioMenu = DropdownButton<AudioTrack>(
                  value: selected.audio,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: audio.map((track) => DropdownMenuItem(value: track, child: Text(_trackLabel(track.id, track.title, track.language), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (track) { if (track != null) player.setAudioTrack(track); },
                );
                final subtitleMenu = DropdownButton<SubtitleTrack>(
                  value: selected.subtitle,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: subtitles.map((track) => DropdownMenuItem(value: track, child: Text(_trackLabel(track.id, track.title, track.language), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (track) { if (track != null) player.setSubtitleTrack(track); },
                );
                final children = [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('音轨', style: TextStyle(fontSize: 12, color: Colors.white54)), audioMenu])),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('字幕', style: TextStyle(fontSize: 12, color: Colors.white54)), subtitleMenu])),
                ];
                return compact ? Column(children: children) : Row(children: [children.first, const SizedBox(width: 18), children.last]);
              }),
            ),
          );
        },
      );

  static String _trackLabel(String id, String? title, String? language) {
    if (id == 'auto') return '自动';
    if (id == 'no') return '关闭';
    final parts = [if (title != null && title.isNotEmpty) title, if (language != null && language.isNotEmpty) language];
    return parts.isEmpty ? '轨道 $id' : parts.join(' · ');
  }
}
