import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../device.dart';
import '../app/app_controller.dart';
import '../appearance_settings.dart';
import '../library_store.dart';
import '../models.dart';
import '../dearrow.dart';
import '../thumbnail_cache.dart';
import '../youtube_account.dart' show RemotePlaylist;
import 'common.dart';
import 'pages/downloads_page.dart';
import 'skeleton.dart';
import 'skin_paint.dart';
import 'theme.dart';
import '../l10n/l10n.dart';
import '../video_facts_lookup.dart';
import 'motion.dart';
import 'app_icons.dart';
import '../feed_reason.dart';

/// Height of the text below a card's thumbnail: two title lines and one
/// line with the reason, the channel and the menu. The views and age sit
/// on the thumbnail, as Bilibili shows them.
/// The text grows with [textScale] (the app's text size, Android's font
/// size and a TV's larger text); the padding round it does not.
double _cardInfoHeight(double textScale) => compactCards ? 10 + 60 * textScale : 14 + 62 * textScale;

/// How much larger than set the cards' text is drawn here.
double cardTextScale(BuildContext context) => MediaQuery.textScalerOf(context).scale(14) / 14;

/// The gap between cards; tighter in compact mode, where cards sit on a
/// surface of their own.
double get gridGap => compactCards ? Space.s : AppStyle.cardSpacing;
double get _gridRowGap => compactCards ? Space.m : AppStyle.cardSpacing;

/// The narrowest card in compact mode is this part of the chosen width.
const _compactWidth = 0.8;

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
      // Without the cache folder still within the download limits.
      (null, null) => CachedThumbnail(url, null),
      (null, final frame?) => CachedThumbnail(frame.toString(), null, fallback: CachedThumbnail(url, null)),
      (final dir?, null) => CachedThumbnail(url, CachedThumbnail.fileFor(dir, item.id, file)),
      (final dir?, final frame?) => CachedThumbnail(frame.toString(), CachedThumbnail.fileFor(dir, item.id, 'dearrow_${frame.queryParameters['time']}'), fallback: CachedThumbnail(url, CachedThumbnail.fileFor(dir, item.id, file))),
    },
  );
}

/// The decode width for a thumbnail shown [logical] pixels wide: the real
/// size, in steps so resizing the window does not decode again at every
/// pixel, and never above the width of the file shown ([largest], by
/// default the thumbnail size chosen in Settings) or below 160.
int thumbnailDecodeWidth(double logical, double pixelRatio, {int? largest}) {
  final steps = (logical * pixelRatio / 80).ceil();
  return (steps * 80).clamp(160, largest ?? thumbnailFileWidth(VideoItem.thumbnailFile));
}

/// How wide YouTube's thumbnail file [name] is.
int thumbnailFileWidth(String name) => switch (name) {
      'mqdefault' => 320,
      'sddefault' => 640,
      'maxresdefault' => 1280,
      _ => 480,
    };

/// [item]'s title, or DeArrow's when that is on.
String titleFor(VideoItem item) => deArrow.titleOf(item.id, item.title);

/// Column count and card height for a grid [width] wide.
/// The watched line under a history card.
const _reasonHeight = 20.0;

/// [padding] is the space a skin leaves round each video card.
({int columns, double itemHeight}) gridLayoutFor(double width, {double padding = 0, double textScale = 1}) {
  // A TV is seen from across the room, so its few pixels across still fit
  // three or four cards a row, as TV video apps show them.
  final base = Device.tv ? min(videoCardMinWidth, 200.0) : videoCardMinWidth;
  final narrowest = compactCards ? base * _compactWidth : base;
  final columns = max(1, ((width + gridGap) / (narrowest + gridGap)).floor());
  final itemWidth = (width - gridGap * (columns - 1)) / columns;
  return (columns: columns, itemHeight: (itemWidth - 2 * padding) * 9 / 16 + _cardInfoHeight(textScale) + 2 * padding);
}

