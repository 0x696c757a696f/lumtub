import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app_directories.dart';
import '../appearance_settings.dart';
import '../cache_manager.dart';
import '../decoder_status.dart';
import '../models.dart';
import '../player_option_applicator.dart';
import '../player_settings.dart';
import '../tool_manager.dart';
import '../video_format_selector.dart';
import '../video_repository.dart';
import '../windows_env.dart';
import '../windows_video_info.dart';

enum PageMode { home, explore, subscriptions, history, playlists, settings }

/// Application state and actions, kept separate from the widgets that show them.
class AppController extends ChangeNotifier {
  HistoryStore? _history;
  AppDirectories? directories;
  CacheManager? _cacheManager;
  PlayerSettingsStore? _settingsStore;
  ToolManager? _tools;
  VideoRepository? _repository;
  ToolPaths? paths;

  Player? player;
  VideoController? videoController;

  int cacheBytes = 0;
  Map<String, DecoderStatus> decodeStates = const {};
  String currentCodec = '尚未播放视频';
  String currentHwdec = '尚未验证';
  WindowsVideoInfo windowsVideoInfo = const WindowsVideoInfo();
  PlayerSettings settings = const PlayerSettings();
  List<VideoItem> results = [];
  VideoItem? playing;
  PageMode mode = PageMode.home;
  bool ready = false;
  bool searching = false;
  bool hasMoreResults = false;
  bool checking = false;
  String status = '正在准备 Windows 原生播放器…';
  /// Startup failure; the setup screen shows it with a retry button.
  String? error;
  String? searchError;
  String? playbackError;

  /// The list the current video was opened from, shown as the play queue.
  List<VideoItem> queue = const [];
  VideoDetails? details;
  bool loadingDetails = false;

  AppearanceSettings appearance;
  final AppearanceSettingsStore? _appearanceStore;

  AppController({this.appearance = const AppearanceSettings(), AppearanceSettingsStore? appearanceStore}) : _appearanceStore = appearanceStore;

  int _searchSerial = 0;
  int _playSerial = 0;
  String? _query;
  StreamSubscription<VideoItem>? _searchSubscription;
  bool _disposed = false;
  final _notices = StreamController<String>.broadcast();

  /// One-off messages the UI shows as snack bars.
  Stream<String> get notices => _notices.stream;

  List<VideoItem> get history => _history?.items ?? const [];

  /// The text of the current or last search, if any.
  String? get query => _query;

  @visibleForTesting
  set debugQuery(String? value) => _query = value;

  Directory? get cacheRoot => _cacheManager?.rootFor(settings);

  Directory? get thumbnailDirectory {
    final root = cacheRoot;
    return root == null ? null : Directory('${root.path}${Platform.pathSeparator}thumbnails');
  }

