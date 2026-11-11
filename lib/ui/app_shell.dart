import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../appearance_settings.dart';
import '../downloads/download_models.dart';
import '../native_core.dart';
import 'common.dart';
import '../models.dart';
import '../timestamp_link.dart';
import 'cast_ui.dart';
import 'pages/settings_subpages.dart' show openLogs;
import 'screenshot_action.dart';
import 'pages/account_settings.dart';
import 'pages/channel_page.dart';
import 'pages/downloads_page.dart';
import 'pages/explore_page.dart';
import 'pages/library_pages.dart';
import 'pages/settings_page.dart';
import 'pages/settings_sections.dart';
import 'pages/support_page.dart';
import 'pages/video_pages.dart';
import 'pages/watch_page.dart';
import 'pages/youtube_playlist_page.dart';
import 'lights_off.dart';
import 'mini_player.dart';
import 'pip_view.dart';
import 'theme.dart';
import 'video_card.dart';
import 'window_chrome.dart';
import '../l10n/l10n.dart';
import 'frame_stats.dart';
import 'motion.dart';
import 'player_shortcuts.dart';
import 'app_icons.dart';
import 'skin_chrome.dart';
import 'skin_paint.dart';
import '../skins/skin_library.dart';
import '../skins/skin.dart';
import '../window_frame.dart';
import '../device.dart';

const appName = 'Lumtub';

