import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'app_directories.dart';
import 'cache_manager.dart';
import 'models.dart';
import 'player_option_applicator.dart';
import 'player_settings.dart';
import 'tool_manager.dart';
import 'video_repository.dart';
import 'windows_env.dart';
import 'windows_video_info.dart';

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

enum PageMode { home, explore, subscriptions, history, playlists, settings }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchText = TextEditingController();
  HistoryStore? _history;
  AppDirectories? _directories;
  CacheManager? _cacheManager;
  int _cacheBytes = 0;
  final Map<String, String> _decodeStates = {'h264': '尚未验证', 'vp9': '尚未验证', 'av1': '尚未验证'};
  String _currentCodec = '尚未播放视频';
  String _currentHwdec = '尚未验证';
  WindowsVideoInfo _windowsVideoInfo = const WindowsVideoInfo();
  PlayerSettingsStore? _settingsStore;
  PlayerSettings _settings = const PlayerSettings();
  ToolManager? _tools;
  VideoRepository? _repository;
  Player? _player;
  VideoController? _videoController;
  ToolPaths? _paths;
  List<VideoItem> _results = [];
  VideoItem? _playing;
  PageMode _mode = PageMode.home;
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
      final directories = await AppDirectories.create();
      final history = HistoryStore(directories);
      await history.initialize();
      final settingsStore = PlayerSettingsStore(directories);
      final settings = await settingsStore.load();
      final cacheManager = CacheManager(directories);
      await cacheManager.prepare(settings);
      final cacheBytes = await cacheManager.size(settings);
      final manager = ToolManager(directories, (message) {
        if (mounted) setState(() => _status = message);
      });
      _tools = manager;
      await manager.initialize();
      final paths = await manager.ensureReady();
      addToWindowsPath(paths.executableDirectories);
      MediaKit.ensureInitialized(libmpv: paths.mpv);
      final player = Player(configuration: PlayerConfiguration(bufferSize: settings.cacheMemoryMb * 1024 * 1024));
      final controller = VideoController(player, configuration: VideoControllerConfiguration(hwdec: settings.hwdec));
      final ignoredOptions = await PlayerOptionApplicator.apply(player, settings);
      // yt-dlp and Deno are on PATH before libmpv starts, so ytdl_hook can find them.
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _paths = paths;
        _directories = directories;
        _cacheManager = cacheManager;
        _cacheBytes = cacheBytes;
        _settingsStore = settingsStore;
        _settings = settings;
        _history = history;
        _repository = VideoRepository(paths.ytDlp, cacheDirectory: '${cacheManager.rootFor(settings).path}${Platform.pathSeparator}yt-dlp');
        _player = player;
        _videoController = controller;
        _ready = true;
        _status = ignoredOptions.isEmpty ? '就绪 · 解码方式将在播放时验证' : '就绪 · 已忽略不支持的设置：${ignoredOptions.join(', ')}';
        _error = null;
      });
      // Do not block the UI while checking newer releases.
      unawaited(manager.checkUpdates());
      unawaited(_readWindowsVideoInfo());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _status = '初始化失败';
        });
      }
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
      _mode = PageMode.explore;
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
      _mode = PageMode.explore;
      _error = null;
    });
    try {
      await _player!.open(Media(item.url));
      await _history?.record(item);
      unawaited(_inspectCurrentDecoder());
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

  Future<void> _saveSettings(PlayerSettings settings) async {
    final store = _settingsStore;
    final player = _player;
    if (store == null || player == null) return;
    final oldSettings = _settings;
    final requiresNextVideo = settings.hwdec != oldSettings.hwdec || settings.interpolation != oldSettings.interpolation;
    final ignoredOptions = await PlayerOptionApplicator.apply(player, settings);
    await store.save(settings);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      if (_paths != null && settings.cachePath != oldSettings.cachePath) {
        _repository = VideoRepository(_paths!.ytDlp, cacheDirectory: '${(_cacheManager?.rootFor(settings).path ?? '')}${Platform.pathSeparator}yt-dlp');
      }
      _status = ignoredOptions.isEmpty
          ? '播放器设置已保存${requiresNextVideo ? '；硬件解码和帧插值在下一段视频生效。' : '。'}'
          : '已保存；此 libmpv 不支持：${ignoredOptions.join(', ')}。';
    });
  }

  Future<void> _inspectCurrentDecoder() async {
    final platform = _player?.platform;
    if (platform is! NativePlayer) {
      _notice('当前播放器无法读取 libmpv 解码状态。');
      return;
    }
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      final codec = (await platform.getProperty('video-codec')).trim().toLowerCase();
      final hwdec = (await platform.getProperty('hwdec-current')).trim();
      if (!mounted) return;
      final normalized = codec.contains('av1') ? 'av1' : codec.contains('vp9') ? 'vp9' : codec.contains('h264') || codec.contains('avc') ? 'h264' : null;
      setState(() {
        _currentCodec = codec.isEmpty ? '尚未验证' : codec;
        _currentHwdec = hwdec.isEmpty || hwdec == 'no' || hwdec == 'none' ? '软件解码已验证' : hwdec;
        if (normalized != null) _decodeStates[normalized] = _currentHwdec;
      });
    } catch (_) {
      if (mounted) setState(() => _currentHwdec = '尚未验证');
    }
  }

  Future<void> _readWindowsVideoInfo() async {
    final info = await WindowsVideoInfo.read();
    if (mounted) setState(() => _windowsVideoInfo = info);
  }

  Future<void> _openStore(String url) async {
    try {
      await Process.start('explorer.exe', [url]);
    } catch (_) {
      _notice('无法打开 Microsoft Store 链接。');
    }
  }

  Future<void> _changeCacheLocation() async {
    final directories = _directories;
    final manager = _cacheManager;
    if (directories == null || manager == null) return;
    if (_playing != null) {
      _notice('请先返回列表并停止当前视频，再迁移缓存。');
      return;
    }
    final selected = await getDirectoryPath(initialDirectory: manager.rootFor(_settings).path);
    if (selected == null) return;
    final target = Directory('$selected${Platform.pathSeparator}YTPlusCache');
    final next = _settings.copyWith(cachePath: target.path);
    try {
      await manager.prepare(next);
      if (!mounted) return;
      final migrate = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('迁移现有缓存？'),
        content: Text('新位置：${target.path}\n\n只迁移 YTPlus 创建的缩略图、临时文件、yt-dlp 和 mpv 缓存目录。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('不迁移')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('迁移')),
        ],
      ));
      if (migrate == true) await manager.migrate(_settings, next);
      await _saveSettings(next);
      if (!mounted) return;
      setState(() => _cacheBytes = 0);
      _notice('缓存位置已保存。yt-dlp 缓存在下一次搜索时使用新位置。');
    } on FileSystemException catch (error) {
      _notice('新缓存位置不可用，继续使用原位置：${error.message}');
    }
  }

  Future<void> _clearCache() async {
    final manager = _cacheManager;
    if (manager == null) return;
    if (_playing != null) {
      _notice('正在播放时不会清理缓存。请先返回列表。');
      return;
    }
    await manager.clear(_settings);
    if (!mounted) return;
    setState(() => _cacheBytes = 0);
    _notice('已清理 YTPlus 管理的缓存文件。');
  }

  void _notice(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

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
          selectedIndex: _mobileNavigationIndex,
          onDestinationSelected: (i) => _navigate(switch (i) {
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
          _navItem(Icons.home_outlined, '首页', PageMode.home),
          _navItem(Icons.explore_outlined, '探索', PageMode.explore),
          _navItem(Icons.subscriptions_outlined, '订阅', PageMode.subscriptions),
          _navItem(Icons.history_rounded, '观看历史', PageMode.history),
          _navItem(Icons.queue_music_outlined, '播放列表', PageMode.playlists),
          const Spacer(),
          _navItem(Icons.settings_outlined, '设置', PageMode.settings),
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
            tooltip: '检查 yt-dlp / Deno 更新',
            onPressed: _ready && !_checking ? _checkUpdates : null,
            icon: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.system_update_alt_rounded),
          ),
          IconButton(
            tooltip: '账户（即将推出）',
            onPressed: null,
            icon: const Icon(Icons.account_circle_outlined),
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
    if (_mode == PageMode.settings) return _settingsView();
    if (_mode == PageMode.subscriptions || _mode == PageMode.playlists) return _plannedView();
    final list = _mode == PageMode.history ? _history?.items ?? const <VideoItem>[] : _results;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 18),
        child: Row(children: [
          Text(_pageTitle, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
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
          const SizedBox(height: 8),
          _playbackControls(),
          const SizedBox(height: 8),
          _trackSelectors(),
          const SizedBox(height: 20),
          Text(current.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22)),
          const SizedBox(height: 8),
          Text(current.channel, style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 17),
          const Text('使用 libmpv 直接播放；播放异常时可以检查 yt-dlp / Deno 更新。', style: TextStyle(color: Colors.white38, fontSize: 12)),
          if (_error != null) _errorBanner(),
        ]),
      ),
    )));
  }

  Widget _playbackControls() {
    final player = _player!;
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? player.state.position;
        final duration = player.state.duration;
        final maximum = duration.inMilliseconds <= 0 ? 1.0 : duration.inMilliseconds.toDouble();
        final value = position.inMilliseconds.clamp(0, maximum.toInt()).toDouble();
        return Card(
          color: _surface,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Column(children: [
              Slider(
                value: value,
                max: maximum,
                onChanged: duration.inMilliseconds <= 0 ? null : (milliseconds) => player.seek(Duration(milliseconds: milliseconds.round())),
              ),
              Row(children: [
                StreamBuilder<bool>(
                  stream: player.stream.playing,
                  builder: (context, playing) => IconButton(
                    tooltip: playing.data == true ? '暂停' : '播放',
                    icon: Icon(playing.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    onPressed: () => playing.data == true ? player.pause() : player.play(),
                  ),
                ),
                IconButton(tooltip: '快退 5 秒', icon: const Icon(Icons.replay_5_rounded), onPressed: () => player.seek(position - const Duration(seconds: 5))),
                IconButton(tooltip: '快进 5 秒', icon: const Icon(Icons.forward_5_rounded), onPressed: () => player.seek(position + const Duration(seconds: 5))),
                Text('${_timeLabel(position)} / ${_timeLabel(duration)}', style: const TextStyle(color: Colors.white60)),
                const Spacer(),
                PopupMenuButton<double>(
                  tooltip: '播放速度',
                  initialValue: player.state.rate,
                  onSelected: player.setRate,
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 0.5, child: Text('0.5×')),
                    PopupMenuItem(value: 0.75, child: Text('0.75×')),
                    PopupMenuItem(value: 1.0, child: Text('正常速度')),
                    PopupMenuItem(value: 1.25, child: Text('1.25×')),
                    PopupMenuItem(value: 1.5, child: Text('1.5×')),
                    PopupMenuItem(value: 2.0, child: Text('2×')),
                  ],
                  child: const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.speed_rounded)),
                ),
                IconButton(
                  tooltip: player.state.volume == 0 ? '取消静音' : '静音',
                  icon: Icon(player.state.volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                  onPressed: () => player.setVolume(player.state.volume == 0 ? 100 : 0),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Widget _trackSelectors() {
    final player = _player!;
    return StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? player.state.tracks;
        final selected = player.state.track;
        final audio = [...tracks.audio];
        final subtitles = [...tracks.subtitle];
        if (!audio.contains(selected.audio)) audio.insert(0, selected.audio);
        if (!subtitles.contains(selected.subtitle)) subtitles.insert(0, selected.subtitle);
        return Card(
          color: _surface,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: LayoutBuilder(builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final audioMenu = DropdownButton<AudioTrack>(
                value: selected.audio,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: audio.map((track) => DropdownMenuItem(value: track, child: Text(_trackLabel(track.id, track.title, track.language), overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (track) { if (track != null) player.setAudioTrack(track); },
              );
              final subtitleMenu = DropdownButton<SubtitleTrack>(
                value: selected.subtitle,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: subtitles.map((track) => DropdownMenuItem(value: track, child: Text(_trackLabel(track.id, track.title, track.language), overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (track) { if (track != null) player.setSubtitleTrack(track); },
              );
              final children = [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('音轨', style: TextStyle(fontSize: 12, color: Colors.white54)), audioMenu])),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('字幕', style: TextStyle(fontSize: 12, color: Colors.white54)), subtitleMenu])),
              ];
              return compact ? Column(children: children) : Row(children: [children.first, const SizedBox(width: 18), children.last]);
            }),
          ),
        );
      },
    );
  }

  String _trackLabel(String id, String? title, String? language) {
    if (id == 'auto') return '自动';
    if (id == 'no') return '关闭';
    final parts = [if (title != null && title.isNotEmpty) title, if (language != null && language.isNotEmpty) language];
    return parts.isEmpty ? '轨道 $id' : parts.join(' · ');
  }

  String _timeLabel(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '${value.inMinutes}:$seconds';
  }

  Widget _emptyView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(_mode == PageMode.history ? Icons.history_rounded : Icons.play_circle_outline_rounded, size: 60, color: Colors.white24),
        const SizedBox(height: 16),
          Text(_mode == PageMode.history ? '还没有观看记录' : '搜索你想看的 YouTube 视频', style: const TextStyle(fontSize: 18, color: Colors.white60)),
        const SizedBox(height: 8),
        if (_mode != PageMode.history)
          const Text('也可以粘贴 youtube.com 或 youtu.be 链接', style: TextStyle(color: Colors.white38)),
      ]));

  int get _mobileNavigationIndex => switch (_mode) {
        PageMode.home => 0,
        PageMode.explore => 1,
        PageMode.history => 2,
        _ => 3,
      };

  String get _pageTitle => switch (_mode) {
        PageMode.home => '首页',
        PageMode.explore => '探索视频',
        PageMode.history => '观看历史',
        _ => '',
      };

  Widget _plannedView() {
    final subscriptions = _mode == PageMode.subscriptions;
    return Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(subscriptions ? Icons.subscriptions_outlined : Icons.queue_music_outlined, size: 58, color: Colors.white24),
          const SizedBox(height: 16),
          Text(subscriptions ? '订阅会保存在本机' : '播放列表会保存在本机', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('这个区域已预留在界面中，等本地订阅和播放列表功能完成后显示内容。', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, height: 1.5)),
        ]),
      ),
    ));
  }

  Widget _settingsView() {
    final directories = _directories;
    return ListView(padding: const EdgeInsets.fromLTRB(28, 12, 28, 28), children: [
      const Text('设置', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
      const SizedBox(height: 20),
      const Text('播放与性能', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      _preferenceCard(Column(children: [
        _choice('硬件解码', _settings.hwdec, const {'auto-safe': '自动（推荐）', 'd3d11va': 'D3D11VA', 'no': '软件解码'}, (value) => _saveSettings(_settings.copyWith(hwdec: value))),
        const Divider(height: 1),
        _choice('视频缩放算法', _settings.scale, const {'spline36': '默认', 'bilinear': 'Bilinear', 'lanczos': 'Lanczos'}, (value) => _saveSettings(_settings.copyWith(scale: value))),
        SwitchListTile.adaptive(contentPadding: const EdgeInsets.symmetric(horizontal: 18), title: const Text('色带消除'), subtitle: const Text('降低渐变中的色带，可能略增 GPU 负载。'), value: _settings.deband, onChanged: (value) => _saveSettings(_settings.copyWith(deband: value))),
        SwitchListTile.adaptive(contentPadding: const EdgeInsets.symmetric(horizontal: 18), title: const Text('帧插值'), subtitle: const Text('下一段视频生效；会增加 GPU 负载。'), value: _settings.interpolation, onChanged: (value) => _saveSettings(_settings.copyWith(interpolation: value))),
        _slider('字幕大小', _settings.subtitleScale, 0.5, 3, '${_settings.subtitleScale.toStringAsFixed(1)}×', (value) => _saveSettings(_settings.copyWith(subtitleScale: value))),
        _slider('字幕位置', _settings.subtitlePosition.toDouble(), 0, 100, '${_settings.subtitlePosition}%', (value) => _saveSettings(_settings.copyWith(subtitlePosition: value.round()))),
      ])),
      const SizedBox(height: 18),
      const Text('视频缓存', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      _preferenceCard(Column(children: [
        _choice('网络缓存', _settings.cacheMode, const {'auto': '自动（推荐）', 'yes': '启用', 'no': '禁用'}, (value) => _saveSettings(_settings.copyWith(cacheMode: value))),
        _slider('预读时间', _settings.cacheSeconds.toDouble(), 1, 300, '${_settings.cacheSeconds} 秒', (value) => _saveSettings(_settings.copyWith(cacheSeconds: value.round()))),
        _slider('内存上限', _settings.cacheMemoryMb.toDouble(), 16, 512, '${_settings.cacheMemoryMb} MB', (value) => _saveSettings(_settings.copyWith(cacheMemoryMb: value.round()))),
        const Padding(padding: EdgeInsets.fromLTRB(18, 2, 18, 14), child: Text('这里控制 libmpv 的内存网络缓存。它不会移动 RAM 缓存到磁盘。', style: TextStyle(color: Colors.white54, fontSize: 12))),
      ])),
      const SizedBox(height: 18),
      const Text('解码与格式', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      _preferenceCard(SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18),
        title: const Text('自动选择最省资源的视频编码'),
        subtitle: const Text('只会影响自动格式选择，不会降低手动指定的画质。'),
        value: _settings.autoSelectCodec,
        onChanged: (value) => _saveSettings(_settings.copyWith(autoSelectCodec: value)),
      )),
      const SizedBox(height: 10),
      _preferenceCard(Column(children: [
        ListTile(
          leading: const Icon(Icons.developer_board_outlined, color: _accent),
          title: const Text('GPU'),
          subtitle: Text(_windowsVideoInfo.gpuNames.isEmpty ? '尚未检测到或无法读取' : _windowsVideoInfo.gpuNames.join('\n')),
          isThreeLine: _windowsVideoInfo.gpuNames.length > 1,
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.memory_outlined, color: _accent),
          title: const Text('当前实际解码方式'),
          subtitle: Text('视频：$_currentCodec\n方式：$_currentHwdec'),
          isThreeLine: true,
          trailing: OutlinedButton(onPressed: _playing == null ? null : _inspectCurrentDecoder, child: const Text('检测')),
        ),
        const Divider(height: 1),
        _decoderRow('H.264', _decodeStates['h264']!),
        _decoderRow('VP9', _decodeStates['vp9']!),
        _decoderRow('AV1', _decodeStates['av1']!),
        const Divider(height: 1),
        _extensionRow('VP9 Video Extensions', _windowsVideoInfo.vp9Extension, 'https://apps.microsoft.com/detail/9n4d0msmp0pt'),
        _extensionRow('AV1 Video Extension', _windowsVideoInfo.av1Extension, 'https://apps.microsoft.com/detail/9mvzqvxjbq9v'),
        const Padding(padding: EdgeInsets.fromLTRB(18, 4, 18, 14), child: Text('状态只会在实际播放对应编码后更新；自动模式本身不代表硬件解码已成功。', style: TextStyle(color: Colors.white54, fontSize: 12))),
        const Padding(padding: EdgeInsets.fromLTRB(18, 0, 18, 14), child: Text('商店扩展是 Windows Media Foundation 组件，不是 YTPlus 或 libmpv 的必需依赖；安装它也不能让不支持的 GPU 获得硬件解码。', style: TextStyle(color: Colors.white54, fontSize: 12))),
      ])),
      const SizedBox(height: 14),
      _preferenceCard(ExpansionTile(
        leading: const Icon(Icons.tune, color: _accent),
        title: const Text('高级 libmpv 参数'),
        subtitle: const Text('只展示不会改变 media_kit 视频输出的选项。'),
        children: [
          _optionInfo('hwdec', _settings.hwdec, '硬件解码方式', '下一段视频'),
          _optionInfo('scale', _settings.scale, '视频缩放算法', '立即'),
          _optionInfo('deband', _settings.deband ? 'yes' : 'no', '色带消除', '立即'),
          _optionInfo('interpolation', _settings.interpolation ? 'yes' : 'no', '帧插值', '下一段视频'),
          _optionInfo('cache', _settings.cacheMode, '网络缓存模式', '立即'),
          _optionInfo('cache-secs', '${_settings.cacheSeconds}', '缓存预读时间', '立即'),
          _optionInfo('demuxer-max-bytes', '${_settings.cacheMemoryMb}MiB', '缓存内存上限', '立即'),
          Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), child: OutlinedButton.icon(onPressed: () => _saveSettings(const PlayerSettings()), icon: const Icon(Icons.restart_alt), label: const Text('恢复全部播放器默认设置'))),),
        ],
      )),
      const SizedBox(height: 18),
      const Text('存储与缓存', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      _preferenceCard(Column(children: [
        ListTile(
          leading: const Icon(Icons.folder_outlined, color: _accent),
          title: const Text('当前应用缓存位置'),
          subtitle: Text(_settings.cachePath ?? (directories == null ? '正在准备…' : directories.cache.path)),
          trailing: TextButton(onPressed: _changeCacheLocation, child: const Text('选择文件夹')),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined, color: _accent),
          title: const Text('缓存占用'),
          subtitle: Text('${_formatBytes(_cacheBytes)} · 只清理 YTPlus 创建的缓存目录'),
          trailing: OutlinedButton(onPressed: _clearCache, child: const Text('清理')),
        ),
      ])),
      const SizedBox(height: 20),
      const Text('YTPlus 只会写入自己的 LocalAppData 目录；安装和首次启动不要求管理员权限。', style: TextStyle(color: Colors.white54, height: 1.5)),
    ]);
  }

  Widget _preferenceCard(Widget child) => Card(
        color: _surface,
        margin: EdgeInsets.zero,
        child: child,
      );

  Widget _choice(String label, String selected, Map<String, String> choices, ValueChanged<String> onChanged) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 9, 18, 9),
        child: Row(children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 18),
          DropdownButton<String>(value: selected, underline: const SizedBox.shrink(), onChanged: (value) { if (value != null) onChanged(value); }, items: choices.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList()),
        ]),
      );

  Widget _slider(String label, double value, double min, double max, String description, ValueChanged<double> onChanged) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 9, 18, 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text(label), const Spacer(), Text(description, style: const TextStyle(color: Colors.white54))]),
          Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, divisions: ((max - min) * (label == '字幕大小' ? 10 : 1)).round(), onChanged: onChanged),
        ]),
      );

  Widget _optionInfo(String name, String value, String description, String applies) => ListTile(
        dense: true,
        title: Text(name, style: const TextStyle(fontFamily: 'monospace')),
        subtitle: Text('$description · $applies生效'),
        trailing: Text(value, style: const TextStyle(color: _accent, fontFamily: 'monospace')),
      );

  Widget _decoderRow(String codec, String status) => ListTile(
        dense: true,
        title: Text(codec),
        trailing: Text(status, style: TextStyle(color: status == '尚未验证' ? Colors.white54 : _accent)),
      );

  Widget _extensionRow(String title, ExtensionStatus status, String storeUrl) {
    final label = switch (status) {
      ExtensionStatus.present => '已安装',
      ExtensionStatus.missing => '未安装',
      ExtensionStatus.unknown => '尚未验证',
    };
    return ListTile(
      dense: true,
      title: Text(title),
      subtitle: const Text('Windows Media Foundation 扩展'),
      trailing: status == ExtensionStatus.missing
          ? TextButton(onPressed: () => _openStore(storeUrl), child: const Text('在商店查看'))
          : Text(label, style: TextStyle(color: status == ExtensionStatus.present ? _accent : Colors.white54)),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

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