  void _update(VoidCallback change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  void _notice(String message) {
    if (!_disposed) _notices.add(message);
  }

  Future<void> initialize() async {
    try {
      final directories = await AppDirectories.create();
      final history = HistoryStore(directories);
      await history.initialize();
      final settingsStore = PlayerSettingsStore(directories);
      final settings = await settingsStore.load();
      final cacheManager = CacheManager(directories);
      await cacheManager.prepare(settings);
      final cacheBytes = await cacheManager.size(settings);
      final manager = ToolManager(directories, (message) => _update(() => status = message));
      _tools = manager;
      await manager.initialize();
      final paths = await manager.ensureReady();
      addToWindowsPath(paths.executableDirectories);
      MediaKit.ensureInitialized(libmpv: paths.mpv);
      final player = Player(configuration: PlayerConfiguration(bufferSize: settings.cacheMemoryMb * 1024 * 1024));
      final controller = VideoController(player, configuration: VideoControllerConfiguration(hwdec: settings.hwdec));
      final ignoredOptions = await PlayerOptionApplicator.apply(player, settings);
      // yt-dlp and Deno are on PATH before libmpv starts, so ytdl_hook can find them.
      if (_disposed) {
        await player.dispose();
        return;
      }
      _update(() {
        this.paths = paths;
        this.directories = directories;
        _cacheManager = cacheManager;
        this.cacheBytes = cacheBytes;
        _settingsStore = settingsStore;
        this.settings = settings;
        decodeStates = {...settings.decoderResults};
        _history = history;
        _repository = _repositoryFor(paths, cacheManager, settings);
        this.player = player;
        videoController = controller;
        ready = true;
        status = ignoredOptions.isEmpty ? '就绪 · 解码方式将在播放时验证' : '就绪 · 已忽略不支持的设置：${ignoredOptions.join(', ')}';
        error = null;
      });
      // Do not block the UI while checking newer releases.
      unawaited(manager.checkUpdates());
      unawaited(_readWindowsVideoInfo());
    } catch (e) {
      _update(() {
        error = e.toString();
        status = '初始化失败';
      });
    }
  }

  void retryInitialize() {
    _update(() {
      error = null;
      status = '重新安装组件…';
    });
    unawaited(initialize());
  }

  VideoRepository _repositoryFor(ToolPaths paths, CacheManager cacheManager, PlayerSettings settings) =>
      VideoRepository(paths.ytDlp, cacheDirectory: '${cacheManager.rootFor(settings).path}${Platform.pathSeparator}yt-dlp');

  Future<void> search(String value) async {
    final query = value.trim();
    if (query.isEmpty || !ready) return;
    final asUrl = parseYoutubeId(query);
    if (asUrl != null) {
      await play(VideoItem(id: asUrl, title: 'YouTube 视频 · $asUrl', channel: 'YouTube', url: 'https://www.youtube.com/watch?v=$asUrl'));
      return;
    }
    player?.pause();
    _update(() {
      mode = PageMode.explore;
      playing = null;
      results = [];
      _query = query;
      hasMoreResults = false;
      searchError = null;
    });
    _loadPage(query, 1);
  }

  /// Fetches the next page of the current search, if there is one.
  /// Fetches the next page. After a failed page, scrolling does not retry on
  /// its own; [retry] comes from the retry button.
  void loadMoreResults({bool retry = false}) {
    final query = _query;
    if (query == null || searching || !hasMoreResults) return;
    if (searchError != null && !retry) return;
    _update(() => searchError = null);
    _loadPage(query, results.length + 1);
  }

  void _loadPage(String query, int start) {
    final serial = ++_searchSerial;
    unawaited(_searchSubscription?.cancel());
    final seen = {for (final item in results) item.id};
    var received = 0;
    var failed = false;
    _update(() => searching = true);
    _searchSubscription = _repository!.search(query, start: start).listen(
      (item) {
        if (serial != _searchSerial) return;
        received++;
        if (seen.add(item.id)) _update(() => results = [...results, item]);
      },
      onError: (Object e) {
        failed = true;
        if (serial == _searchSerial) _update(() => searchError = '$e');
      },
      onDone: () {
        if (serial != _searchSerial) return;
        _update(() {
          searching = false;
          // A failed page after the first can be retried from the banner.
          hasMoreResults = received >= VideoRepository.pageSize || (failed && results.isNotEmpty);
        });
      },
      cancelOnError: false,
    );
  }

  void _cancelSearch() {
    // An interrupted page can be fetched again by scrolling to the end.
    if (searching && _query != null) hasMoreResults = true;
    ++_searchSerial;
    unawaited(_searchSubscription?.cancel());
    _searchSubscription = null;
    searching = false;
  }

  static String? parseYoutubeId(String input) {
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

  /// Plays [item]; [from] is the list it was picked from and becomes the queue.
  Future<void> play(VideoItem item, {List<VideoItem>? from}) async {
    final player = this.player;
    if (player == null) return;
    final serial = ++_playSerial;
    _update(() {
      _cancelSearch();
      playing = item;
      if (from != null) queue = List.unmodifiable(from);
      playbackError = null;
      details = null;
      loadingDetails = true;
    });
    unawaited(_loadDetails(item, serial));
    try {
      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('ytdl-format', VideoFormatSelector.expressionFor(settings));
      }
      await player.open(Media(item.url));
      await _history?.record(item);
      unawaited(inspectCurrentDecoder());
      _update(() {});
    } catch (e) {
      if (serial == _playSerial) _update(() => playbackError = '$e');
    }
  }

  Future<void> retryPlayback() async {
    final item = playing;
    if (item != null) await play(item);
  }

  Future<void> _loadDetails(VideoItem item, int serial) async {
    try {
      final loaded = await _repository!.details(item.id);
      if (serial == _playSerial) _update(() => details = loaded);
    } catch (_) {
      // The page still shows what the list already knew about the video.
    } finally {
      if (serial == _playSerial) _update(() => loadingDetails = false);
    }
  }

  /// Videos after the current one in the queue, or the whole queue when the
  /// current video was opened from elsewhere.
  List<VideoItem> get upNext {
    final current = playing;
    if (current == null) return const [];
    final index = queue.indexWhere((item) => item.id == current.id);
    return index < 0 ? queue : queue.sublist(index + 1);
  }

  void stopWatching() {
    ++_playSerial;
    _update(() {
      playing = null;
      playbackError = null;
    });
    player?.pause();
  }

  void navigate(PageMode target) {
    ++_playSerial;
    _update(() {
      if (target != PageMode.explore) _cancelSearch();
      mode = target;
      playing = null;
      playbackError = null;
    });
    player?.pause();
  }

  void retrySearch() {
    final last = _query;
    if (last != null) unawaited(search(last));
  }

  Future<void> clearHistory() async {
    await _history?.clear();
    _update(() {});
    _notice('观看历史已清空。');
  }

  Future<void> saveAppearance(AppearanceSettings next) async {
    _update(() => appearance = next);
    try {
      await _appearanceStore?.save(next);
    } on FileSystemException {
      _notice('外观设置未能保存，本次运行仍然生效。');
    }
  }

  Future<void> checkUpdates() async {
    if (checking || _tools == null) return;
    _update(() => checking = true);
    try {
      await _tools!.checkUpdates(force: true);
    } finally {
      _update(() => checking = false);
    }
  }

  Future<void> saveSettings(PlayerSettings next) async {
    final store = _settingsStore;
    final player = this.player;
    if (store == null || player == null) return;
    final oldSettings = settings;
    final requiresNextVideo = next.hwdec != oldSettings.hwdec || next.interpolation != oldSettings.interpolation;
    final ignoredOptions = await PlayerOptionApplicator.apply(player, next);
    await store.save(next);
    _update(() {
      settings = next;
      final paths = this.paths;
      final cacheManager = _cacheManager;
      if (paths != null && cacheManager != null && next.cachePath != oldSettings.cachePath) {
        _repository = _repositoryFor(paths, cacheManager, next);
      }
      status = ignoredOptions.isEmpty
          ? '播放器设置已保存${requiresNextVideo ? '；硬件解码和帧插值在下一段视频生效。' : '。'}'
          : '已保存；此 libmpv 不支持：${ignoredOptions.join(', ')}。';
    });
  }

  Future<void> inspectCurrentDecoder() async {
    final platform = player?.platform;
    if (platform is! NativePlayer) {
      _notice('当前播放器无法读取 libmpv 解码状态。');
      return;
    }
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      final codec = (await platform.getProperty('video-codec')).trim().toLowerCase();
      final decoder = DecoderStatus.fromMpv(await platform.getProperty('hwdec-current'));
      final normalized = DecoderStatus.codecKey(codec);
      _update(() {
        currentCodec = codec.isEmpty ? '尚未验证' : codec;
        currentHwdec = decoder.label;
        if (normalized != null) decodeStates = {...decodeStates, normalized: decoder};
      });
      if (normalized != null) {
        settings = settings.copyWith(decoderResults: decodeStates);
        unawaited(_settingsStore?.save(settings));
      }
    } catch (_) {
      _update(() => currentHwdec = '尚未验证');
    }
  }