/// Top bar, navigation rail (bottom bar on narrow windows), page area and
/// status line.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _searchText = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'search');
  StreamSubscription<String>? _notices;
  StreamSubscription<void>? _waylandTop;
  StreamSubscription<DownloadTask>? _finished;
  Timer? _supportCheck;

  AppController get _controller => widget.controller;
  late final _frames = FrameStats.start(() => _controller.onWatchPage ? (_controller.mini ? 'mini player' : 'watch') : _controller.mode.name, causes: () => _controller.rebuildCauses);

  static List<(PageMode, IconData, IconData, String)> get _destinations => [
    (PageMode.home, AppIcons.house, AppIcons.houseFill, tr('Home')),
    (PageMode.explore, AppIcons.compass, AppIcons.compassFill, tr('Explore')),
    (PageMode.subscriptions, AppIcons.stack, AppIcons.stackFill, tr('Subscriptions')),
    (PageMode.history, AppIcons.clockCounterClockwise, AppIcons.clockCounterClockwiseFill, tr('History')),
    (PageMode.playlists, AppIcons.filmReel, AppIcons.filmReelFill, tr('Playlist')),
    (PageMode.downloads, AppIcons.arrowCircleDown, AppIcons.arrowCircleDownFill, tr('Downloads')),
  ];

  /// The bottom bar has room for four: History, Playlists and Downloads share
  /// one Library tab, with a switch at the top of each of those pages.
  static const _library = {PageMode.history, PageMode.playlists, PageMode.downloads};
  static final _bottomDestinations = [
    ..._destinations.where((d) => !_library.contains(d.$1)),
    (PageMode.history, AppIcons.bookOpen, AppIcons.bookOpenFill, tr('Library')),
  ];
  PageMode _lastLibrary = PageMode.history;

  @override
  void initState() {
    super.initState();
    _frames;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) WindowChrome.menus.value = _menus;
    });
    _notices = _controller.notices.listen((message) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
    _waylandTop = _controller.waylandTopNotes.listen((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr("This Wayland desktop doesn't let apps keep a window on top. X11 compatibility mode allows it and needs a restart of Lumtub.")),
        duration: const Duration(seconds: 12),
        showCloseIcon: true,
        // With an action Flutter keeps a snack bar until it is closed.
        persist: false,
        action: SnackBarAction(label: tr('Switch and restart'), onPressed: () => unawaited(_controller.switchToX11())),
      ));
    });
    if (NativeCore.instance == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(NativeCore.missingMessage), duration: const Duration(minutes: 1), showCloseIcon: true));
        }
      });
    }
    _supportCheck = Timer.periodic(const Duration(minutes: 3), (_) => _askForSupport());
    _finished = _controller.finishedDownloads.listen((task) {
      final path = task.filePath;
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Downloaded: {0}', [task.item.title]), maxLines: 2, overflow: TextOverflow.ellipsis),
        duration: const Duration(seconds: 8),
        // With an action Flutter keeps a snack bar until it is closed.
        persist: false,
        action: Platform.isAndroid ? null : SnackBarAction(label: tr('Show in folder'), onPressed: () => unawaited(openInExplorer(path, select: true))),
      ));
    });
  }

  @override
  void dispose() {
    if (WindowChrome.menus.value == _menus) WindowChrome.menus.value = null;
    unawaited(_notices?.cancel());
    unawaited(_waylandTop?.cancel());
    unawaited(_finished?.cancel());
    _supportCheck?.cancel();
    _searchText.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Asks about supporting Lumtub when it is due, and only while nothing
  /// plays and no dialog or other page is open.
  void _askForSupport() {
    final reminder = _controller.supportReminder;
    if (reminder == null || !mounted || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    reminder.used(now);
    if (!reminder.due(now) || _controller.playing != null || ModalRoute.of(context)?.isCurrent == false) return;
    unawaited(askForSupport(context, reminder));
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    _searchText.selection = TextSelection(baseOffset: 0, extentOffset: _searchText.text.length);
  }

  void _submitSearch(String value) {
    if (value.trim().isEmpty) return;
    _searchFocus.unfocus();
    unawaited(_controller.search(value));
  }

  void _select(int index) {
    final target = _destinations[index].$1;
    if (target == PageMode.explore) {
      _controller.openExplore();
    } else {
      _controller.navigate(target);
    }
  }

  SettingsCategory? _takeOpenOn() {
    final category = _openOn;
    _openOn = null;
    return category;
  }

  /// The menus of a skin's menu bar: what the window's buttons and
  /// shortcuts already do, gathered under File, View, Play, Tools and Help.
  /// Play is there only while a video is open. The entries are plain
  /// objects built with the bar, which is rebuilt only when the page, the
  /// video or a setting changes, never with the playing position.
  List<SkinMenu> _menus({required bool appMenu}) {
    final c = _controller;
    final primary = Platform.isMacOS ? (LogicalKeyboardKey key, {bool shift = false}) => SingleActivator(key, meta: true, shift: shift) : (LogicalKeyboardKey key, {bool shift = false}) => SingleActivator(key, control: true, shift: shift);
    final appearance = c.appearance;
    void save(AppearanceSettings next) => unawaited(c.saveAppearance(next));
    final settings = SkinMenuEntry(tr('S&ettings'), () => openSettings(context, c), shortcut: primary(LogicalKeyboardKey.comma));
    final exit = SkinMenuEntry(tr('E&xit'), () => unawaited(WindowFrame.close()), shortcut: appMenu ? primary(LogicalKeyboardKey.keyQ) : null);
    final about = SkinMenuEntry(tr('&About Lumtub'), () => openSettings(context, c, category: SettingsCategory.about));
    final playing = c.playing;
    return [
      if (appMenu) SkinMenu(appName, [about, const SkinMenuEntry.divider(), settings, const SkinMenuEntry.divider(), exit], bold: true),
      SkinMenu(tr('&File'), [
        SkinMenuEntry(tr('&Search or open a link…'), _focusSearch, shortcut: primary(LogicalKeyboardKey.keyK)),
        const SkinMenuEntry.divider(),
        SkinMenuEntry(tr('&Downloads'), () => c.navigate(PageMode.downloads)),
        SkinMenuEntry(tr('History'), () => c.navigate(PageMode.history)),
        SkinMenuEntry(tr('Playlist'), () => c.navigate(PageMode.playlists)),
        const SkinMenuEntry.divider(),
        SkinMenuEntry(tr('&Incognito mode'), () => c.setIncognito(!c.incognito), shortcut: primary(LogicalKeyboardKey.keyN, shift: true), checked: c.incognito),
        if (!appMenu) ...[
          const SkinMenuEntry.divider(),
          settings,
          const SkinMenuEntry.divider(),
          exit,
        ],
      ]),
      SkinMenu(tr('&View'), [
        for (final (i, d) in _destinations.indexed) SkinMenuEntry(d.$4, () => _select(i), checked: _selectedIndex == i && !c.onWatchPage),
        const SkinMenuEntry.divider(),
        SkinMenuEntry(tr('&Back'), _back, shortcut: const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true)),
        const SkinMenuEntry.divider(),
        SkinMenuEntry(tr('&Compact mode'), () => save(appearance.copyWith(compact: !appearance.compact)), checked: appearance.compact),
        SkinMenuEntry(tr('&Status bar'), () => save(appearance.copyWith(showStatusBar: !appearance.showStatusBar)), checked: appearance.showStatusBar),
      ]),
      if (playing != null) SkinMenu(tr('&Play'), _playMenu(playing)),
      SkinMenu(tr('Tools'), [
        SkinMenuEntry(tr('Check for component updates'), c.checking ? null : () => unawaited(c.checkUpdates())),
        SkinMenuEntry(tr('Clear cache'), () => openSettings(context, c, category: SettingsCategory.storage)),
        SkinMenuEntry(tr('Error log'), () => unawaited(openLogs(context, c))),
        const SkinMenuEntry.divider(),
        SkinMenuEntry(tr('&Skins folder'), () {
          final folder = SkinLibrary.instance.folder;
          if (folder != null) unawaited(openInExplorer(folder.path));
        }),
      ]),
      SkinMenu(tr('&Help'), [
        SkinMenuEntry(tr('Keyboard shortcuts'), () => unawaited(showShortcutHelp(context, c.preferences))),
        SkinMenuEntry(tr('How to &make a skin'), () => unawaited(openExternal('https://github.com/0x696c757a696f/lumtub/blob/main/skins/README.md'))),
        SkinMenuEntry(tr('Report a bug or suggest an idea'), () => unawaited(openExternal('https://github.com/0x696c757a696f/lumtub/issues/new/choose'))),
        if (!appMenu) ...[
          const SkinMenuEntry.divider(),
          about,
        ],
      ]),
    ];
  }

  /// What the player and the watch page offer for the video that is open.
  List<SkinMenuEntry> _playMenu(VideoItem item) {
    final c = _controller;
    final player = c.player;
    final library = c.library;
    final danmaku = c.preferences.danmaku;
    return [
      SkinMenuEntry(tr('&Play or pause'), player == null ? null : () => unawaited(player.playOrPause())),
      SkinMenuEntry(tr('P&revious video'), () => unawaited(c.playPrevious())),
      SkinMenuEntry(tr('&Next video'), () => unawaited(c.playNext())),
      const SkinMenuEntry.divider(),
      SkinMenuEntry(tr('&Mute'), player == null ? null : () => unawaited(c.toggleMute())),
      SkinMenuEntry(tr('&Audio only'), () => unawaited(c.toggleAudioOnly())),
      SkinMenuEntry(tr('Picture in p&icture'), () => c.setPip(true)),
      if (c.hasDanmaku) SkinMenuEntry(tr('Bullet chat'), () => unawaited(c.setDanmaku(danmaku.copyWith(enabled: !danmaku.enabled))), checked: danmaku.enabled),
      SkinMenuEntry(tr('Screenshot'), player == null ? null : () => unawaited(captureScreenshot(context, c))),
      const SkinMenuEntry.divider(),
      SkinMenuEntry(tr('Copy link'), () => unawaited(copyText(context, item.url, tr('Link copied')))),
      if (!item.isLive)
        SkinMenuEntry(tr('Copy link at current time'), () {
          final link = timestampLink(item.id, c.player?.state.position ?? Duration.zero);
          unawaited(copyText(context, link ?? item.url, tr('Link copied')));
        }),
      if (library != null) SkinMenuEntry(tr('Watch later'), () => library.toggleWatchLater(item), checked: library.isWatchLater(item.id)),
      if (c.downloads != null && (!item.isLive || c.downloads!.canRecord)) SkinMenuEntry(item.isLive ? tr('Record the live stream') : tr('Downloads'), () => unawaited(showDownloadChoice(context, c, item))),
      SkinMenuEntry(tr('Cast'), () => unawaited(showCastDialog(context, c))),
      if (c.playingChannel case final channel?) SkinMenuEntry(tr('View channel'), () => c.openChannel(channel)),
    ];
  }

  /// Goes back to the previous page or video.
  void _back() {
    if (_controller.canGoBack) _controller.goBack();
  }

  int get _bottomIndex {
    if (_library.contains(_controller.mode)) return _bottomDestinations.length - 1;
    final index = _bottomDestinations.indexWhere((d) => d.$1 == _controller.mode);
    return index < 0 ? 0 : index;
  }

  void _selectBottom(int index) {
    if (index == _bottomDestinations.length - 1) {
      _controller.navigate(_library.contains(_controller.mode) ? _controller.mode : _lastLibrary);
    } else {
      _select(_destinations.indexWhere((d) => d.$1 == _bottomDestinations[index].$1));
    }
  }

  /// History, Playlists and Downloads under the bottom bar's Library tab.
  Widget _libraryTabs(Widget page) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<PageMode>(
            showSelectedIcon: false,
            segments: [
              for (final d in _destinations.where((d) => _library.contains(d.$1)))
                ButtonSegment(value: d.$1, label: Text(d.$4, overflow: TextOverflow.ellipsis)),
            ],
            selected: {_controller.mode},
            onSelectionChanged: (picked) {
              _lastLibrary = picked.first;
              _controller.navigate(picked.first);
            },
          ),
        ),
        Expanded(child: page),
      ]);

  int? get _selectedIndex {
    final index = _destinations.indexWhere((d) => d.$1 == _controller.mode);
    return index < 0 ? null : index;
  }

  bool _tvFocused = false;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          // ⌘ on a Mac where Windows and Linux take Ctrl.
          SingleActivator(LogicalKeyboardKey.keyK, control: !Platform.isMacOS, meta: Platform.isMacOS): _focusSearch,
          SingleActivator(LogicalKeyboardKey.keyN, control: !Platform.isMacOS, meta: Platform.isMacOS, shift: true): () => _controller.setIncognito(!_controller.incognito),
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _back,
          // Esc goes back too, except on the watch page, where it leaves
          // full screen and closes panels.
          const SingleActivator(LogicalKeyboardKey.escape): () {
            final typing = NotWhileTyping.typing;
            if (!typing && !_controller.onWatchPage) _back();
          },
        },
        child: Listener(
          // The mouse "back" button goes back, like Alt+←.
          onPointerDown: (event) {
            if (event.buttons == kBackMouseButton) _back();
          },
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
              _frames.rebuilt();
              if (_controller.ready && !_tvFocused) {
                _tvFocused = true;
                Device.focusFirstOnTv();
              }
              // Picture in picture shows the video alone.
              if (_controller.pip && _controller.playing != null && _controller.videoController != null) {
                return PipView(controller: _controller);
              }
              final wide = constraints.maxWidth >= 720;
              final skin = context.skin;
              final rail = switch (_controller.appearance.navigation) {
                NavigationStyle.auto => wide,
                NavigationStyle.rail => true,
                NavigationStyle.bottom => false,
              };
              final tabs = rail ? null : skin?.tabs;
              Widget tabBar(SkinTabs tabs) => SkinTabBar(
                    tabs: tabs,
                    destinations: [for (final d in _destinations) (d.$2, d.$3, d.$4)],
                    selected: _selectedIndex,
                    onSelected: _select,
                  );
              final scaffold = Scaffold(
                // Below Android's status bar and camera cutout; the
                // navigation bar keeps clear of the gesture bar itself.
                body: SafeArea(bottom: rail, left: rail, right: rail, top: !WindowFrame.supported, child: Column(children: [
                  _TopBar(
                    wide: wide,
                    controller: _controller,
                    searchText: _searchText,
                    searchFocus: _searchFocus,
                    onSubmit: _submitSearch,
                  ),
                  if (tabs != null && tabs.top) tabBar(tabs),
                  Expanded(child: Stack(children: [
                    Row(children: [
                      if (rail && skin != null && skin.drawsRail)
                        SkinRail(
                          skin: skin,
                          destinations: [for (final d in _destinations) (d.$2, d.$3, d.$4)],
                          selected: _selectedIndex,
                          onSelected: _select,
                        )
                      else if (rail)
                        NavigationRail(
                          backgroundColor: context.tones.chrome,
                          selectedIndex: _selectedIndex,
                          labelType: NavigationRailLabelType.all,
                          minWidth: 76,
                          groupAlignment: -1,
                          onDestinationSelected: _select,
                          destinations: [
                            for (final d in _destinations)
                              NavigationRailDestination(icon: Icon(d.$2), selectedIcon: Icon(d.$3), label: Text(d.$4)),
                          ],
                        ),
                      Expanded(child: AnimatedSwitcher(
                        duration: Motion.of(Ease.fade),
                        // Keyed per page so each page's list keeps its scroll position
                        // (PageStorage) when the user comes back to it.
                        child: KeyedSubtree(key: PageStorageKey<String>(_pageKey), child: VideoActions(controller: _controller, child: _veiled(skin, !rail && !_controller.onWatchPage && _library.contains(_controller.mode) ? _libraryTabs(_content()) : _content()))),
                      )),
                    ]),
                    // The video keeps playing over the pages; the watch page
                    // is not mounted meanwhile, so the card has the only Video.
                    if (_controller.mini && _controller.playing != null)
                      Positioned.fill(child: MiniPlayer(controller: _controller)),
                  ])),
                  // No status line on phones, tablets and TVs: the room goes to the page.
                  if (_controller.appearance.showStatusBar && !touchFirst) _StatusBar(controller: _controller),
                ])),
                bottomNavigationBar: rail || (tabs != null && tabs.top) ? null : tabs != null ? tabBar(tabs) : NavigationBar(
                  height: 64,
                  // Six labels do not fit a phone's width side by side.
                  labelBehavior: MediaQuery.sizeOf(context).width < 600 ? NavigationDestinationLabelBehavior.onlyShowSelected : null,
                  selectedIndex: _bottomIndex,
                  onDestinationSelected: _selectBottom,
                  destinations: [
                    for (final d in _bottomDestinations) NavigationDestination(icon: Icon(d.$2), selectedIcon: Icon(d.$3), label: d.$4),
                  ],
                ),
              );
              // 关灯 darkens the whole window but the player, under dialogs
              // and menus, which are routes above the shell.
              final watching = _controller.onWatchPage && !_controller.mini && _controller.videoController != null;
              return ValueListenableBuilder(
                valueListenable: lightsOff,
                builder: (context, off, child) => Stack(fit: StackFit.expand, children: [
                  child!,
                  if (off && watching) Positioned.fill(child: LightsOffLayer(dim: _controller.preferences.lightsOffDim / 100)),
                ]),
                // Android's back button and gesture go back through the
                // pages first; on the first page they leave the app.
                child: WindowFrame.supported
                    ? scaffold
                    : PopScope(
                        canPop: !_controller.canGoBack,
                        onPopInvokedWithResult: (didPop, _) {
                          if (!didPop) _back();
                        },
                        child: scaffold,
                      ),
              );
            }),
          ),
        ),
      );

  /// A skin with a busy picture behind lays some of its page colour over
  /// it under the pages, so what is written on them reads.
  Widget _veiled(Skin? skin, Widget page) {
    if (skin == null || skin.veil == 0 || _controller.appearance.lowResource) return page;
    return ColoredBox(color: skin.colors.page.withValues(alpha: skin.veil * SkinGlass.thinning(skin)), child: page);
  }

  String get _pageKey => !_controller.ready ? 'setup' : _controller.onWatchPage ? 'watch' : switch (_controller.mode) {
        PageMode.channel => 'channel:${_controller.channel?.id}',
        PageMode.playlist => 'playlist:${_controller.openPlaylistId}',
        PageMode.youtubePlaylist => 'yt-playlist:${_controller.youtubePlaylist?.id}',
        PageMode.explore when _controller.query != null => 'search:${_controller.query}',
        final mode => mode.name,
      };

  Widget _content() {
    final controller = _controller;
    if (!controller.ready) return _SetupView(controller: controller);
    if (controller.onWatchPage && controller.videoController != null) return WatchPage(controller: controller);
    return switch (controller.mode) {
      PageMode.home => HomeFeedPage(controller: controller, onFocusSearch: _focusSearch),
      PageMode.explore => controller.query == null ? ExplorePage(controller: controller) : SearchResultsPage(controller: controller, onFocusSearch: _focusSearch),
      PageMode.history => HistoryPage(controller: controller),
      PageMode.subscriptions => SubscriptionsPage(controller: controller),
      PageMode.playlists => PlaylistsPage(controller: controller),
      PageMode.downloads => DownloadsPage(controller: controller),
      PageMode.channel => ChannelPage(controller: controller),
      PageMode.playlist => PlaylistDetailPage(controller: controller),
      PageMode.youtubePlaylist => YoutubePlaylistPage(controller: controller),
      PageMode.settings => SettingsPage(controller: controller, initial: _takeOpenOn() ?? (SmokeCheck.requested ? SettingsCategory.style : SettingsCategory.account)),
    };
  }
}