/// The space the current skin leaves round each video card.
double skinCardPadding(BuildContext context) => context.skin?.videoCard == null ? 0 : context.skin!.videoCardPadding;

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
  const SliverVideoGrid({super.key, required this.items, required this.onOpen, this.thumbnails, this.onRemove, this.removeLabel, this.reasons, this.watched});
  final List<VideoItem> items;
  final void Function(VideoItem item) onOpen;
  final Directory? thumbnails;
  /// Adds a "remove" entry to each card's menu, for playlists.
  final void Function(VideoItem item)? onRemove;
  final String? removeLabel;
  /// Why each card is there, by video id ([FeedReason]), shown as a tag
  /// before its channel.
  final Map<String, String>? reasons;
  /// When each video was watched, by id, as a line under its card.
  final Map<String, String>? watched;

  @override
  Widget build(BuildContext context) {
    // Room for the watched line only when some card has one.
    final watched = this.watched != null && items.any((item) => this.watched![item.id] != null) ? this.watched : null;
    // Room for the reason line only when some card has a reason.
    final reasoned = reasons != null && items.any((item) => (reasons![item.id] ?? '').isNotEmpty);
    return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
        sliver: videoLayout != VideoLayout.grid
            ? SliverFixedExtentList(
                itemExtent: VideoRow.heightFor(videoLayout) + (watched == null ? 0 : _reasonHeight),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => VideoRow(
                    key: ValueKey(items[i].id),
                    item: items[i],
                    layout: videoLayout,
                    thumbnails: thumbnails,
                    onOpen: () => onOpen(items[i]),
                    onRemove: onRemove == null ? null : () => onRemove!(items[i]),
                    removeLabel: removeLabel,
                    reason: reasons == null ? null : reasons![items[i].id] ?? '',
                    watched: watched?[items[i].id],
                  ),
                  childCount: items.length,
                ),
              )
            : SliverLayoutBuilder(builder: (context, constraints) {
          final layout = gridLayoutFor(constraints.crossAxisExtent, padding: skinCardPadding(context), textScale: cardTextScale(context));
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: layout.columns,
              mainAxisSpacing: _gridRowGap,
              crossAxisSpacing: gridGap,
              mainAxisExtent: layout.itemHeight + ((watched == null ? 0 : 1) + (reasoned ? 1 : 0)) * _reasonHeight * cardTextScale(context),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => VideoCard(
                // A card's hover and preview state never passes to another
                // video when the list changes under it.
                key: ValueKey(items[i].id),
                item: items[i],
                thumbnails: thumbnails,
                onOpen: () => onOpen(items[i]),
                onRemove: onRemove == null ? null : () => onRemove!(items[i]),
                removeLabel: removeLabel,
                reason: reasons == null ? null : reasons![items[i].id] ?? '',
                watched: watched?[items[i].id],
              ),
              childCount: items.length,
            ),
          );
        }),
      );
  }
}

/// What [SliverVideoGrid.watched] shows for each time: "3 days ago", made
/// only for the cards asked about, so a long history costs nothing extra.
Map<String, String> watchedLabels(Map<String, DateTime> times) => _WatchedLabels(times);

class _WatchedLabels extends UnmodifiableMapBase<String, String> {
  _WatchedLabels(this._times);
  final Map<String, DateTime> _times;

  @override
  String? operator [](Object? key) => switch (_times[key]) { final at? => formatAgo(at), null => null };

  @override
  Iterable<String> get keys => _times.keys;
}

/// A video as one row of a list: a small thumbnail or none, the title, the
/// channel and views, for 列表 and 纯文字. Fewer and smaller pictures than
/// the grid, so long lists scroll lighter.
class VideoRow extends StatelessWidget {
  const VideoRow({super.key, required this.item, required this.layout, required this.onOpen, this.thumbnails, this.onRemove, this.removeLabel, this.reason, this.watched});
  final VideoItem item;
  final VideoLayout layout;
  final VoidCallback onOpen;
  final Directory? thumbnails;
  final VoidCallback? onRemove;
  final String? removeLabel;
  final String? reason;
  final String? watched;

  static const _thumbWidth = 168.0;

  static double heightFor(VideoLayout layout) => layout == VideoLayout.text ? 60.0 : _thumbWidth * 9 / 16 + Space.s * 2;

  void _menu(BuildContext context, Offset position) => unawaited(showVideoMenu(context, item, position, onOpen: onOpen, onRemove: onRemove, removeLabel: removeLabel));

  @override
  Widget build(BuildContext context) => WithVideoFacts(item, builder: _build);

