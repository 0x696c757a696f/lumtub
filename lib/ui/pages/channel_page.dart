import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_controller.dart';
import '../../app/library_controller.dart';
import '../../app/posts_loader.dart';
import '../../app/video_list_loader.dart';
import '../../channel_avatar_lookup.dart';
import '../../channel_sort.dart';
import '../../church_wording.dart';
import '../../community_posts.dart';
import '../../device.dart';
import '../../l10n/l10n.dart';
import '../../models.dart';
import '../../thumbnail_cache.dart';
import '../../video_repository.dart';
import '../app_icons.dart';
import '../comments_view.dart';
import '../common.dart';
import '../haptics.dart';
import '../key_scroll.dart';
import '../live_chat_input.dart';
import '../motion.dart';
import '../press_scale.dart';
import '../rating_buttons.dart';
import '../reveal.dart';
import '../sort_menu.dart' show LengthMenu;
import '../theme.dart';
import '../translatable.dart';
import '../video_card.dart';

/// A channel's page: header with follow button, tabs for videos, Shorts,
/// live streams, playlists and posts, and a search inside the channel.
class ChannelPage extends StatefulWidget {
  const ChannelPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  /// Below this width a post's comments open as their own page instead of
  /// beside the posts.
  static const _sideBySide = 960.0;
  static const _panelWidth = 440.0;

  /// The post whose comments are open on the right.
  CommunityPost? _commentsFor;

  AppController get controller => widget.controller;

  void _openComments(CommunityPost post, bool wide) {
    if (wide) {
      setState(() => _commentsFor = _commentsFor?.id == post.id ? null : post);
    } else {
      unawaited(showPostComments(context, controller, post));
    }
  }

  void _closeComments() => setState(() => _commentsFor = null);

  /// The tab already shown goes back to its top; another one opens.
  void _pickTab(BuildContext context, ChannelTab value) {
    if (controller.channelTab == value && controller.channelQuery == null) {
      KeyScroll.toTopAt(context);
    } else {
      Haptics.select();
      controller.setChannelTab(value);
    }
  }

  void _sort(ChannelSort value) {
    if (controller.channelSort != value) Haptics.select();
    controller.setChannelSort(value);
  }