/// Opens 设置. While a video is open it goes over the watch page, so the
/// video keeps playing and 返回 comes back to it.
/// The section 设置 opens on next, once.
SettingsCategory? _openOn;

void openSettings(BuildContext context, AppController controller, {SettingsCategory? category}) {
  if (!controller.onWatchPage) {
    _openOn = category;
    return controller.navigate(PageMode.settings);
  }
  unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (context) {
      void back() => Navigator.of(context).maybePop();
      return CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): back},
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons == kBackMouseButton) back();
          },
          child: Focus(autofocus: true, child: Scaffold(appBar: SkinAppBar(AppBar(title: Text(tr('Settings')))), body: SettingsPage(controller: controller, initial: category ?? SettingsCategory.account))),
        ),
      );
    },
  )));
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.wide, required this.controller, required this.searchText, required this.searchFocus, required this.onSubmit});
  final bool wide;
  final AppController controller;
  final TextEditingController searchText;
  final FocusNode searchFocus;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ready = controller.ready;
    final skin = context.skin;
    return Container(
      decoration: skin?.topBar != null ? SurfaceDecoration.of(context, skin!.topBar!) : BoxDecoration(color: context.tones.chrome),
      height: AppStyle.topBarHeight,
      child: _onTopBar(
        context,
        skin?.topBar == null ? null : skin?.topBarText,
        Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          InkWell(
            borderRadius: AppStyle.cardRadius,
            onTap: () => controller.navigate(PageMode.home),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: skin != null && skin.hasLogo ? SkinWordmark(skin: skin, name: appName, showName: wide) : Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(8)),
                  child: Icon(AppIcons.playFill, color: colors.onPrimary, size: 22),
                ),
                if (wide) ...[
                  const SizedBox(width: 8),
                  Text(appName, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                ],
              ]),
            ),
          ),
          SizedBox(width: wide ? 16 : 8),
          Expanded(child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SizedBox(height: 40, child: _SearchField(app: controller, controller: searchText, focusNode: searchFocus, enabled: ready, onSubmit: onSubmit)),
          ))),
          SizedBox(width: wide ? 16 : 4),
          IconButton(
            tooltip: keyNames(controller.incognito ? tr('Incognito mode is on; click to turn it off (Ctrl+Shift+N)') : tr("Incognito mode: don't record watching and searching (Ctrl+Shift+N)")),
            isSelected: controller.incognito,
            style: controller.incognito ? IconButton.styleFrom(backgroundColor: colors.tertiaryContainer, foregroundColor: colors.onTertiaryContainer) : null,
            onPressed: () => controller.setIncognito(!controller.incognito),
            icon: Icon(AppIcons.eyeSlash),
            selectedIcon: const Icon(AppIcons.eyeSlashFill),
          ),
          // Phones and TVs have no Deno or libmpv to update.
          if (!touchFirst) IconButton(
            tooltip: tr('Check for component updates'),
            onPressed: ready && !controller.checking ? controller.checkUpdates : null,
            icon: controller.checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(AppIcons.arrowLineDown),
          ),
          IconButton(
            tooltip: tr('Settings'),
            isSelected: controller.mode == PageMode.settings && !controller.onWatchPage,
            onPressed: () => openSettings(context, controller),
            icon: Icon(AppIcons.gear),
            selectedIcon: const Icon(AppIcons.gearFill),
          ),
          AccountButton(account: controller.account, onOpenSettings: () => openSettings(context, controller)),
        ]),
      ),
      ),
    );
  }

  /// [child] with its icon buttons drawn in [color], when a skin gives one.
  static Widget _onTopBar(BuildContext context, Color? color, Widget child) {
    if (color == null) return child;
    final theme = Theme.of(context);
    return IconButtonTheme(
      data: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: color, disabledForegroundColor: color.withValues(alpha: 0.45)).merge(theme.iconButtonTheme.style)),
      child: IconTheme.merge(data: IconThemeData(color: color), child: child),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.app, required this.controller, required this.focusNode, required this.enabled, required this.onSubmit});
  final AppController app;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onSubmit;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