  Widget _build(BuildContext context, VideoItem item) {
    final colors = context.colors;
    final text = layout == VideoLayout.text;
    final status = item.isLive ? tr('Live now') : item.isUpcoming ? tr('Upcoming live') : null;
    final meta = MetaLine.of(item, extra: text && status == null && item.durationLabel.isNotEmpty ? item.durationLabel : null, style: TextStyle(fontSize: 12, color: colors.outline));
    return InkWell(
      borderRadius: AppStyle.controlRadius,
      onTap: onOpen,
      onSecondaryTapUp: (details) => _menu(context, details.globalPosition),
      onLongPress: () => _menu(context, _centreOf(context)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s, horizontal: Space.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!text) ...[
            SizedBox(
              width: _thumbWidth,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: AppStyle.controlRadius,
                  child: Stack(fit: StackFit.expand, children: [
                    Image(
                      color: context.pictureWarmth,
                      colorBlendMode: BlendMode.multiply,
                      image: thumbnailFor(item, thumbnails, width: 320, size: 'mqdefault'),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (context, _, __) => ColoredBox(color: colors.surfaceContainerHighest),
                    ),
                    if (status != null)
                      PositionedDirectional(end: 4, bottom: 4, child: DurationBadge(status, color: item.isLive ? const Color(0xFFCC0000) : null))
                    else if (item.durationLabel.isNotEmpty)
                      PositionedDirectional(end: 4, bottom: 4, child: DurationBadge(item.durationLabel)),
                    if (item.membersOnly) const PositionedDirectional(start: 4, bottom: 4, child: MembersOnlyBadge()),
                    _ProgressBar(item: item),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: Space.m),
          ],
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titleFor(item), maxLines: text ? 1 : 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.38, fontWeight: FontWeight.w500, color: colors.onSurface)),
            const SizedBox(height: Space.xs),
            Row(children: [
              if (text && status != null) ...[
                Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: item.isLive ? const Color(0xFFCC0000) : colors.primary)),
                const SizedBox(width: Space.s),
              ],
              if (text && item.membersOnly) ...[
                Text(tr('Members only'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2BA640))),
                const SizedBox(width: Space.s),
              ],
              if (reason case final reason? when reason.isNotEmpty) ...[
                ReasonTag(reason),
                const SizedBox(width: 6),
              ],
              Expanded(child: meta),
            ]),
            if (watched case final watched?) Padding(padding: const EdgeInsets.only(top: Space.xs), child: WatchedLine(watched)),
          ])),
        ]),
      ),
    );
  }
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
          final layout = gridLayoutFor(constraints.crossAxisExtent, textScale: cardTextScale(context));
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: layout.columns,
              mainAxisSpacing: _gridRowGap,
              crossAxisSpacing: gridGap,
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
      color: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppStyle.cardRadius),
      clipBehavior: Clip.none,
      child: InkWell(
        borderRadius: AppStyle.cardRadius,
        onTap: onOpen,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: AppStyle.thumbnailRadius,
              child: Stack(fit: StackFit.expand, children: [
                if (cover != null)
                  LayoutBuilder(builder: (context, box) => Image(
                    color: context.pictureWarmth,
                    colorBlendMode: BlendMode.multiply,
                    image: ResizeImage.resizeIfNeeded(thumbnailDecodeWidth(box.maxWidth, MediaQuery.devicePixelRatioOf(context), largest: 480), null, CachedThumbnail(cover, null)),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => ColoredBox(color: colors.surfaceContainerHighest),
                  ))
                else
                  ColoredBox(color: colors.surfaceContainerHighest),
                PositionedDirectional(
                  end: 0,
                  top: 0,
                  bottom: 0,
                  width: 96,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.65),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(AppIcons.playlist, color: Colors.white, size: 28),
                      if (item.count != null) Text(tr('{0} videos', [item.count]), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Flexible(child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.38, fontWeight: FontWeight.w500, color: colors.onSurface))),
              const SizedBox(height: Space.xs),
              Text(item.channel.isEmpty ? tr('Playlist') : tr('{0} · Playlist', [item.channel]), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.outline)),
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
          final layout = gridLayoutFor(constraints.crossAxisExtent, padding: skinCardPadding(context), textScale: cardTextScale(context));
          final width = constraints.crossAxisExtent;
          return SliverToBoxAdapter(child: Skeleton(child: SizedBox(
            width: width,
            child: Wrap(
              spacing: gridGap,
              runSpacing: _gridRowGap,
              children: List.generate(layout.columns * rows, (_) => SizedBox(
                width: (width - gridGap * (layout.columns - 1)) / layout.columns - 0.01,
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
        SizedBox(height: 8),
        FractionallySizedBox(widthFactor: 0.4, child: SkeletonBox(height: 11)),
      ]);
}

/// Thumbnail-on-top video card with hover zoom and a right-click menu.
class VideoCard extends StatefulWidget {
  const VideoCard({super.key, required this.item, required this.onOpen, this.thumbnails, this.onRemove, this.removeLabel, this.reason, this.watched});
  final VideoItem item;
  final VoidCallback onOpen;
  final Directory? thumbnails;
  final VoidCallback? onRemove;
  /// The menu entry for [onRemove]; 从此列表移除 unless given.
  final String? removeLabel;
  /// Why the card is recommended; null leaves the line out.
  final String? reason;
  /// When the video was watched, shown on its picture.
  final String? watched;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _hovered = false;
  /// Reached with the keyboard: it shows its actions as a pointer resting
  /// on it would, with an outline to show where focus is, but does not
  /// prefetch or preview.
  bool _focused = false;
  bool _pointer = false;
  Timer? _prefetch;
  Timer? _preview;
  /// Which of YouTube's three frames from the video (1–3) the hover preview
  /// shows; 0 while it shows the thumbnail.
  int _frame = 0;

  /// A pointer resting on a card starts resolving the video, so a click
  /// that follows starts playback sooner, and then previews it: YouTube
  /// keeps frames from a quarter, half and three quarters of the way in.
  void _hover(bool value) {
    if (value == _hovered) return;
    setState(() {
      _hovered = value;
      _frame = 0;
    });
    _prefetch?.cancel();
    _preview?.cancel();
    // 低占用模式 loads nothing until a video is opened.
    if (!value || !_pointer || lowResourceMode) return;
    if (!widget.item.membersOnly) _prefetch = Timer(const Duration(milliseconds: 700), () => VideoActions.of(context)?.prefetch(widget.item, hover: true));
    if (widget.item.isLive || widget.item.isUpcoming) return;
    _preview = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _frame = 1);
      _preview = Timer.periodic(const Duration(milliseconds: 1000), (_) {
        if (mounted) setState(() => _frame = _frame % 3 + 1);
      });
    });
  }

  void _pointerOver(bool value) {
    _pointer = value;
    _hover(_pointer || _focused);
  }

  void _focus(bool value) {
    setState(() => _focused = value);
    _hover(_pointer || _focused);
    if (!_pointer) {
      _prefetch?.cancel();
      _preview?.cancel();
    }
  }

  /// The menu, at the card's middle when opened from the keyboard.
  void _menu([Offset? at]) {
    final box = context.findRenderObject() as RenderBox?;
    final position = at ?? (box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero)));
    unawaited(showVideoMenu(context, widget.item, position, onOpen: widget.onOpen, onRemove: widget.onRemove, removeLabel: widget.removeLabel));
  }

  ImageProvider _frameImage(VideoItem item, int frame) {
    final url = 'https://i.ytimg.com/vi/${item.id}/mq$frame.jpg';
    final dir = widget.thumbnails;
    // mq frames are 320 wide; decoding them larger gains nothing.
    return ResizeImage.resizeIfNeeded(320, null, CachedThumbnail(url, dir == null ? null : CachedThumbnail.fileFor(dir, item.id, 'mq$frame')));
  }

  @override
  void initState() {
    super.initState();
    deArrow.addListener(_branded);
  }

  /// DeArrow answered for some videos, maybe this one: answers come in
  /// bursts while a feed loads, so only a card whose branding changed
  /// builds again.
  void _branded() {
    if (mounted && _branding != _brandingNow()) setState(() {});
  }

  (String, Uri?) _brandingNow() => (deArrow.titleOf(widget.item.id, widget.item.title), deArrow.thumbnailOf(widget.item.id));
  (String, Uri?)? _branding;

  @override
  void dispose() {
    deArrow.removeListener(_branded);
    _prefetch?.cancel();
    _preview?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WithVideoFacts(widget.item, builder: _build);

  Widget _build(BuildContext context, VideoItem item) {
    _branding = _brandingNow();
    final colors = context.colors;
    final metaStyle = TextStyle(fontSize: 12, color: colors.outline);
    final meta = MetaLine.of(item, style: metaStyle);
    final views = MetaLine.viewsOf(item);
    // A picture and text on the page, as YouTube shows them: no box round,
    // unless a skin puts cards on a surface. Compact cards sit on a quiet
    // surface of their own, so tightly packed ones still read apart.
    final skin = context.skin;
    final compact = compactCards && skin?.videoCard == null;
    final card = Card(
      color: compact ? colors.surfaceContainerLow : Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppStyle.cardRadius),
      clipBehavior: compact ? Clip.antiAlias : Clip.none,
      child: InkWell(
        borderRadius: AppStyle.cardRadius,
        hoverColor: Colors.transparent,
        onTap: widget.onOpen,
        onHover: _pointerOver,
        onFocusChange: _focus,
        onSecondaryTapUp: (details) => _menu(details.globalPosition),
        onLongPress: () => _menu(_centreOf(context)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: compact ? BorderRadius.zero : context.thumbnailRadius,
              child: Stack(fit: StackFit.expand, children: [
                AnimatedScale(
                  scale: _hovered ? 1.04 : 1,
                  duration: Motion.of(Ease.fade),
                  curve: Ease.curve,
                  child: LayoutBuilder(
                    builder: (context, box) => Image(
                      color: context.pictureWarmth,
                      colorBlendMode: BlendMode.multiply,
                      image: thumbnailFor(item, widget.thumbnails, width: thumbnailDecodeWidth(box.maxWidth, MediaQuery.devicePixelRatioOf(context))),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      frameBuilder: (context, child, frame, sync) => sync || frame != null ? child : ColoredBox(color: colors.surfaceContainerHighest),
                      errorBuilder: (context, _, __) => ColoredBox(color: colors.surfaceContainerHighest, child: Icon(AppIcons.televisionSimple, size: 40, color: colors.outline)),
                    ),
                  ),
                ),
                if (_frame > 0) ...[
                  AnimatedSwitcher(
                    duration: Motion.of(const Duration(milliseconds: 250)),
                    child: Image(
                      color: context.pictureWarmth,
                      colorBlendMode: BlendMode.multiply,
                      // The frames are cached on disk like thumbnails, so
                      // hovering the same card again reads no network.
                      image: _frameImage(item, _frame),
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
                // Views over a shade at the foot of the picture, the length
                // at its end; the age goes with the channel below, where a
                // narrow card can't cut it off.
                if (views != null)
                  const Positioned(left: 0, right: 0, bottom: 0, height: 48, child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x8C000000), Color(0xBF000000)], stops: [0, 0.6, 1]),
                  )))),
                if (views != null)
                  PositionedDirectional(start: 8, end: 80, bottom: 7, child: Text(
                    views,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500, shadows: [Shadow(blurRadius: 3, color: Color(0x80000000))]),
                  )),
                if (item.isLive || item.isUpcoming)
                  PositionedDirectional(end: 8, bottom: 6, child: DurationBadge(item.isLive ? tr('Live now') : tr('Upcoming live'), color: item.isLive ? const Color(0xFFCC0000) : null))
                else if (item.durationLabel.isNotEmpty)
                  PositionedDirectional(end: 8, bottom: 6, child: DurationBadge(item.durationLabel)),
                if (item.membersOnly) const PositionedDirectional(start: 8, top: 8, child: MembersOnlyBadge()),
                _ProgressBar(item: item),
                if (_hovered) PositionedDirectional(top: 8, end: 8, child: _QuickActions(item: item)),
              ]),
            ),
          ),
          Expanded(child: Padding(
            padding: compact ? const EdgeInsets.fromLTRB(8, 6, 8, 4) : const EdgeInsets.fromLTRB(2, 10, 2, 4),
            // The channel line keeps to the card's foot, however long the
            // title, so a row of cards lines up.
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Align(alignment: AlignmentDirectional.topStart, child: Text(titleFor(item), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 13 : 14, height: compact ? 1.32 : 1.38, fontWeight: FontWeight.w500, color: colors.onSurface)))),
              // Why it is here, on a line of its own so it reads whole.
              if (widget.reason case final reason? when reason.isNotEmpty)
                SizedBox(height: _reasonHeight * cardTextScale(context), child: Align(alignment: AlignmentDirectional.centerStart, child: ReasonTag(reason, wide: true))),
              // Whose it is, and its menu.
              SizedBox(
                height: 24,
                child: Row(children: [
                  Expanded(child: MetaLine(lead: meta.lead.isEmpty ? tr('YouTube') : meta.lead, tail: MetaLine.ageOf(item) ?? '', style: metaStyle)),
                  Builder(builder: (context) => IconButton(
                    tooltip: tr('More (Menu key)'),
                    onPressed: () => _menu(_centreOf(context)),
                    icon: Icon(AppIcons.dotsThreeVertical, size: touchFirst ? 18 : 16, color: colors.outline),
                    padding: EdgeInsets.zero,
                    // Wider for a finger; the row's height stays.
                    constraints: BoxConstraints.tightFor(width: touchFirst ? 40 : 24, height: 24),
                    visualDensity: VisualDensity.compact,
                  )),
                ]),
              ),
              if (widget.watched case final watched?) SizedBox(height: _reasonHeight * cardTextScale(context), child: WatchedLine(watched)),
            ]),
          )),
        ]),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.contextMenu): _menu,
        const SingleActivator(LogicalKeyboardKey.f10, shift: true): _menu,
      },
      child: Stack(children: [
        if (skin?.videoCard case final surface?)
          SkinBox(
            surface: surface.forState(hovered: _hovered, focused: _focused),
            radius: context.cardRadius.topLeft.x,
            padding: EdgeInsets.all(skin!.videoCardPadding),
            child: card,
          )
        else
          card,
        if (_focused)
          Positioned.fill(child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
            borderRadius: AppStyle.cardRadius,
            border: Border.all(color: colors.primary, width: 2),
          )))),
      ]),
    );
  }
}