  /// The ids of a page of posts, made once per list (a new list comes with
  /// each page loaded).
  static Set<String> _postIds(List<CommunityPost> posts) => _postIdsOf[posts] ??= {for (final p in posts) p.id};
  static final _postIdsOf = Expando<Set<String>>();

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= _sideBySide;
        final posts = controller.channelPosts;
        // Only while that post is still listed.
        final open = _commentsFor;
        final shown = wide && open != null && posts != null && _postIds(posts.posts).contains(open.id) ? open : null;
        final list = _list(context, wide, shown);
        if (shown == null) return list;
        return CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _closeComments},
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: list),
            const VerticalDivider(width: 1),
            SizedBox(width: _panelWidth, child: PostCommentsPanel(key: ValueKey(shown.id), controller: controller, post: shown, onClose: _closeComments)),
          ]),
        );
      });

  Widget _list(BuildContext context, bool wide, CommunityPost? shown) {
    final channel = controller.channel;
    final loader = controller.channelVideos;
    final posts = controller.channelPosts;
    if (channel == null || (loader == null && posts == null)) {
      return StatusView(icon: AppIcons.userCircle, title: tr('No channel open'));
    }
    final tab = controller.channelTab;
    final searching = controller.channelQuery != null;
    final sortable = !searching && posts == null && (tab == ChannelTab.videos || tab == ChannelTab.shorts || tab == ChannelTab.live);
    return NearEndListener(
      onNearEnd: () {
        loader?.loadMore();
        unawaited(posts?.loadMore());
      },
      child: CustomScrollView(key: const PageStorageKey('list'), slivers: [
        SliverToBoxAdapter(child: ChannelHeader(controller: controller, channel: channel, onBack: controller.goBack)),
        // On a phone the tabs are one row that scrolls sideways and stays
        // at the top while the videos scroll, as phone video apps have it.
        if (isPhone(context) && !searching) ...[
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedRow(
              color: Theme.of(context).colorScheme.surface,
              child: ListView(
                key: const PageStorageKey('channel-tabs'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding, vertical: 8),
                children: [
                  for (final value in ChannelTab.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(label: Text(value.label), selected: tab == value, onSelected: (_) => _pickTab(context, value)),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 4, AppStyle.pagePadding, 12),
            child: _ChannelSearchField(key: ValueKey((channel.id, controller.channelQuery == null)), controller: controller),
          )),
        ] else
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, 16),
          child: Row(children: [
            Expanded(child: searching
                ? Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(tr('Search "{0}"', [controller.channelQuery]), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    // 全部 is YouTube's channel search; the others filter
                    // one tab by title.
                    for (final value in <ChannelTab?>[null, ...ChannelTab.values])
                      ChoiceChip(
                        label: Text(value?.label ?? tr('All')),
                        selected: controller.channelSearchTab == value,
                        onSelected: (_) {
                          Haptics.select();
                          controller.searchChannel(controller.channelQuery!, within: value);
                        },
                      ),
                  ])
                : FilterFlow(children: [
                    for (final value in ChannelTab.values)
                      ChoiceChip(label: Text(value.label), selected: tab == value, onSelected: (_) => _pickTab(context, value)),
                    // A TV keeps the order on the same line, so the videos
                    // start higher.
                    if (Device.tv && sortable) ...[
                      const SizedBox(width: 8),
                      for (final value in ChannelSort.values.where((v) => v.fits(tab)))
                        FilterChip(label: Text(value.label), showCheckmark: false, selected: controller.channelSort == value, onSelected: (_) => _sort(value)),
                      if (tab != ChannelTab.shorts) LengthMenu(value: controller.channelLength, onSelected: controller.setChannelLength),
                    ],
                  ])),
            const SizedBox(width: 12),
            SizedBox(width: math.min(240, MediaQuery.sizeOf(context).width * 0.4), child: _ChannelSearchField(key: ValueKey((channel.id, controller.channelQuery == null)), controller: controller)),
          ]),
        )),
        if (sortable && !Device.tv)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, 16),
            child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final value in ChannelSort.values.where((v) => v.fits(tab)))
                ChoiceChip(label: Text(value.label), selected: controller.channelSort == value, onSelected: (_) => _sort(value)),
              // Every Short is short.
              if (tab != ChannelTab.shorts) LengthMenu(value: controller.channelLength, onSelected: controller.setChannelLength),
            ]),
          )),
        if (posts != null) ..._postSlivers(context, posts, wide, shown) else ..._listingSlivers(context, loader!, tab, searching),
        const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
      ]),
    );
  }

  List<Widget> _listingSlivers(BuildContext context, VideoListLoader loader, ChannelTab tab, bool searching) {
    final items = loader.items;
    final playlists = loader.playlists;
    final error = loader.error;
    final empty = items.isEmpty && playlists.isEmpty;
    return [
      if (playlists.isNotEmpty) ...[
        SliverReveal(key: const ValueKey('playlists'), sliver: SliverPlaylistGrid(items: playlists, onOpen: controller.openYoutubePlaylist)),
        if (items.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
      ],
      if (items.isNotEmpty) SliverReveal(key: const ValueKey('videos'), sliver: SliverVideoGrid(items: items, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: items))),
      if (loader.loading) ...[
        if (!empty) const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
        // An order made here waits for the whole tab: how far it got.
        if (controller.channelLengths case final lengths? when items.isEmpty && !searching && lengths.read.value > 0)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, AppStyle.cardSpacing),
            child: Text(tr('Reading all videos to sort them by length: {0} so far', [lengths.read.value]), style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
          )),
        SliverSkeletonGrid(rows: empty ? 3 : 1),
      ],
      if (error != null)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
          child: ErrorBanner(empty ? tr("Couldn't load: {0}", [error]) : tr("Couldn't load more: {0}", [error]), onRetry: () => loader.loadMore(retry: true)),
        )),
      if (empty && !loader.loading && error == null)
        SliverFillRemaining(hasScrollBody: false, child: searching
            ? StatusView(icon: AppIcons.magnifyingGlassMinus, title: tr('Nothing found in this channel'), message: tr('Try other keywords.'))
            : StatusView(icon: AppIcons.filmReel, title: tr('This channel has no {0}', [tab.label]))),
    ];
  }

  List<Widget> _postSlivers(BuildContext context, PostsLoader loader, bool wide, CommunityPost? shown) {
    final posts = loader.posts;
    final error = loader.error;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, Space.m),
          child: Align(alignment: AlignmentDirectional.centerStart, child: ImmersiveTranslationSwitch(controller: controller)),
        ),
      ),
      SliverReveal(key: ValueKey(posts.isEmpty), sliver: SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
        sliver: SliverList.separated(
          itemCount: posts.length,
          separatorBuilder: (context, i) => const SizedBox(height: AppStyle.cardSpacing),
          itemBuilder: (context, i) => Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: PostCard(
                controller: controller,
                post: posts[i],
                channel: controller.channel!,
                selected: shown?.id == posts[i].id,
                onPlay: (video) => controller.play(video),
                onComments: () => _openComments(posts[i], wide),
              ),
            ),
          ),
        ),
      )),
      if (loader.loading)
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))),
      if (error != null)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
          child: ErrorBanner(posts.isEmpty ? tr("Couldn't load community posts: {0}", [error]) : tr("Couldn't load more: {0}", [error]), onRetry: () => loader.loadMore(retry: true)),
        )),
      if (posts.isEmpty && !loader.loading && error == null)
        SliverFillRemaining(
          hasScrollBody: false,
          child: controller.channelQuery != null
              ? StatusView(icon: AppIcons.magnifyingGlassMinus, title: tr('No community posts found'), message: tr('Only recent posts were searched. Try other keywords.'))
              : StatusView(icon: AppIcons.chats, title: tr('This channel has no community posts yet')),
        ),
    ];
  }
}