/// A row under the search field: a recent search or YouTube's suggestion.
class _SearchOption {
  const _SearchOption(this.text, {this.recent = false});
  final String text;
  final bool recent;
}

/// The search field, with recent searches when empty and YouTube's
/// suggestions while typing. Enter searches for what is typed unless a row
/// was picked with the arrow keys.
class _SearchFieldState extends State<_SearchField> {
  bool _picking = false;
  double _width = 640;

  @override
  void initState() {
    super.initState();
    widget.focusNode
      ..onKeyEvent = _onKey
      ..addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode
      ..onKeyEvent = null
      ..removeListener(_onFocus);
    super.dispose();
  }

  /// The first arrow key only marks the first row; later ones move.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent || (key != LogicalKeyboardKey.arrowDown && key != LogicalKeyboardKey.arrowUp)) return KeyEventResult.ignored;
    if (_picking) return KeyEventResult.ignored;
    setState(() => _picking = true);
    return key == LogicalKeyboardKey.arrowDown ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _onFocus() {
    if (widget.focusNode.hasFocus) {
      _refresh();
    } else if (_picking) {
      setState(() => _picking = false);
    }
  }

  /// Builds the rows again for the same text; they otherwise only change
  /// when the text does.
  void _refresh() {
    final value = widget.controller.value;
    widget.controller.value = value.copyWith(text: '${value.text} ');
    widget.controller.value = value;
  }