/// 稍后观看, 加入播放队列 and the menu over a card's thumbnail while it is
/// pointed at or focused, so they need no right click.
class _QuickActions extends StatefulWidget {
  const _QuickActions({required this.item});
  final VideoItem item;

  @override
  State<_QuickActions> createState() => _QuickActionsState();
}

class _QuickActionsState extends State<_QuickActions> {
  @override
  Widget build(BuildContext context) {
    final controller = VideoActions.of(context);
    final library = controller?.library;
    final item = widget.item;
    final later = library?.isWatchLater(item.id) ?? false;
    Widget button(IconData icon, String tip, VoidCallback onPressed) => Padding(
          padding: const EdgeInsetsDirectional.only(start: 4),
          child: Tooltip(
            message: tip,
            child: Material(
              color: Colors.black.withValues(alpha: 0.72),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                canRequestFocus: false,
                onTap: onPressed,
                child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 18, color: Colors.white)),
              ),
            ),
          ),
        );
    void notice(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (library != null)
        button(later ? AppIcons.clockFill : AppIcons.clock, later ? tr('Remove from Watch later') : tr('Watch later'), () {
          final added = library.toggleWatchLater(item);
          setState(() {});
          notice(added ? tr('Added to Watch later') : tr('Removed from Watch later'));
        }),
      if (controller != null && !item.isUpcoming)
        button(AppIcons.queue, tr('Add to play queue'), () => controller.queueLast(item)),
    ]);
  }
}

