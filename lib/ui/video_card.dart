import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../appearance_settings.dart';
import '../library_store.dart';
import '../models.dart';
import '../dearrow.dart';
import '../thumbnail_cache.dart';
import '../youtube_account.dart' show RemotePlaylist;
import 'common.dart';
import 'skeleton.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// Height of the text below a card's thumbnail: two title lines and one
/// channel line.
const _cardInfoHeight = 82.0;

/// [item]'s thumbnail, or DeArrow's frame for it when that is on and one
/// was chosen. [size] is a smaller YouTube file for small tiles, so they
/// do not download the large one the grid uses (newtube does the same).
ImageProvider thumbnailFor(VideoItem item, Directory? thumbnails, {int width = 480, String? size}) {
  final frame = deArrow.thumbnailOf(item.id);
  final file = size ?? VideoItem.thumbnailFile;
  final url = size == null ? item.thumbnail : 'https://i.ytimg.com/vi/${item.id}/$size.jpg';
  return ResizeImage.resizeIfNeeded(
    width,
    null,
    switch ((thumbnails, frame)) {
      (null, null) => NetworkImage(url),
      (null, final frame?) => NetworkImage(frame.toString()),
      (final dir?, null) => CachedThumbnail(url, CachedThumbnail.fileFor(dir, item.id, file)),
      (final dir?, final frame?) => CachedThumbnail(frame.toString(), CachedThumbnail.fileFor(dir, item.id, 'dearrow_${frame.queryParameters['time']}'), fallback: url),
    },
  );
}

/// [item]'s title, or DeArrow's when that is on.
String titleFor(VideoItem item) => deArrow.titleOf(item.id, item.title);

/// Column count and card height for a grid [width] wide.
/// The 推荐原因 line under a recommended card.
const _reasonHeight = 20.0;

({int columns, double itemHeight}) gridLayoutFor(double width) {
  final columns = max(1, ((width + AppStyle.cardSpacing) / (videoCardMinWidth + AppStyle.cardSpacing)).floor());
  final itemWidth = (width - AppStyle.cardSpacing * (columns - 1)) / columns;
  return (columns: columns, itemHeight: itemWidth * 9 / 16 + _cardInfoHeight);
}

/// Makes the app's library actions (favorites, playlists, channels, watch
/// progress) available to every card below it without passing them down.
class VideoActions extends InheritedWidget {
  const VideoActions({super.key, required this.controller, required super.child});
  final AppController controller;

  static AppController? of(BuildContext context) => context.getInheritedWidgetOfExactType<VideoActions>()?.controller;

  // Cards rebuild with their pages whenever the controller notifies.
  @override
  bool updateShouldNotify(VideoActions oldWidget) => false;
}

/// A lazily built grid of video cards as a sliver, so pages can put headers
/// above it in the same scroll view.
class SliverVideoGrid extends StatelessWidget {
  const SliverVideoGrid({super.key, required this.items, required this.onOpen, this.thumbnails, this.onRemove, this.removeLabel, this.reasons});
  final List<VideoItem> items;
  final void Function(VideoItem item) onOpen;
  final Directory? thumbnails;
  /// Adds a "remove" entry to each card's menu, for playlists.
  final void Function(VideoItem item)? onRemove;
  final String? removeLabel;
  /// A line under each card saying why it is there, by video id.
  final Map<String, String>? reasons;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
        sliver: SliverLayoutBuilder(builder: (context, constraints) {
          final layout = gridLayoutFor(constraints.crossAxisExtent);
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: layout.columns,
              mainAxisSpacing: AppStyle.cardSpacing,
              crossAxisSpacing: AppStyle.cardSpacing,
              mainAxisExtent: layout.itemHeight + (reasons == null ? 0 : _reasonHeight),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => VideoCard(
                item: items[i],
                thumbnails: thumbnails,
                onOpen: () => onOpen(items[i]),
                onRemove: onRemove == null ? null : () => onRemove!(items[i]),
                removeLabel: removeLabel,
                reason: reasons == null ? null : reasons![items[i].id] ?? '',
              ),
              childCount: items.length,
            ),
          );
        }),
      );
}

