import 'dart:math';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import 'playlist_order_button.dart';
import 'theme.dart';
import 'video_card.dart';

/// The playlist the video was opened from, on the watch page: every video
/// in the order it plays, the one playing marked, with 正序 / 倒序.
class PlayingListPanel extends StatelessWidget {
  const PlayingListPanel({super.key, required this.controller, required this.trailing, this.shrinkWrap = false});
  final AppController controller;
  /// Shown beside the order button, such as the 自动连播 switch.
  final Widget trailing;
  /// Lists only the videos around the one playing.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final list = controller.playingList!;
    final ordered = list.ordered;
    final index = ordered.indexWhere((item) => item.id == controller.playing?.id);
    final from = shrinkWrap ? max(0, index - 2) : 0;
    final shown = shrinkWrap ? ordered.skip(from).take(20) : ordered;
    final colors = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, 0, Space.xs, 0),
        child: Text(list.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, Space.xxs, 0, Space.xs),
        child: Row(children: [
          Text(
            index < 0 ? tr('播放列表 · {0} 个', [ordered.length]) : tr('播放列表 · {0}/{1}', [index + 1, ordered.length]),
            style: TextStyle(color: colors.outline, fontSize: 12),
          ),
          const SizedBox(width: Space.xs),
          PlaylistOrderButton(controller: controller, id: list.id),
          const Spacer(),
          trailing,
        ]),
      ),
      for (final (i, item) in shown.indexed)
        Container(
          decoration: from + i == index ? BoxDecoration(color: colors.secondaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(Radii.l)) : null,
          child: CompactVideoTile(item: item, thumbnails: controller.thumbnailDirectory, onOpen: () => controller.play(item)),
        ),
    ]);
  }
}