/// [builder] given [item] with what its listing left out filled in by
/// [VideoFactsLookup], built again as answers come.
class WithVideoFacts extends StatelessWidget {
  const WithVideoFacts(this.item, {super.key, required this.builder});
  final VideoItem item;
  final Widget Function(BuildContext context, VideoItem item) builder;

  @override
  Widget build(BuildContext context) {
    final lookup = VideoFactsLookup.instance;
    if (!lookup.needs(item)) return builder(context, item);
    return ListenableBuilder(listenable: lookup, builder: (context, _) => builder(context, lookup.of(item)));
  }
}

class DurationBadge extends StatelessWidget {
  const DurationBadge(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final surface = color == null ? skin?.durationBadge : null;
    final text = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(label, style: TextStyle(fontSize: 12, color: surface != null ? skin!.durationText ?? Colors.white : Colors.white, fontWeight: FontWeight.w500, fontFamily: skin?.monoFont, fontFeatures: const [FontFeature.tabularFigures()])),
    );
    if (surface != null) return SkinBox(surface: surface, radius: 4, child: text);
    return DecoratedBox(decoration: BoxDecoration(color: color ?? Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(4)), child: text);
  }
}

/// When a video in the watch history was watched, on a line of its own so
/// that a long channel name never pushes it out.
class WatchedLine extends StatelessWidget {
  const WatchedLine(this.when, {super.key});
  /// "2 hours ago", or the day as YouTube's history names it.
  final String when;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.outline;
    return Row(children: [
      Icon(AppIcons.clockCounterClockwise, size: 12, color: color),
      const SizedBox(width: 4),
      Expanded(child: Text(tr('Watched {0}', [when]), maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: TextStyle(fontSize: 12, color: color))),
    ]);
  }
}