/// YouTube playlists as a grid of cards.
class SliverPlaylistGrid extends StatelessWidget {
  const SliverPlaylistGrid({super.key, required this.items, required this.onOpen});
  final List<PlaylistResult> items;
  final void Function(PlaylistResult item) onOpen;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
        sliver: SliverLayoutBuilder(builder: (context, constraints) {
          final layout = gridLayoutFor(constraints.crossAxisExtent);
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: layout.columns,
              mainAxisSpacing: AppStyle.cardSpacing,
              crossAxisSpacing: AppStyle.cardSpacing,
              mainAxisExtent: layout.itemHeight,
            ),
            delegate: SliverChildBuilderDelegate((context, i) => PlaylistCard(item: items[i], onOpen: () => onOpen(items[i])), childCount: items.length),
          );
        }),
      );
}

/// A YouTube playlist: its cover with the video count, title and channel.
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({super.key, required this.item, required this.onOpen});
  final PlaylistResult item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cover = item.thumbnail;
    return Card(
      child: InkWell(
        onTap: onOpen,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: AppStyle.thumbnailRadius,
              child: Stack(fit: StackFit.expand, children: [
                if (cover != null)
                  Image.network(cover, fit: BoxFit.cover, errorBuilder: (context, error, stack) => ColoredBox(color: colors.surfaceContainerHighest))
                else
                  ColoredBox(color: colors.surfaceContainerHighest),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 96,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.65),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 28),
                      if (item.count != null) Text(tr('{0} 个视频', [item.count]), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.38, fontWeight: FontWeight.w500, color: colors.onSurface))),
              Text(item.channel.isEmpty ? tr('播放列表') : tr('{0} · 播放列表', [item.channel]), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.outline)),
            ]),
          )),
        ]),
      ),
    );
  }
}

/// Placeholder cards shown while results load.
class SliverSkeletonGrid extends StatelessWidget {
  const SliverSkeletonGrid({super.key, this.rows = 3});
  final int rows;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
        sliver: SliverLayoutBuilder(builder: (context, constraints) {
          final layout = gridLayoutFor(constraints.crossAxisExtent);
          final width = constraints.crossAxisExtent;
          return SliverToBoxAdapter(child: Skeleton(child: SizedBox(
            width: width,
            child: Wrap(
              spacing: AppStyle.cardSpacing,
              runSpacing: AppStyle.cardSpacing,
              children: List.generate(layout.columns * rows, (_) => SizedBox(
                width: (width - AppStyle.cardSpacing * (layout.columns - 1)) / layout.columns - 0.01,
                height: layout.itemHeight,
                child: const _CardSkeleton(),
              )),
            ),
          )));
        }),
      );
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        AspectRatio(aspectRatio: 16 / 9, child: SkeletonBox(radius: AppStyle.radius)),
        SizedBox(height: 12),
        SkeletonBox(height: 14),
        SizedBox(height: 8),
        FractionallySizedBox(widthFactor: 0.6, child: SkeletonBox(height: 14)),
        SizedBox(height: 10),
        FractionallySizedBox(widthFactor: 0.4, child: SkeletonBox(height: 11)),
      ]);
}

/// Thumbnail-on-top video card with hover zoom and a right-click menu.
class VideoCard extends StatefulWidget {
  const VideoCard({super.key, required this.item, required this.onOpen, this.thumbnails, this.onRemove, this.removeLabel, this.reason});
  final VideoItem item;
  final VoidCallback onOpen;
  final Directory? thumbnails;
  final VoidCallback? onRemove;
  /// The menu entry for [onRemove]; 从此列表移除 unless given.
  final String? removeLabel;
  /// Why the card is recommended; null leaves the line out.
  final String? reason;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _hovered = false;
  Timer? _prefetch;
  Timer? _preview;
  /// Which of YouTube's three frames from the video (1–3) the hover preview
  /// shows; 0 while it shows the thumbnail.
  int _frame = 0;