/// [post], opened from a pasted link, on a page of its own with its
/// comments under it and a way to its channel.
Future<void> showLinkedPost(BuildContext context, AppController controller, CommunityPost post, ChannelRef channel) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(tr('Post comments')),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                controller.openChannelFromLink(channel);
              },
              child: Text(channel.name.isEmpty ? tr('Open channel') : channel.name),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: CustomScrollView(slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: PostCard(
                      controller: controller,
                      post: post,
                      channel: channel,
                      onPlay: (video) {
                        Navigator.of(context).pop();
                        unawaited(controller.play(video));
                      },
                    ),
                  ),
                ),
                CommentsSection(
                  key: PageStorageKey('post-comments:${post.id}'),
                  controller: controller,
                  postId: post.id,
                  creator: channel,
                  sliver: true,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                ),
              ]),
            ),
          ),
        ),
      ),
    ));

/// The comments under [post] as their own page, for narrow windows.
Future<void> showPostComments(BuildContext context, AppController controller, CommunityPost post) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        body: SafeArea(child: PostCommentsPanel(controller: controller, post: post, onClose: () => Navigator.of(context).pop())),
      ),
    ));

/// A post's comments beside the posts: the post's text, then its
/// comments, scrolling on their own.
class PostCommentsPanel extends StatelessWidget {
  const PostCommentsPanel({super.key, required this.controller, required this.post, required this.onClose});
  final AppController controller;
  final CommunityPost post;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 4),
          child: Row(children: [
            // A tap on the title goes back to the first comment.
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => KeyScroll.toTopAt(context),
              child: Text(tr('Post comments'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            )),
            IconButton(tooltip: tr('Close (Esc)'), icon: Icon(AppIcons.x), onPressed: onClose),
          ]),
        ),
        if (post.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SelectionArea(child: Text(post.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.outline, height: 1.4))),
          ),
        const Divider(height: 1),
        Expanded(
          child: CommentsSection(
            key: PageStorageKey('post-comments:${post.id}'),
            controller: controller,
            postId: post.id,
            creator: controller.channel,
            scrollable: true,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          ),
        ),
      ]);
}