/// The mark on a members-only video, in the green YouTube gives it.
class MembersOnlyBadge extends StatelessWidget {
  const MembersOnlyBadge({super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tr("Only the channel's members can watch this"),
        child: DurationBadge(tr('Members only'), color: const Color(0xFF2BA640)),
      );
}

/// Compact horizontal card for the up-next list on the watch page.
class CompactVideoTile extends StatefulWidget {
  const CompactVideoTile({super.key, required this.item, required this.onOpen, this.thumbnails});
  final VideoItem item;
  final VoidCallback onOpen;
  final Directory? thumbnails;

  @override
  State<CompactVideoTile> createState() => _CompactVideoTileState();
}

class _CompactVideoTileState extends State<CompactVideoTile> {
  VideoItem get item => widget.item;
  VoidCallback get onOpen => widget.onOpen;
  Directory? get thumbnails => widget.thumbnails;

  @override
  void initState() {
    super.initState();
    deArrow.addListener(_branded);
  }

  @override
  void dispose() {
    deArrow.removeListener(_branded);
    super.dispose();
  }

  /// As [VideoCard]: only a tile whose DeArrow branding changed builds again.
  void _branded() {
    if (mounted && _branding != _brandingNow()) setState(() {});
  }

  (String, Uri?) _brandingNow() => (deArrow.titleOf(item.id, item.title), deArrow.thumbnailOf(item.id));
  (String, Uri?)? _branding;

  @override
  Widget build(BuildContext context) => WithVideoFacts(widget.item, builder: _build);

