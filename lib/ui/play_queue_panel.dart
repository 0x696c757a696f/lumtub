import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import 'theme.dart';
import 'video_card.dart';

/// The hand-made play queue (see [AppController.playQueue]): reorder by
/// dragging, remove one, clear. Shown at the top of the watch page's
/// up-next list while the queue has videos.
class PlayQueuePanel extends StatelessWidget {
  const PlayQueuePanel({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.playQueue.items;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 0, 4),
        child: Row(children: [
          Text(tr('播放队列'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(tr('{0} 个', [items.length]), style: TextStyle(color: context.colors.outline, fontSize: 12)),
          const Spacer(),
          TextButton(onPressed: controller.clearQueue, child: Text(tr('清空'))),
        ]),
      ),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: items.length,
        onReorderItem: controller.moveQueued,
        itemBuilder: (context, i) {
          final item = items[i];
          return Row(key: ValueKey(item.id), children: [
            Expanded(child: CompactVideoTile(item: item, thumbnails: controller.thumbnailDirectory, onOpen: () => controller.playQueued(item))),
            IconButton(tooltip: tr('从队列移除'), visualDensity: VisualDensity.compact, onPressed: () => controller.removeQueued(item.id), icon: const Icon(Icons.close_rounded, size: 18)),
            ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.drag_handle_rounded, size: 20))),
          ]);
        },
      ),
    ]);
  }
}