  Future<List<String>> _recent() async =>
      widget.app.preferences.recordHistory ? await widget.app.searchHistory?.items() ?? const [] : const [];

  Future<Iterable<_SearchOption>> _options(TextEditingValue value) async {
    final text = value.text.trim();
    if (text.isEmpty) return [for (final q in (await _recent()).take(10)) _SearchOption(q, recent: true)];
    final lower = text.toLowerCase();
    final recent = [for (final q in await _recent()) if (q.toLowerCase().startsWith(lower) && q != text) q].take(3).toList();
    // Wait for typing to pause before asking YouTube.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (widget.controller.text.trim() != text) return const [];
    final suggested = await widget.app.searchSuggestions.forQuery(text);
    return [
      for (final q in recent) _SearchOption(q, recent: true),
      for (final q in suggested)
        if (!recent.contains(q)) _SearchOption(q),
    ].take(12);
  }

  Future<void> _remove(String query) async {
    await widget.app.searchHistory?.remove(query);
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        _width = constraints.maxWidth;
        return CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): widget.focusNode.unfocus},
          child: RawAutocomplete<_SearchOption>(
            textEditingController: widget.controller,
            focusNode: widget.focusNode,
            displayStringForOption: (option) => option.text,
            optionsBuilder: _options,
            onSelected: (option) => widget.onSubmit(option.text),
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) => TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: widget.enabled,
              onSubmitted: (text) {
                if (_picking) {
                  _picking = false;
                  onFieldSubmitted();
                } else {
                  widget.onSubmit(text);
                }
              },
              onChanged: (_) => setState(() => _picking = false),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                // A phone's box is too narrow for the whole sentence.
                hintText: touchFirst && MediaQuery.sizeOf(context).width < 600 ? tr('Search') : tr('Search YouTube, or paste a video link'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                prefixIcon: Icon(AppIcons.magnifyingGlass),
                suffixIcon: controller.text.isEmpty && touchFirst
                    ? null
                    : controller.text.isEmpty
                    ? Padding(
                        padding: const EdgeInsetsDirectional.only(end: 12),
                        child: Center(widthFactor: 1, child: Text(keyNames('Ctrl+K'), style: TextStyle(fontSize: 12, color: context.colors.outline))),
                      )
                    : IconButton(
                        tooltip: tr('Clear'),
                        icon: Icon(AppIcons.x, size: 20),
                        onPressed: () {
                          controller.clear();
                          setState(() {});
                          focusNode.requestFocus();
                        },
                      ),
              ),
            ),
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: AlignmentDirectional.topStart,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Material(
                  elevation: 4,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  shape: RoundedRectangleBorder(borderRadius: AppStyle.cardRadius, side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: _width, minWidth: _width, maxHeight: 420),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, i) {
                        final option = options.elementAt(i);
                        final highlighted = _picking && AutocompleteHighlightedOption.of(context) == i;
                        return ListTile(
                          dense: true,
                          selected: highlighted,
                          selectedTileColor: context.colors.surfaceContainerHighest,
                          leading: Icon(option.recent ? AppIcons.clockCounterClockwiseFill : AppIcons.magnifyingGlass, size: 20),
                          title: Text(option.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: option.recent
                              ? IconButton(tooltip: tr('Delete this entry'), icon: Icon(AppIcons.x, size: 18), onPressed: () => _remove(option.text))
                              : null,
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      });
}