  /// A pointer resting on a card starts resolving the video, so a click
  /// that follows starts playback sooner, and then previews it: YouTube
  /// keeps frames from a quarter, half and three quarters of the way in.
  void _hover(bool value) {
    setState(() {
      _hovered = value;
      _frame = 0;
    });
    _prefetch?.cancel();
    _preview?.cancel();
    if (!value) return;
    _prefetch = Timer(const Duration(milliseconds: 400), () => VideoActions.of(context)?.prefetch(widget.item));
    if (widget.item.isLive || widget.item.isUpcoming) return;
    _preview = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _frame = 1);
      _preview = Timer.periodic(const Duration(milliseconds: 1000), (_) {
        if (mounted) setState(() => _frame = _frame % 3 + 1);
      });
    });
  }

  @override
  void initState() {
    super.initState();
    deArrow.addListener(_branded);
  }

  /// DeArrow answered for some videos, maybe this one.
  void _branded() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    deArrow.removeListener(_branded);
    _prefetch?.cancel();
    _preview?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colors = context.colors;
    final meta = [
      if (item.channel.isNotEmpty) item.channel,
      if (item.viewCount != null) tr('{0}次观看', [formatCount(item.viewCount!)]),
    ].join(' · ');
    return Card(
      child: InkWell(
        onTap: widget.onOpen,
        onHover: _hover,
        onSecondaryTapUp: (details) => showVideoMenu(context, item, details.globalPosition, onOpen: widget.onOpen, onRemove: widget.onRemove, removeLabel: widget.removeLabel),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: AppStyle.thumbnailRadius,
              child: Stack(fit: StackFit.expand, children: [
                AnimatedScale(
                  scale: _hovered ? 1.04 : 1,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Image(
                    image: thumbnailFor(item, widget.thumbnails),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    frameBuilder: (context, child, frame, sync) => sync || frame != null ? child : ColoredBox(color: colors.surfaceContainerHighest),
                    errorBuilder: (context, _, __) => ColoredBox(color: colors.surfaceContainerHighest, child: Icon(Icons.ondemand_video_rounded, size: 40, color: colors.outline)),
                  ),
                ),
                if (_frame > 0) ...[
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Image.network(
                      'https://i.ytimg.com/vi/${item.id}/mq$_frame.jpg',
                      key: ValueKey(_frame),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      width: double.infinity,
                      height: double.infinity,
                      // Shown only once loaded, over the thumbnail.
                      frameBuilder: (context, child, frame, sync) => sync || frame != null ? child : const SizedBox.shrink(),
                      errorBuilder: (context, _, __) => const SizedBox.shrink(),
                    ),
                  ),
                  Positioned(left: 8, right: 8, top: 8, child: Row(children: [
                    for (var i = 1; i <= 3; i++)
                      Expanded(child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(color: i <= _frame ? Colors.white : Colors.white38, borderRadius: BorderRadius.circular(2)),
                      )),
                  ])),
                ],
                if (item.isLive || item.isUpcoming)
                  Positioned(right: 8, bottom: 8, child: DurationBadge(item.isLive ? tr('直播中') : tr('即将直播'), color: item.isLive ? const Color(0xFFCC0000) : null))
                else if (item.durationLabel.isNotEmpty)
                  Positioned(right: 8, bottom: 8, child: DurationBadge(item.durationLabel)),
                _ProgressBar(item: item),
              ]),
            ),
          ),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(titleFor(item), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.38, fontWeight: FontWeight.w500, color: colors.onSurface))),
              Text(meta.isEmpty ? 'YouTube' : meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.outline)),
              if (widget.reason case final reason?)
                SizedBox(
                  height: _reasonHeight,
                  child: Row(children: [
                    if (reason.isNotEmpty) ...[
                      Icon(Icons.auto_awesome_outlined, size: 12, color: colors.primary),
                      const SizedBox(width: 4),
                    ],
                    Expanded(child: Text(reason, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.primary))),
                  ]),
                ),
            ]),
          )),
        ]),
      ),
    );
  }
}

class DurationBadge extends StatelessWidget {
  const DurationBadge(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: color ?? Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(4)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500, fontFeatures: [FontFeature.tabularFigures()])),
        ),
      );
}