/// One community post: text, images, an attached video or poll, likes.
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.controller, required this.post, required this.channel, required this.onPlay, this.onComments, this.selected = false});
  final AppController controller;
  final CommunityPost post;
  /// Whether its comments are open beside it.
  final bool selected;
  final VoidCallback? onComments;
  final ChannelRef channel;
  final void Function(VideoItem video) onPlay;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final video = post.video;
    return Card(
      shape: selected ? RoundedRectangleBorder(borderRadius: AppStyle.cardRadius, side: BorderSide(color: colors.primary, width: 1.5)) : null,
      child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ChannelAvatar(name: channel.name, radius: 16, image: channel.avatar, channelId: channel.id),
          const SizedBox(width: 8),
          Expanded(child: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(post.published, style: TextStyle(color: colors.outline, fontSize: 12)),
        ]),
        if (post.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Translatable(controller: controller, rite: ChurchWording.riteOf(channel.name) ?? (controller.channel?.id == channel.id ? controller.channelRite : null), text: post.text, builder: (context, text) => SelectableText(text, style: const TextStyle(height: 1.5))),
        ],
        if (post.images.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 240,
            child: ListView.separated(
              key: PageStorageKey('post-images:${post.id}'),
              scrollDirection: Axis.horizontal,
              itemCount: post.images.length,
              separatorBuilder: (context, i) => const SizedBox(width: 8),
              itemBuilder: (context, i) => ClipRRect(
                borderRadius: AppStyle.thumbnailRadius,
                child: Image(
                  color: context.pictureWarmth,
                  colorBlendMode: BlendMode.multiply,
                  image: ResizeImage.resizeIfNeeded(null, (240 * MediaQuery.devicePixelRatioOf(context)).ceil(), CachedThumbnail(post.images[i], null)),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => const SizedBox(width: 240),
                ),
              ),
            ),
          ),
        ],
        if (post.choices.isNotEmpty && controller.channelPosts != null) ...[
          const SizedBox(height: 8),
          _Poll(post: post, loader: controller.channelPosts!),
        ] else if (post.poll.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final choice in post.poll)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(border: Border.all(color: colors.outlineVariant), borderRadius: BorderRadius.circular(8)),
              child: Text(choice),
            ),
        ],
        if (video != null) ...[
          const SizedBox(height: 8),
          CompactVideoTile(item: video, onOpen: () => onPlay(video)),
        ],
        const SizedBox(height: 8),
        Row(children: [
          RatingButtons(
            likes: post.likes,
            state: controller.channelPosts?.ratingOf(post) ?? '',
            loaded: post.rating?.state ?? '',
            onRate: post.rating == null || controller.channelPosts == null ? null : (want) => controller.channelPosts!.rate(post, want),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: TextButton.icon(
              onPressed: onComments,
              icon: Icon(AppIcons.chatCircle, size: 16),
              label: Text(post.comments.isEmpty ? tr('Comments') : post.comments, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ),
          ),
          const Spacer(),
          // A phone has no room for the words: the icon keeps them as its tooltip.
          if (MediaQuery.sizeOf(context).width < 480)
            IconButton(onPressed: () => openExternal(post.url), tooltip: tr('View in browser'), icon: Icon(AppIcons.arrowSquareOut, size: 18))
          else
            TextButton.icon(onPressed: () => openExternal(post.url), icon: Icon(AppIcons.arrowSquareOut, size: 16), label: Text(tr('View in browser'))),
        ]),
      ]),
    ));
  }
}