  Widget _build(BuildContext context, VideoItem item) {
    _branding = _brandingNow();
    final colors = context.colors;
    final upcomingStart = item.isUpcoming && item.scheduledStart != null ? tr('Starts {0}', [formatScheduledStart(item.scheduledStart!)]) : null;
    return InkWell(
      borderRadius: AppStyle.cardRadius,
      onTap: onOpen,
      onSecondaryTapUp: (details) => showVideoMenu(context, item, details.globalPosition, onOpen: onOpen),
      onLongPress: () => showVideoMenu(context, item, _centreOf(context), onOpen: onOpen),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 152,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(fit: StackFit.expand, children: [
                  Image(
                    color: context.pictureWarmth,
                    colorBlendMode: BlendMode.multiply,
                    image: thumbnailFor(item, thumbnails, width: 320, size: 'mqdefault'),
                    fit: BoxFit.cover,
                    errorBuilder: (context, _, __) => ColoredBox(color: colors.surfaceContainerHighest),
                  ),
                  if (item.isLive || item.isUpcoming)
                    PositionedDirectional(end: 4, bottom: 4, child: DurationBadge(item.isLive ? tr('Live now') : tr('Upcoming live'), color: item.isLive ? const Color(0xFFCC0000) : null))
                  else if (item.durationLabel.isNotEmpty)
                    PositionedDirectional(end: 4, bottom: 4, child: DurationBadge(item.durationLabel)),
                  if (item.membersOnly) const PositionedDirectional(start: 4, bottom: 4, child: MembersOnlyBadge()),
                  _ProgressBar(item: item),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titleFor(item), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w500, color: colors.onSurface)),
            const SizedBox(height: 4),
            if (upcomingStart != null)
              Text(upcomingStart, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.primary, fontWeight: FontWeight.w500)),
            Text(item.channel.isEmpty ? tr('YouTube') : item.channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.outline)),
            // Views and age, so choosing what to watch next needs no hover.
            if (MetaLine.of(item, style: const TextStyle()).tail case final facts when facts.isNotEmpty)
              Text(facts, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.outline)),
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
  // On a phone the same rows come up from the bottom, a finger's height each.
  final phone = isPhone(context);
  final rows = <SheetChoice<String>>[];
  PopupMenuEntry<String> entry(String value, IconData icon, String label) {
    rows.add((value: value, icon: icon, label: label, selected: false));
    return PopupMenuItem(value: value, child: ListTile(dense: true, leading: Icon(icon), title: Text(label)));
  }

  PopupMenuEntry<String> divider() {
    rows.add((value: null, icon: null, label: null, selected: false));
    return const PopupMenuDivider();
  }

  final items = <PopupMenuEntry<String>>[
      entry('play', AppIcons.playFill, tr('Play')),
      if (library != null) ...[
        entry('favorite', favorite ? AppIcons.heartFill : AppIcons.heart, favorite ? tr('Remove from favorites') : tr('Favorites')),
        entry('later', later ? AppIcons.clockFill : AppIcons.clock, later ? tr('Remove from Watch later') : tr('Watch later')),
        entry('playlist', AppIcons.listPlus, tr('Add to playlist…')),
      ],
      if (controller != null) ...[
        entry('queueNext', AppIcons.playlist, tr('Play next')),
        entry('queueLast', AppIcons.queue, tr('Add to play queue')),
      ],
      if (controller?.account?.signedIn ?? false) entry('youtube', AppIcons.filmReel, tr('Save to YouTube playlist…')),
      if (controller != null) entry('channel', AppIcons.userCircle, tr('View channel')),
      if (controller != null && channel != null) ...[
        if (controller.preferences.isUnrecommended(channel.id))
          entry('recommend', AppIcons.thumbsUp, tr('Recommend this channel again'))
        else
          entry('unrecommend', AppIcons.thumbsDown, tr("Don't recommend this channel")),
        entry('block', AppIcons.prohibitFill, tr('Block this channel')),
      ],
      if (onRemove != null)
        removeLabel == null
            ? entry('remove', AppIcons.minusCircle, tr('Remove from this list'))
            : entry('remove', AppIcons.thumbsDown, removeLabel),
      divider(),
      if (controller?.downloads != null && !item.isLive) entry('download', AppIcons.downloadSimple, tr('Downloads')),
      if (item.isLive && (controller?.downloads?.canRecord ?? false)) entry('download', AppIcons.radioButton, tr('Record the live stream')),
      entry('copy', AppIcons.link, tr('Copy link')),
      entry('browser', AppIcons.arrowSquareOut, tr('Open in browser')),
  ];
  final choice = phone
      ? await pickFromSheet<String>(context, rows, title: item.title)
      : await showMenu<String>(context: context, position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size), items: items);
  if (!context.mounted) return;
  switch (choice) {
    case 'play':
      onOpen();
    case 'favorite':
      final added = library!.toggleFavorite(item);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? tr('Favorited') : tr('Removed from favorites'))));
    case 'later':
      final added = library!.toggleWatchLater(item);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? tr('Added to Watch later') : tr('Removed from Watch later'))));
    case 'queueNext':
      controller!.queueNext(item);
    case 'queueLast':
      controller!.queueLast(item);
    case 'playlist':
      await showAddToPlaylist(context, controller!, item);
    case 'youtube':
      await showSaveToYoutube(context, controller!, item);
    case 'channel':
      await controller!.openChannelOf(item);
    case 'recommend' || 'unrecommend':
      controller!.setRecommendChannel(channel!, choice == 'recommend');
    case 'block':
      controller!.blockChannel(channel!);
    case 'remove':
      onRemove!();
    case 'download':
      await showDownloadChoice(context, controller!, item);
    case 'copy':
      await copyText(context, item.url, tr('Link copied'));
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
      title: Text(tr('Save to YouTube playlist')),
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
                  child: ListTile(dense: true, leading: Icon(AppIcons.playlist), title: Text(playlist.title), subtitle: Text(tr('{0} videos', [playlist.count]))),
                ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, create),
                child: ListTile(dense: true, leading: Icon(AppIcons.plus), title: Text(tr('New private playlist…'))),
              ),
            ]);
          },
        ),
      ],
    ),
  );
  if (!context.mounted || choice == null) return;
  if (choice is RemotePlaylist) return account.saveToPlaylist(item, playlist: choice);
  final title = await promptText(context, title: tr('New YouTube playlist'), hint: tr('Playlist name'), confirm: tr('Create and save'));
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
      title: Text(tr('Add to playlist')),
      children: [
        for (final playlist in library.playlists)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, playlist.id),
            child: ListTile(leading: Icon(AppIcons.playlist), title: Text(playlist.name), subtitle: Text(tr('{0} videos', [playlist.items.length]))),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, create),
          child: ListTile(leading: Icon(AppIcons.plus), title: Text(tr('New playlist'))),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  final playlist = choice == create ? await _createPlaylist(context, controller) : library.playlist(choice);
  if (playlist == null || !context.mounted) return;
  final added = library.addToPlaylist(playlist, item);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? tr('Added to "{0}"', [playlist.name]) : tr('This video is already in "{0}"', [playlist.name]))));
}