  Future<void> _readWindowsVideoInfo() async {
    final info = await WindowsVideoInfo.read();
    _update(() => windowsVideoInfo = info);
  }

  Future<void> openStore(String url) async {
    try {
      await Process.start('explorer.exe', [url]);
    } catch (_) {
      _notice('无法打开 Microsoft Store 链接。');
    }
  }

  /// Moves the managed cache under [selectedFolder]. [confirmMigrate] asks
  /// whether existing cache folders should move with it.
  Future<void> changeCacheLocation(String selectedFolder, Future<bool?> Function(String targetPath) confirmMigrate) async {
    final manager = _cacheManager;
    if (directories == null || manager == null) return;
    final target = Directory('$selectedFolder${Platform.pathSeparator}YTPlusCache');
    final next = settings.copyWith(cachePath: target.path);
    try {
      await manager.prepare(next);
      final migrate = await confirmMigrate(target.path);
      if (migrate == true) await manager.migrate(settings, next);
      await saveSettings(next);
      _update(() => cacheBytes = 0);
      _notice('缓存位置已保存。yt-dlp 缓存在下一次搜索时使用新位置。');
    } on FileSystemException catch (error) {
      _notice('新缓存位置不可用，继续使用原位置：${error.message}');
    }
  }

  bool ensureNotPlaying(String message) {
    if (playing == null) return true;
    _notice(message);
    return false;
  }

  Future<void> clearCache() async {
    final manager = _cacheManager;
    if (manager == null) return;
    if (!ensureNotPlaying('正在播放时不会清理缓存。请先返回列表。')) return;
    await manager.clear(settings);
    _update(() => cacheBytes = 0);
    _notice('已清理 YTPlus 管理的缓存文件。');
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSearch();
    unawaited(player?.dispose());
    _tools?.dispose();
    unawaited(_notices.close());
    super.dispose();
  }
}