/// A poll that can be voted in: a choice is voted for by tapping it, and
/// tapped again to take the vote back. The shares show once YouTube gave
/// them, which it does after a vote.
class _Poll extends StatelessWidget {
  const _Poll({required this.post, required this.loader});
  final CommunityPost post;
  final PostsLoader loader;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final voted = loader.voteOf(post);
    Future<void> vote(int index) async {
      final failed = await loader.vote(post, index);
      if (failed != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failed)));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (index, choice) in post.choices.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: voted == index ? colors.primary : colors.outlineVariant, width: voted == index ? 1.5 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => vote(index),
              child: Stack(children: [
                if (voted >= 0 && choice.ratio != null)
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: choice.ratio!.clamp(0.0, 1.0),
                      child: ColoredBox(color: colors.primary.withValues(alpha: 0.12)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    Icon(voted == index ? AppIcons.checkCircleFill : AppIcons.circle, size: 18, color: voted == index ? colors.primary : colors.outline),
                    const SizedBox(width: 8),
                    Expanded(child: Text(choice.text)),
                    if (voted >= 0 && choice.percent.isNotEmpty) Text(choice.percent, style: TextStyle(color: colors.outline, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      if (post.votes.isNotEmpty) Text(post.votes, style: TextStyle(color: colors.outline, fontSize: 12)),
    ]);
  }
}

/// Searches the open channel's videos; clearing it lists the uploads again.
class _ChannelSearchField extends StatefulWidget {
  const _ChannelSearchField({super.key, required this.controller});
  final AppController controller;

  @override
  State<_ChannelSearchField> createState() => _ChannelSearchFieldState();
}

class _ChannelSearchFieldState extends State<_ChannelSearchField> {
  bool get _posts {
    final controller = widget.controller;
    return controller.channelQuery == null ? controller.channelTab == ChannelTab.posts : controller.channelSearchTab == ChannelTab.posts;
  }

  late final _text = TextEditingController(text: widget.controller.channelQuery ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LeavesByKeys(child: TextField(
        controller: _text,
        textInputAction: TextInputAction.search,
        // Typed on the 社区 tab, it searches the posts; otherwise the
        // whole channel, until another chip is picked.
        onSubmitted: (text) => widget.controller.searchChannel(text, within: _posts ? ChannelTab.posts : widget.controller.channelSearchTab),
        decoration: InputDecoration(
          isDense: true,
          hintText: _posts ? tr("Search this channel's posts") : tr('Search videos in this channel'),
          prefixIcon: Icon(AppIcons.magnifyingGlass, size: 20),
          suffixIcon: ListenableBuilder(
            listenable: _text,
            builder: (context, _) => _text.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: tr('Clear'),
                    icon: Icon(AppIcons.x, size: 18),
                    onPressed: () {
                      _text.clear();
                      widget.controller.searchChannel('');
                    },
                  ),
          ),
        ),
      ));
}

/// Channel name, follow button and a link to the channel on YouTube.
class ChannelHeader extends StatelessWidget {
  const ChannelHeader({super.key, required this.controller, required this.channel, this.onBack});
  final AppController controller;
  final ChannelRef channel;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = channel.name.isEmpty ? tr('YouTube channels') : channel.name;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppStyle.pagePadding - 8, 8, AppStyle.pagePadding, 16),
      child: LayoutBuilder(builder: (context, constraints) {
        // On a phone the browser button moves into the menu, the picture
        // shrinks and 关注 goes under the name, so the name keeps the row.
        final grow = textGrowth(context);
        final narrow = constraints.maxWidth < 480 * grow;
        // With large text the name takes a row of its own on a phone.
        final nameAlone = narrow && grow > 1.3;
        Widget nameText(String text) => Text(text, maxLines: nameAlone ? 3 : narrow ? 2 : 1, overflow: TextOverflow.ellipsis, style: (narrow ? context.text.titleLarge : context.text.headlineSmall)?.copyWith(fontWeight: FontWeight.w700));
        final names = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Never translated in lists; here a tap on 翻译 (or 沉浸式翻译)
          // shows the name in the reader's language.
          if (channel.name.isEmpty)
            nameText(name)
          else
            Translatable(controller: controller, rite: controller.channel?.id == channel.id ? controller.channelRite : null, text: name, builder: (context, text) => nameText(text)),
          const SizedBox(height: 2),
          Text(tr('YouTube channels'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.onSurfaceVariant)),
        ]);
        final back = onBack == null ? null : IconButton(tooltip: keyNames(tr('Back (Alt+←)')), onPressed: onBack, icon: Icon(AppIcons.arrowLeft));
        final follow = FollowButton(controller: controller, channel: channel);
        if (narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (back != null) back,
              const SizedBox(width: 4),
              ChannelAvatar(name: name, radius: 22, image: channel.avatar, channelId: channel.id),
              const SizedBox(width: 12),
              if (nameAlone) const Spacer() else Expanded(child: names),
              ChannelMenuButton(controller: controller, channel: channel, browser: true),
            ]),
            if (nameAlone) Padding(padding: const EdgeInsetsDirectional.only(start: 8, top: 8), child: names),
            const SizedBox(height: 8),
            Padding(padding: const EdgeInsetsDirectional.only(start: 8), child: follow),
          ]);
        }
        return Row(children: [
          if (back != null) back,
          const SizedBox(width: 8),
          ChannelAvatar(name: name, radius: 28, image: channel.avatar, channelId: channel.id),
          const SizedBox(width: 16),
          Expanded(child: names),
          const SizedBox(width: 8),
          // A long translation of 关注 is cut short rather than pushing the
          // name out.
          ConstrainedBox(constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.4), child: follow),
          const SizedBox(width: 8),
          IconButton(tooltip: tr('Open in browser'), onPressed: () => openExternal(channel.url), icon: Icon(AppIcons.arrowSquareOut)),
          ChannelMenuButton(controller: controller, channel: channel),
        ]);
      }),
    );
  }
}