Future<LocalPlaylist?> _createPlaylist(BuildContext context, AppController controller) async {
  final name = await promptText(context, title: tr('New playlist'), hint: tr('Playlist name'), confirm: tr('Create'));
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
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, text.text), child: Text(confirm)),
      ],
    ),
  ).whenComplete(text.dispose);
}

/// Where a long press opens a card's menu: its middle.
Offset _centreOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  return box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero));
}

/// A video's channel, then its views and upload date, on one line: a long
/// channel name is shortened first, so the views and date stay in sight.
class MetaLine extends StatelessWidget {
  const MetaLine({super.key, required this.lead, required this.tail, required this.style});

  factory MetaLine.of(VideoItem item, {String? extra, required TextStyle style}) {
    final upcomingStart = item.isUpcoming && item.scheduledStart != null ? tr('Starts {0}', [formatScheduledStart(item.scheduledStart!)]) : null;
    return MetaLine(
      lead: [if (upcomingStart != null) upcomingStart, if (item.channel.isNotEmpty) item.channel].join(' · '),
      tail: [viewsOf(item), ageOf(item), extra].nonNulls.join(' · '),
      style: style,
    );
  }

  /// "1.2K views", or watching for a live.
  static String? viewsOf(VideoItem item) => switch (item.audience) {
        final count? => tr(item.isLive ? '{0} watching' : '{0} views', [formatCount(count)]),
        null => null,
      };

  /// How long ago it was uploaded; none for lives and upcoming ones.
  static String? ageOf(VideoItem item) {
    if (item.isLive || item.isUpcoming) return null;
    if (item.published case final at?) return formatAgo(at);
    return item.age;
  }

  final String lead;
  final String tail;
  final TextStyle style;

  /// What the channel keeps of a line [width] wide: all it needs, up to a
  /// third, however long the rest.
  double _leadRoom(BuildContext context, double width) {
    if (lead.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: lead, style: DefaultTextStyle.of(context).style.merge(style)),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final needed = painter.width.ceilToDouble();
    painter.dispose();
    return needed < width / 3 ? needed : width / 3;
  }

  @override
  Widget build(BuildContext context) {
    if (lead.isEmpty && tail.isEmpty) return Text(tr('YouTube'), maxLines: 1, style: style);
    return LayoutBuilder(
      builder: (context, box) => Row(children: [
        if (lead.isNotEmpty) Flexible(child: Text(lead, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: style)),
        if (tail.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth - _leadRoom(context, box.maxWidth)),
            child: Text(lead.isEmpty ? tail : ' · $tail', maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: style),
          ),
      ]),
    );
  }
}

/// Why a recommended video is on the feed, as a small tag: a word or two,
/// with the full reason when the pointer rests on it.
class ReasonTag extends StatelessWidget {
  const ReasonTag(this.reason, {super.key, this.wide = false});
  final String reason;

  /// Shows the whole reason across the width it is given, not a word for
  /// its kind.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final (kind, text) = FeedReason.read(reason);
    final color = context.skin?.colors.reason ?? context.colors.primary;
    return Tooltip(
      message: text,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? double.infinity : 120),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(4)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            child: Text(wide ? text : kind?.label ?? text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, height: 1.3, fontWeight: FontWeight.w500, color: color)),
          ),
        ),
      ),
    );
  }
}
