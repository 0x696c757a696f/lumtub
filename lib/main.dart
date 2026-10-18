import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'models.dart';
import 'tool_manager.dart';
import 'video_repository.dart';
import 'windows_env.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YtPlusApp());
}

const _bg = Color(0xFF101419);
const _surface = Color(0xFF1B222A);
const _accent = Color(0xFF55D4BA);

class YtPlusApp extends StatelessWidget {
  const YtPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YTPlus',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: ColorScheme.fromSeed(seedColor: _accent, brightness: Brightness.dark, surface: _surface),
        appBarTheme: const AppBarTheme(backgroundColor: _bg, surfaceTintColor: Colors.transparent),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surface,
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: _accent)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        ),
      ),
      home: const HomePage(),
    );
  }
}

enum PageMode { discover, history }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchText = TextEditingController();
  final _history = HistoryStore();
  ToolManager? _tools;
  VideoRepository? _repository;
  Player? _player;
  VideoController? _videoController;
  ToolPaths? _paths;
  List<VideoItem> _results = [];
  VideoItem? _playing;
  PageMode _mode = PageMode.discover;
  bool _ready = false;
  bool _searching = false;
  bool _checking = false;
  String _status = '正在准备 Windows 原生播放器…';
  String? _error;
  int _searchSerial = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _history.initialize();
      final manager = ToolManager((message) {
        if (mounted) setState(() => _status = message);
      });
      _tools = manager;
      await manager.initialize();
      final paths = await manager.ensureReady();
      addToWindowsPath(paths.executableDirectories);
      try {
        MediaKit.ensureInitialized(libmpv: paths.mpv);
      } catch (e) {
        // Incompatible nightly DLL: try the stable copy bundled by media_kit.
        if (mounted) setState(() => _status = '新 DLL 无法加载，尝试随应用提供的备用版本：$e');
        MediaKit.ensureInitialized();
      }
      final player = Player(configuration: const PlayerConfiguration(bufferSize: 16 * 1024 * 1024));
      final controller = VideoController(player, configuration: const VideoControllerConfiguration(hwdec: 'auto-safe'));
      // Ensure mpv's builtin ytdl_hook locates the auto-managed yt-dlp.exe.
      // PATH is also updated above, so that yt-dlp can discover Deno.
      try {
        await player.setProperty('script-opts', 'ytdl_hook-ytdl_path=${paths.ytDlp}');
      } catch (_) {
        // PATH-based discovery is the compatible fallback.
      }
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _paths = paths;
        _repository = VideoRepository(paths.ytDlp);
        _player = player;
        _videoController = controller;
        _ready = true;
        _status = '就绪 · GPU 硬解已启用';
        _error = null;
      });
      // Do not block the UI while checking newer releases.
      unawaited(manager.checkUpdates());
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _status = '初始化失败';
      });
    }
  }

  Future<void> _search([String? value]) async {
    final query = (value ?? _searchText.text).trim();
    if (query.isEmpty || !_ready) return;
    final asUrl = _parseYoutubeId(query);
    if (asUrl != null) {
      await _play(VideoItem(id: asUrl, title: 'YouTube 视频 · $asUrl', channel: 'YouTube', url: 'https://www.youtube.com/watch?v=$asUrl'));
      return;
    }
    final serial = ++_searchSerial;
    _player?.pause();
    setState(() {
      _mode = PageMode.discover;
      _playing = null;
      _searching = true;
      _error = null;
    });
    try {
      final found = await _repository!.search(query);
      if (!mounted || serial != _searchSerial) return;
      setState(() => _results = found);
    } catch (e) {
      if (mounted && serial == _searchSerial) setState(() => _error = '搜索失败：$e');
    } finally {
      if (mounted && serial == _searchSerial) setState(() => _searching = false);
    }
  }

  String? _parseYoutubeId(String input) {
    final url = Uri.tryParse(input);
    if (url == null || !url.hasScheme || url.scheme != 'https') return null;
    if (url.host == 'youtu.be') {
      final id = url.pathSegments.isNotEmpty ? url.pathSegments.first : '';
      return RegExp(r'^[\w-]{11}$').hasMatch(id) ? id : null;
    }
    if (url.host == 'youtube.com' || url.host == 'www.youtube.com' || url.host == 'm.youtube.com') {
      final id = url.queryParameters['v'] ??
          ((url.pathSegments.length >= 2 && (url.pathSegments.first == 'shorts' || url.pathSegments.first == 'live')) ? url.pathSegments[1] : '');
      return RegExp(r'^[\w-]{11}$').hasMatch(id) ? id : null;
    }
    return null;
  }

  Future<void> _play(VideoItem item) async {
    if (_player == null) return;
    setState(() {
      _playing = item;
      _mode = PageMode.discover;
      _error = null;
    });
    try {
      await _player!.open(Media(item.url));
      await _history.record(item);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = '播放失败：$e');
    }
  }

  void _navigate(PageMode target) {
    setState(() {
      _mode = target;
      _playing = null;
      _error = null;
    });
    _player?.pause();
  }

  Future<void> _checkUpdates() async {
    if (_checking || _tools == null) return;
    setState(() => _checking = true);
    try {
      await _tools!.checkUpdates(force: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    ++_searchSerial;
    _searchText.dispose();
    unawaited(_player?.dispose());
    _tools?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 850;
      return Scaffold(
        body: Row(children: [
          if (wide) _sidebar(),
          Expanded(child: Column(children: [
            _topBar(wide),
            Expanded(child: !_ready ? _setupView() : _content()),
            _bottomStatus(),
          ])),
        ]),
        bottomNavigationBar: wide ? null : NavigationBar(
          selectedIndex: _mode == PageMode.discover ? 0 : 1,
          onDestinationSelected: (i) => _navigate(i == 0 ? PageMode.discover : PageMode.history),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.explore_outlined), label: '发现'),
            NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          ],
        ),
      );
    });
  }

  Widget _sidebar() => Container(
        width: 220,
        color: const Color(0xFF151B22),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 32),
            child: Row(children: [
              Container(width: 33, height: 33, decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 25)),
              const SizedBox(width: 10),
              const Text('YTPlus', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            ]),
          ),
          _navItem(Icons.explore_outlined, '发现视频', PageMode.discover),
          _navItem(Icons.history_rounded, '观看历史', PageMode.history),
          const Spacer(),
          const Padding(padding: EdgeInsets.all(12), child: Text('Windows · Flutter + libmpv\n无 Electron · 原生播放', style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.7))),
        ]),
      );

  Widget _navItem(IconData icon, String title, PageMode mode) {
    final active = _mode == mode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        leading: Icon(icon, color: active ? _accent : Colors.white60),
        title: Text(title, style: TextStyle(color: active ? Colors.white : Colors.white70, fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: active ? const Color(0xFF253A38) : null,
        onTap: () => _navigate(mode),
      ),
    );
  }

  Widget _topBar(bool wide) => Padding(
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
              onSubmitted: (_) => _search(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索 YouTube，或粘贴视频链接',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), tooltip: '搜索', onPressed: _ready ? () => _search() : null),
              ),
            ),
          )),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '检查 mpv / yt-dlp 更新',
            onPressed: _ready && !_checking ? _checkUpdates : null,
            icon: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.system_update_alt_rounded),
          ),
        ]),
      );

  Widget _setupView() => Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(_error == null ? Icons.download_for_offline_outlined : Icons.error_outline, size: 54, color: _accent),
            const SizedBox(height: 22),
            Text(_error == null ? '准备播放器组件' : '需要处理一个安装问题', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Text(_error ?? _status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.5)),
            const SizedBox(height: 22),
            if (_error == null) const LinearProgressIndicator(),
            if (_error != null) FilledButton.icon(onPressed: () {setState(() { _error = null; _status = '重新安装组件…'; }); unawaited(_initialize());}, icon: const Icon(Icons.refresh), label: const Text('重试')),
            const SizedBox(height: 12),
            const Text('首次运行需从 GitHub 下载组件；以后可离线启动。', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
        ),
      ));

  Widget _content() {
    if (_playing != null && _videoController != null) return _watchView();
    final list = _mode == PageMode.history ? _history.items : _results;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 18),
        child: Row(children: [
          Text(_mode == PageMode.history ? '观看历史' : '发现视频', style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (list.isNotEmpty) Text('共 ${list.length} 项', style: const TextStyle(color: Colors.white38)),
        ]),
      ),
      if (_searching) const LinearProgressIndicator(minHeight: 2),
      if (_error != null) _errorBanner(),
      Expanded(child: list.isEmpty ? _emptyView() : LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth > 1320 ? 4 : constraints.maxWidth > 930 ? 3 : constraints.maxWidth > 550 ? 2 : 1;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisSpacing: 19, crossAxisSpacing: 19, childAspectRatio: 1.40),
          itemCount: list.length,
          itemBuilder: (context, i) => _videoCard(list[i]),
        );
      })),
    ]);
  }

  Widget _videoCard(VideoItem item) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _play(item),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(fit: StackFit.expand, children: [
              Image.network(item.thumbnail, fit: BoxFit.cover, cacheWidth: 520,
                errorBuilder: (context, _, __) => const ColoredBox(color: _surface, child: Icon(Icons.ondemand_video_outlined, size: 46, color: Colors.white30))),
              if (item.durationLabel.isNotEmpty)
                Positioned(bottom: 8, right: 9, child: DecoratedBox(decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(5)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3), child: Text(item.durationLabel, style: const TextStyle(fontSize: 11))))),
            ]),
          )),
          const SizedBox(height: 9),
          Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 3),
          Text(item.channel.isEmpty ? 'YouTube' : item.channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ]),
      );

  Widget _watchView() {
    final current = _playing!;
    return SingleChildScrollView(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1200),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 8, 26, 36),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextButton.icon(onPressed: () {setState(() => _playing = null); _player?.pause();}, icon: const Icon(Icons.arrow_back), label: const Text('返回列表')),
          const SizedBox(height: 10),
          AspectRatio(aspectRatio: 16 / 9, child: ClipRRect(borderRadius: BorderRadius.circular(15), child: ColoredBox(color: Colors.black, child: Video(controller: _videoController!)))),
          const SizedBox(height: 20),
          Text(current.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22)),
          const SizedBox(height: 8),
          Text(current.channel, style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 17),
          const Text('使用 libmpv 直接播放；播放失败时可以检查右上角的组件更新。', style: TextStyle(color: Colors.white38, fontSize: 12)),
          if (_error != null) _errorBanner(),
        ]),
      ),
    )));
  }

  Widget _emptyView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(_mode == PageMode.history ? Icons.history_rounded : Icons.play_circle_outline_rounded, size: 60, color: Colors.white24),
        const SizedBox(height: 16),
        Text(_mode == PageMode.history ? '还没有观看记录' : '搜索你想看的 YouTube 视频', style: const TextStyle(fontSize: 18, color: Colors.white60)),
        const SizedBox(height: 8),
        if (_mode == PageMode.discover)
          const Text('也可以粘贴 youtube.com 或 youtu.be 链接', style: TextStyle(color: Colors.white38)),
      ]));

  Widget _errorBanner() => Container(
        margin: const EdgeInsets.fromLTRB(28, 0, 28, 12), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFF3F292D), borderRadius: BorderRadius.circular(10)),
        child: Text(_error!, style: const TextStyle(color: Color(0xFFFFBCC2))),
      );

  Widget _bottomStatus() => Container(
        width: double.infinity, height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10))),
        alignment: Alignment.centerLeft,
        child: Text(_ready ? 'libmpv: ${File(_paths!.mpv).parent.path.split(Platform.pathSeparator).lastWhere((part) => part.isNotEmpty)}     ·     ${_status.length > 140 ? '${_status.substring(0, 140)}…' : _status}' : _status,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      );
}