/// A round avatar: the channel's picture when a search listed one or it was
/// looked up by [channelId], else the first letter of its name.
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({super.key, required this.name, this.radius = 18, this.image, this.cacheFile, this.channelId});
  final String name;
  final double radius;
  final String? image;
  /// Looks the picture up when [image] is not known.
  final String? channelId;
  /// Where the picture is kept once downloaded, so a long list of
  /// subscriptions does not fetch every picture again on each visit.
  final File? cacheFile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final letter = name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first).toUpperCase();
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: colors.primaryContainer,
      child: Text(letter, style: TextStyle(fontSize: radius * 0.85, fontWeight: FontWeight.w600, color: colors.onPrimaryContainer)),
    );
    final url = image;
    if (url == null) {
      if (channelId == null) return fallback;
      final lookup = ChannelAvatarLookup.instance;
      return ListenableBuilder(
        listenable: lookup,
        builder: (context, _) {
          final found = lookup.of(channelId);
          return found == null ? fallback : ChannelAvatar(name: name, radius: radius, image: found);
        },
      );
    }
    if (channelId != null) ChannelAvatarLookup.instance.remember(channelId!, url);
    final file = cacheFile;
    return ClipOval(child: Image(
      color: context.pictureWarmth,
      colorBlendMode: BlendMode.multiply,
      image: ResizeImage.resizeIfNeeded((radius * 4).round(), null, CachedThumbnail(url, file)),
      width: radius * 2,
      height: radius * 2,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, sync) => fadeInFrame(child, frame, sync),
      errorBuilder: (context, error, stack) => fallback,
    ));
  }
}

/// A channel in search results: avatar, name, subscribers and follow button.
class ChannelResultTile extends StatelessWidget {
  const ChannelResultTile({super.key, required this.controller, required this.result});
  final AppController controller;
  final ChannelResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ref = result.ref;
    final name = ref.name.isEmpty ? tr('YouTube channels') : ref.name;
    final meta = [if (result.handle != null) result.handle!, if (result.subscribers != null) result.subscribers!].join(' · ');
    return PressScale(child: Card(child: InkWell(
      onTap: () => controller.openChannel(ref),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          ChannelAvatar(name: name, radius: 30, image: result.avatar, channelId: ref.id),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (meta.isNotEmpty) Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
            if (result.description.isNotEmpty)
              Text(result.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
          ])),
          const SizedBox(width: 12),
          FollowButton(controller: controller, channel: ChannelRef(ref.id, ref.name, result.avatar ?? ref.avatar)),
        ]),
      ),
    )));
  }
}

/// 屏蔽此频道 and 不推荐此频道, or undoing them, for a channel page or the
/// video playing.
class ChannelMenuButton extends StatelessWidget {
  const ChannelMenuButton({super.key, required this.controller, required this.channel, this.browser = false});
  final AppController controller;
  final ChannelRef channel;
  /// Also offers 在浏览器中打开, for a header with no room for its button.
  final bool browser;