/// Compact horizontal card for the up-next list on the watch page.
class CompactVideoTile extends StatelessWidget {
  const CompactVideoTile({super.key, required this.item, required this.onOpen, this.thumbnails});
  final VideoItem item;
  final VoidCallback onOpen;
  final Directory? thumbnails;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: deArrow, builder: _tile);

  Widget _tile(BuildContext context, Widget? _) {
    final colors = context.colors;
    return InkWell(
      borderRadius: AppStyle.cardRadius,
      onTap: onOpen,
      onSecondaryTapUp: (details) => showVideoMenu(context, item, details.globalPosition, onOpen: onOpen),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 152,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(fit: StackFit.expand, children: [
                  Image(
                    image: thumbnailFor(item, thumbnails, width: 320, size: 'mqdefault'),
                    fit: BoxFit.cover,
                    errorBuilder: (context, _, __) => ColoredBox(color: colors.surfaceContainerHighest),
                  ),
                  if (item.durationLabel.isNotEmpty) Positioned(right: 4, bottom: 4, child: DurationBadge(item.durationLabel)),
                  _ProgressBar(item: item),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titleFor(item), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w500, color: colors.onSurface)),
            const SizedBox(height: 4),
            Text(item.channel.isEmpty ? 'YouTube' : item.channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.outline)),
          ])),
        ]),
      ),
    );
  }
}

/// How much of [item] was watched, as a bar along the thumbnail's bottom.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.item});
  final VideoItem item;

  @override
  Widget build(BuildContext context) {
    final progress = VideoActions.of(context)?.library?.progressOf(item.id);
    if (progress == null || progress.fraction < 0.02) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: LinearProgressIndicator(value: progress.fraction, minHeight: 3, backgroundColor: Colors.black45, color: context.colors.primary),
    );
  }
}

Future<void> showVideoMenu(BuildContext context, VideoItem item, Offset position, {required VoidCallback onOpen, VoidCallback? onRemove, String? removeLabel}) async {
  final controller = VideoActions.of(context);
  final library = controller?.library;
  final channel = item.channelRef;
  final favorite = library?.isFavorite(item.id) ?? false;
  final later = library?.isWatchLater(item.id) ?? false;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  PopupMenuItem<String> entry(String value, IconData icon, String label) =>
      PopupMenuItem(value: value, child: ListTile(dense: true, leading: Icon(icon), title: Text(label)));
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      entry('play', Icons.play_arrow_rounded, tr('播放')),
      if (library != null) ...[
        entry('favorite', favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, favorite ? tr('取消收藏') : tr('收藏')),
        entry('later', later ? Icons.watch_later_rounded : Icons.watch_later_outlined, later ? tr('从稍后观看移除') : tr('稍后观看')),
        entry('playlist', Icons.playlist_add_rounded, tr('添加到播放列表…')),
      ],
      if (controller != null) ...[
        entry('queueNext', Icons.playlist_play_rounded, tr('下一个播放')),
        entry('queueLast', Icons.queue_music_rounded, tr('加入播放队列')),
      ],
      if (controller?.account?.signedIn ?? false) entry('youtube', Icons.video_library_outlined, tr('保存到 YouTube 播放列表…')),
      if (controller != null && channel != null) ...[
        entry('channel', Icons.account_circle_outlined, tr('查看频道')),
        if (controller.preferences.isUnrecommended(channel.id))
          entry('recommend', Icons.thumb_up_off_alt_outlined, tr('恢复推荐此频道'))
        else
          entry('unrecommend', Icons.thumb_down_off_alt_outlined, tr('不推荐此频道')),
        entry('block', Icons.block_rounded, tr('屏蔽此频道')),
      ],
      if (onRemove != null)
        removeLabel == null
            ? entry('remove', Icons.remove_circle_outline_rounded, tr('从此列表移除'))
            : entry('remove', Icons.thumb_down_off_alt_outlined, removeLabel),
      const PopupMenuDivider(),
      entry('copy', Icons.link_rounded, tr('复制链接')),
      entry('browser', Icons.open_in_new_rounded, tr('在浏览器中打开')),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'play':
      onOpen();
    case 'favorite':
      final added = library!.toggleFavorite(item);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? tr('已收藏') : tr('已取消收藏'))));
    case 'later':
      final added = library!.toggleWatchLater(item);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? tr('已加入稍后观看') : tr('已从稍后观看移除'))));
    case 'queueNext':
      controller!.queueNext(item);
    case 'queueLast':
      controller!.queueLast(item);
    case 'playlist':
      await showAddToPlaylist(context, controller!, item);
    case 'youtube':
      await showSaveToYoutube(context, controller!, item);
    case 'channel':
      controller!.openChannel(channel!);
    case 'recommend' || 'unrecommend':
      controller!.setRecommendChannel(channel!, choice == 'recommend');
    case 'block':
      controller!.blockChannel(channel!);
    case 'remove':
      onRemove!();
    case 'copy':
      await copyText(context, item.url, tr('链接已复制'));
    case 'browser':
      await openExternal(item.url);
  }
}

