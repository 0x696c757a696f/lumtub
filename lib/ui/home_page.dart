import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'video_list_view.dart';
import 'watch_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = AppController();
  final _searchText = TextEditingController();
  StreamSubscription<String>? _notices;

  @override
  void initState() {
    super.initState();
    _notices = _controller.notices.listen((message) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    unawaited(_notices?.cancel());
    _searchText.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 850;
          return Scaffold(
            body: Row(children: [
              if (wide) _Sidebar(mode: _controller.mode, onNavigate: _controller.navigate),
              Expanded(child: Column(children: [
                _topBar(wide),
                Expanded(child: !_controller.ready ? _SetupView(controller: _controller) : _content()),
                _StatusBar(controller: _controller),
              ])),
            ]),
            bottomNavigationBar: wide ? null : NavigationBar(
              selectedIndex: _mobileNavigationIndex,
              onDestinationSelected: (i) => _controller.navigate(switch (i) {
                0 => PageMode.home,
                1 => PageMode.explore,
                2 => PageMode.history,
                _ => PageMode.settings,
              }),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
                NavigationDestination(icon: Icon(Icons.explore_outlined), label: '探索'),
                NavigationDestination(icon: Icon(Icons.history), label: '历史'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
              ],
            ),
          );
        }),
      );

  Widget _content() {
    final controller = _controller;
    if (controller.playing != null && controller.videoController != null) return WatchView(controller: controller);
    return switch (controller.mode) {
      PageMode.settings => SettingsPage(controller: controller),
      PageMode.subscriptions => const PlannedView(subscriptions: true),
      PageMode.playlists => const PlannedView(subscriptions: false),
      _ => VideoListView(controller: controller),
    };
  }

  int get _mobileNavigationIndex => switch (_controller.mode) {
        PageMode.home => 0,
        PageMode.explore => 1,
        PageMode.history => 2,
        _ => 3,
      };

  Widget _topBar(bool wide) {
    final ready = _controller.ready;
    final checking = _controller.checking;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
      child: Row(children: [
        if (!wide) ...[
          const Text('YTPlus', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
        ],
        Expanded(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: TextField(
            controller: _searchText,
            onSubmitted: _controller.search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索 YouTube，或粘贴视频链接',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), tooltip: '搜索', onPressed: ready ? () => _controller.search(_searchText.text) : null),
            ),
          ),
        )),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '检查 yt-dlp / Deno 更新',
          onPressed: ready && !checking ? _controller.checkUpdates : null,
          icon: checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.system_update_alt_rounded),
        ),
        const IconButton(
          tooltip: '账户（即将推出）',
          onPressed: null,
          icon: Icon(Icons.account_circle_outlined),
        ),
      ]),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.mode, required this.onNavigate});
  final PageMode mode;
  final ValueChanged<PageMode> onNavigate;

  // A Material (not a coloured Container) so the active tile colour and ink
  // splashes paint above the sidebar background.
  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.sidebar,
        child: Container(
          width: 220,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 32),
              child: Row(children: [
                Container(width: 33, height: 33, decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 25)),
                const SizedBox(width: 10),
                const Flexible(child: Text('YTPlus', maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold))),
              ]),
            ),
            _item(Icons.home_outlined, '首页', PageMode.home),
            _item(Icons.explore_outlined, '探索', PageMode.explore),
            _item(Icons.subscriptions_outlined, '订阅', PageMode.subscriptions),
            _item(Icons.history_rounded, '观看历史', PageMode.history),
            _item(Icons.queue_music_outlined, '播放列表', PageMode.playlists),
            const Spacer(),
            _item(Icons.settings_outlined, '设置', PageMode.settings),
            const Padding(padding: EdgeInsets.all(12), child: Text('Windows · Flutter + libmpv\n无 Electron · 原生播放', style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.7))),
          ]),
        ),
      );

  Widget _item(IconData icon, String title, PageMode target) {
    final active = mode == target;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        leading: Icon(icon, color: active ? AppColors.accent : Colors.white60),
        title: Text(title, style: TextStyle(color: active ? Colors.white : Colors.white70, fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: active ? AppColors.activeNav : null,
        onTap: () => onNavigate(target),
      ),
    );
  }
}

class _SetupView extends StatelessWidget {
  const _SetupView({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.error;
    return Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(error == null ? Icons.download_for_offline_outlined : Icons.error_outline, size: 54, color: AppColors.accent),
          const SizedBox(height: 22),
          Text(error == null ? '准备播放器组件' : '需要处理一个安装问题', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Text(error ?? controller.status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.5)),
          const SizedBox(height: 22),
          if (error == null) const LinearProgressIndicator(),
          if (error != null) FilledButton.icon(onPressed: controller.retryInitialize, icon: const Icon(Icons.refresh), label: const Text('重试')),
          const SizedBox(height: 12),
          const Text('首次运行需从 GitHub 下载组件；以后可离线启动。', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ]),
      ),
    ));
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
        ? 'libmpv: ${File(paths.mpv).parent.path.split(Platform.pathSeparator).lastWhere((part) => part.isNotEmpty)}     ·     ${status.length > 140 ? '${status.substring(0, 140)}…' : status}'
        : status;
    return Container(
      width: double.infinity,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10))),
      alignment: Alignment.centerLeft,
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 11)),
    );
  }
}