  @override
  Widget build(BuildContext context) {
    final prefs = controller.preferences;
    final blocked = prefs.isBlocked(channel.id);
    final unrecommended = prefs.isUnrecommended(channel.id);
    PopupMenuItem<String> entry(String value, IconData icon, String label) =>
        PopupMenuItem(value: value, child: ListTile(dense: true, leading: Icon(icon), title: Text(label)));
    return PopupMenuButton<String>(
      tooltip: tr('More'),
      icon: Icon(AppIcons.dotsThreeVertical),
      itemBuilder: (context) => [
        if (browser) entry('browser', AppIcons.arrowSquareOut, tr('Open in browser')),
        unrecommended
            ? entry('recommend', AppIcons.thumbsUp, tr('Recommend this channel again'))
            : entry('unrecommend', AppIcons.thumbsDown, tr("Don't recommend this channel")),
        blocked ? entry('unblock', AppIcons.user, tr('Unblock this channel')) : entry('block', AppIcons.prohibitFill, tr('Block this channel')),
        entry('join', AppIcons.medal, tr('Join as a member on YouTube in your browser')),
      ],
      onSelected: (choice) => switch (choice) {
        'browser' => unawaited(openExternal(channel.url)),
        'join' => unawaited(openExternal('${channel.url}/join')),
        'recommend' => controller.setRecommendChannel(channel, true),
        'unrecommend' => controller.setRecommendChannel(channel, false),
        'unblock' => controller.unblockChannel(channel.id),
        _ => controller.blockChannel(channel),
      },
    );
  }
}

class FollowButton extends StatelessWidget {
  const FollowButton({super.key, required this.controller, required this.channel, this.compact = false});
  final AppController controller;
  final ChannelRef channel;
  /// Once followed, a tick without the word, for a phone's row where the
  /// channel's name needs the room.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final library = controller.library;
    if (library == null) return const SizedBox.shrink();
    final following = library.isFollowing(channel.id);
    void toggle() {
      final now = controller.toggleFollow(channel);
      final youtube = (controller.account?.canAct ?? false) && controller.preferences.syncFollowToYoutube;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(now ? (youtube ? tr('Followed and subscribed on YouTube') : tr('Followed. New videos will appear in "Subscriptions"')) : (youtube ? tr('Unfollowed and unsubscribed on YouTube') : tr('Unfollowed')))));
    }

    // The same button either way, so its colour and icon change in place.
    final icon = Swap(child: Icon(following ? AppIcons.check : AppIcons.plus, key: ValueKey(following)));
    final label = Text(following ? tr('Following') : tr('Follow'), maxLines: 1, overflow: TextOverflow.ellipsis);
    if (!following) return FilledButton.icon(onPressed: toggle, icon: icon, label: label);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (compact)
        IconButton.filledTonal(tooltip: tr('Following'), onPressed: toggle, icon: icon)
      else
        Flexible(child: FilledButton.tonalIcon(onPressed: toggle, icon: icon, label: label)),
      const SizedBox(width: 4),
      IconButton.filledTonal(
        tooltip: tr('Subscription groups'),
        icon: Icon(AppIcons.folder),
        onPressed: () => unawaited(showChannelGroups(context, controller, library, channel)),
      ),
    ]);
  }
}

/// Ticks for the subscription groups [channel] is in, and a new group.
Future<void> showChannelGroups(BuildContext context, AppController controller, LibraryController library, ChannelRef channel) => showDialog<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: library,
        builder: (context, _) => PanelDialog(
          title: Text(tr('Subscription groups')),
          content: SizedBox(
            width: dialogWidth(context, 360),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final group in controller.orderedGroups)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: group.channels.contains(channel.id),
                      title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onChanged: (v) => library.setInGroup(group, channel.id, v ?? false),
                    ),
                ]),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(AppIcons.plus),
                title: Text(tr('New group')),
                onTap: () async {
                  final name = await promptText(context, title: tr('New group'), hint: tr('Group name'), confirm: tr('Confirm'));
                  if (name == null || name.trim().isEmpty) return;
                  library.addGroup(name, {channel.id});
                },
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Done')))],
        ),
      ),
    );

/// A row kept at the top of the page while the list under it scrolls.
class _PinnedRow extends SliverPersistentHeaderDelegate {
  const _PinnedRow({required this.child, required this.color});
  final Widget child;
  final Color color;

  static const height = 52.0;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => ColoredBox(color: color, child: child);

  @override
  bool shouldRebuild(_PinnedRow old) => old.child != child || old.color != color;
}