/// Lets the user pick one of the account's YouTube playlists for [item],
/// or create a private one.
Future<void> showSaveToYoutube(BuildContext context, AppController controller, VideoItem item) async {
  final account = controller.account;
  if (account == null) return;
  final playlists = account.remotePlaylists();
  const create = '\u0000new';
  final choice = await showDialog<Object>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(tr('保存到 YouTube 播放列表')),
      children: [
        FutureBuilder<List<RemotePlaylist>>(
          future: playlists,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            }
            final list = snapshot.data ?? const <RemotePlaylist>[];
            return Column(mainAxisSize: MainAxisSize.min, children: [
              for (final playlist in list)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, playlist),
                  child: ListTile(dense: true, leading: const Icon(Icons.playlist_play_rounded), title: Text(playlist.title), subtitle: Text(tr('{0} 个视频', [playlist.count]))),
                ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, create),
                child: ListTile(dense: true, leading: Icon(Icons.add_rounded), title: Text(tr('新建私享播放列表…'))),
              ),
            ]);
          },
        ),
      ],
    ),
  );
  if (!context.mounted || choice == null) return;
  if (choice is RemotePlaylist) return account.saveToPlaylist(item, playlist: choice);
  final title = await promptText(context, title: tr('新建 YouTube 播放列表'), hint: tr('播放列表名称'), confirm: tr('创建并保存'));
  if (title != null && title.trim().isNotEmpty) await account.saveToPlaylist(item, newTitle: title);
}

/// Lets the user pick a playlist for [item], or create one.
Future<void> showAddToPlaylist(BuildContext context, AppController controller, VideoItem item) async {
  final library = controller.library;
  if (library == null) return;
  const create = '\u0000new';
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(tr('添加到播放列表')),
      children: [
        for (final playlist in library.playlists)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, playlist.id),
            child: ListTile(leading: const Icon(Icons.playlist_play_rounded), title: Text(playlist.name), subtitle: Text(tr('{0} 个视频', [playlist.items.length]))),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, create),
          child: ListTile(leading: Icon(Icons.add_rounded), title: Text(tr('新建播放列表'))),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  final playlist = choice == create ? await _createPlaylist(context, controller) : library.playlist(choice);
  if (playlist == null || !context.mounted) return;
  final added = library.addToPlaylist(playlist, item);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? tr('已添加到“{0}”', [playlist.name]) : tr('“{0}”里已经有这个视频', [playlist.name]))));
}

Future<LocalPlaylist?> _createPlaylist(BuildContext context, AppController controller) async {
  final name = await promptText(context, title: tr('新建播放列表'), hint: tr('播放列表名称'), confirm: tr('创建'));
  return name == null ? null : controller.library?.createPlaylist(name);
}

/// Asks for one line of text; null when cancelled.
Future<String?> promptText(BuildContext context, {required String title, required String hint, required String confirm, String initial = ''}) {
  final text = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: text,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('取消'))),
        FilledButton(onPressed: () => Navigator.pop(context, text.text), child: Text(confirm)),
      ],
    ),
  ).whenComplete(text.dispose);
}
