import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import 'playlist_order_button.dart';
import 'theme.dart';
import 'video_card.dart';

/// Where each video stands in a playlist's own order, first and last
/// time it is there, worked out once for each list instead of searched
/// for at every build.
final _places = Expando<(Map<String, int>, Map<String, int>)>();

/// Where the video [id] stands in [items], the [last] time it is there or
/// the first; -1 when it is not.
int _placeOf(List<VideoItem> items, String? id, {required bool last}) {
  if (id == null) return -1;
  final places = _places[items];
  final cached = places == null ? null : (last ? places.$2 : places.$1)[id];
  // A playlist's list may change in place; a stale answer is checked here
  // and the places worked out again.
  if (cached != null && cached < items.length && items[cached].id == id) return cached;
  final first = <String, int>{}, latest = <String, int>{};
  for (final (i, item) in items.indexed) {
    first.putIfAbsent(item.id, () => i);
    latest[item.id] = i;
  }
  _places[items] = (first, latest);
  return (last ? latest : first)[id] ?? -1;
}

/// The playlist the video was opened from, on the watch page: every video
/// in the order it plays, the one playing marked, with 正序 / 倒序. Slivers,
/// so a playlist of thousands builds only the tiles on screen.
List<Widget> playingListSlivers(BuildContext context, {required AppController controller, required Widget trailing, bool shrinkWrap = false}) {
  final list = controller.playingList!;
  final ordered = list.ordered;
  final place = _placeOf(list.items, controller.playing?.id, last: list.reversed);
  final index = place < 0 || !list.reversed ? place : ordered.length - 1 - place;
  // Shrink-wrapped, only the videos around the one playing.
  final from = shrinkWrap ? max(0, index - 2) : 0;
  final count = shrinkWrap ? min(ordered.length, from + 20) - from : ordered.length;
  final colors = context.colors;
  return [
    SliverToBoxAdapter(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, 0, Space.xs, 0),
          child: Text(list.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(Space.xs, Space.xxs, 0, Space.xs),
          child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(
                  index < 0 ? tr('Playlist · {0} videos', [ordered.length]) : tr('Playlist · {0}/{1}', [index + 1, ordered.length]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.outline, fontSize: 12),
                ),
              ),
              const SizedBox(width: Space.xs),
              PlaylistOrderButton(controller: controller, id: list.id),
            ]),
            trailing,
          ]),
        ),
      ]),
    ),
    SliverList.builder(
      itemCount: max(0, count),
      itemBuilder: (context, i) {
        final item = ordered[from + i];
        return Container(
          decoration: from + i == index ? BoxDecoration(color: colors.secondaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(Radii.l)) : null,
          child: CompactVideoTile(item: item, thumbnails: controller.thumbnailDirectory, onOpen: () => controller.play(item)),
        );
      },
    ),
  ];
}