class _SetupView extends StatelessWidget {
  const _SetupView({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.error;
    if (error != null) {
      return StatusView(
        icon: AppIcons.warningCircle,
        error: true,
        title: tr('Component installation ran into a problem'),
        message: error,
        action: FilledButton.icon(onPressed: controller.retryInitialize, icon: Icon(AppIcons.arrowsClockwise), label: Text(tr('Retry'))),
      );
    }
    return StatusView(
      icon: AppIcons.arrowCircleDown,
      title: tr('Preparing player components'),
      message: tr('{0}\nThe first run downloads components from GitHub; after that Lumtub can start offline.', [controller.status]),
      action: const SizedBox(width: 240, child: LinearProgressIndicator()),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final paths = controller.paths;
    final text = controller.ready && paths != null
        ? '${controller.tools?.libmpvLabel ?? 'libmpv'}  ·  $status'
        : status;
    return Container(
      width: double.infinity,
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: switch (context.skin?.statusBar) {
        final surface? => SurfaceDecoration.of(context, surface),
        null => BoxDecoration(color: context.tones.chrome, border: Border(top: BorderSide(color: context.colors.outlineVariant.withValues(alpha: 0.4)))),
      },
      alignment: AlignmentDirectional.centerStart,
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.skin?.statusBarText ?? context.colors.outline, fontSize: 12, fontFamily: context.skin?.monoFont)),
    );
  }
}
