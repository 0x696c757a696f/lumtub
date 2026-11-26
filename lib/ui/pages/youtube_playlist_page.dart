import 'package:material_ui/material_ui.dart';

import '../../app/app_controller.dart';
import '../common.dart';
import '../playlist_length.dart';
import '../theme.dart';
import '../playlist_order_button.dart';
import '../video_card.dart';
import '../../l10n/l10n.dart';
import '../app_icons.dart';

/// A YouTube playlist's videos, with play-all and a link to YouTube.
class YoutubePlaylistPage extends StatelessWidget {
  const YoutubePlaylistPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final playlist = controller.youtubePlaylist;
    final loader = controller.youtubePlaylistVideos;
    if (playlist == null || loader == null) {
      return StatusView(icon: AppIcons.playlist, title: tr('No playlist open'));
    }
    final listId = 'yt:${playlist.id}';
    final own = controller.visible(loader.items);
    final reversed = controller.isReversed(listId);
    // Last to first needs the whole playlist.
    if (reversed && loader.hasMore) WidgetsBinding.instance.addPostFrameCallback((_) => controller.loadWholeYoutubePlaylist());
    final library = controller.library;
    final view = playlistView((listId, library?.revision, library?.store.finishedVersion), own, reversed: reversed, progressOf: library?.progressOf, partial: loader.hasMore);
    final items = view.items;
    final error = loader.error;
    final colors = context.colors;
    return NearEndListener(
      onNearEnd: loader.loadMore,
      child: CustomScrollView(key: const PageStorageKey('list'), slivers: [
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppStyle.pagePadding - 8, 8, AppStyle.pagePadding, 16),
          child: BackHeading(
            onBack: controller.goBack,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TitleText(playlist.title, maxLines: 2, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700) ?? const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                [if (playlist.channel.isNotEmpty) playlist.channel, if (playlist.count != null) tr('{0} videos', [playlist.count]), tr('YouTube playlists')].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              if (view.length case final length?)
                Text(length, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
            ]),
            buttons: [
              PlaylistOrderButton(controller: controller, id: listId, onReversed: controller.loadWholeYoutubePlaylist),
              FilledButton.icon(
                onPressed: items.isEmpty || (reversed && loader.hasMore) ? null : () => controller.playList(listId, playlist.title, own),
                icon: const Icon(AppIcons.playFill),
                label: Text(tr('Play all')),
              ),
              IconButton(tooltip: tr('Open in browser'), onPressed: () => openExternal(playlist.url), icon: Icon(AppIcons.arrowSquareOut)),
            ],
          ),
        )),
        if (items.isNotEmpty && !(reversed && loader.hasMore)) SliverVideoGrid(items: items, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.playList(listId, playlist.title, own, start: item)),
        if (reversed && loader.hasMore && loader.error == null)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
            child: Text(tr('Reading the whole playlist to show it in reverse ({0} read so far)…', [own.length]), style: TextStyle(color: colors.onSurfaceVariant)),
          )),
        if (loader.loading) ...[
          if (items.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
          SliverSkeletonGrid(rows: items.isEmpty ? 3 : 1),
        ],
        if (error != null)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
            child: ErrorBanner(items.isEmpty ? tr("Couldn't load playlist: {0}", [error]) : tr("Couldn't load more: {0}", [error]), onRetry: () => loader.loadMore(retry: true)),
          )),
        if (items.isEmpty && !loader.loading && error == null)
          SliverFillRemaining(hasScrollBody: false, child: StatusView(icon: AppIcons.musicNotesMinus, title: tr('This playlist is empty'))),
        const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
      ]),
    );
  }
}
