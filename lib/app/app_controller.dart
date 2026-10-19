import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app_directories.dart';
import '../app_log.dart';
import '../app_preferences.dart';
import '../playback_recovery.dart';
import '../library_store.dart';
import '../secure_store.dart';
import '../sponsor_block.dart';
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
import 'account_controller.dart';
import 'library_controller.dart';
import 'video_list_loader.dart';

enum PageMode { home, explore, subscriptions, history, playlists, settings, channel, playlist }

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
  VideoItem? playing;
  PageMode mode = PageMode.home;
  bool ready = false;
  bool checking = false;
  String status = '正在准备 Windows 原生播放器…';
  /// Startup failure; the setup screen shows it with a retry button.
  String? error;
  String? playbackError;

  /// Favorites, playlists, followed channels and progress; set once ready.
  LibraryController? library;

  /// The optional Google sign-in for importing subscriptions and playlists.
  AccountController? account;

  /// The open channel page and its uploads.
  ChannelRef? channel;
  VideoListLoader? channelVideos;
  /// What the channel page is searching for; null lists the uploads.
  String? channelQuery;
  /// The id of the open playlist page: a [LocalPlaylist] id, or
  /// [favoritesPlaylistId].
  String? openPlaylistId;
  static const favoritesPlaylistId = 'favorites';
  PageMode _returnMode = PageMode.home;

  /// Whether the statistics overlay is shown over the video.
  bool showStats = false;

  void toggleStats() => _update(() => showStats = !showStats);

  /// Videos like the one playing, found by searching for its title.
  VideoListLoader? related;

  /// The list the current video was opened from, shown as the play queue.
  List<VideoItem> queue = const [];
  VideoDetails? details;
  bool loadingDetails = false;

  AppearanceSettings appearance;
  final AppearanceSettingsStore? _appearanceStore;
  /// The Windows accent colour, once read, for [AppearanceSettings.systemAccent].
  Color? windowsAccent;

  AppPreferences preferences = const AppPreferences();
  AppPreferencesStore? _preferencesStore;

  AppController({this.appearance = const AppearanceSettings(), AppearanceSettingsStore? appearanceStore}) : _appearanceStore = appearanceStore {
    _applyAppearanceGlobals(appearance);
  }

  /// The seed colour the theme is built from.
  Color get accentColor => appearance.systemAccent && windowsAccent != null ? windowsAccent! : appearance.accent;

  static void _applyAppearanceGlobals(AppearanceSettings appearance) {
    VideoItem.thumbnailFile = appearance.thumbnailQuality.file;
    videoCardMinWidth = appearance.cardWidth;
  }

  int _playSerial = 0;
  String? _query;
  final _playerSubscriptions = <StreamSubscription<Object>>[];
  double _volumeBeforeMute = 100;
  bool _libmpvConfirmed = false;
  /// The video whose position is being recorded; null while switching, so
  /// positions of the previous file are not credited to the next.
  VideoItem? _tracking;
  DateTime _lastProgressSave = DateTime(0);
  List<SkipSegment> _segments = const [];
  final _skipped = <SkipSegment>{};
  final _http = http.Client();
  final _recovery = PlaybackRecovery();
  /// The last position actually played, which survives a failed stream.
  Duration _lastPosition = Duration.zero;
  Timer? _stallTimer;
  bool _recovering = false;
  bool _shutDown = false;
  late final _sponsorBlock = SponsorBlock(_http);
  bool _disposed = false;
  final _notices = StreamController<String>.broadcast();

  /// One-off messages the UI shows as snack bars.
  Stream<String> get notices => _notices.stream;

  List<VideoItem> get history => _history?.items ?? const [];

  /// The text of the current or last search, if any.
  String? get query => _query;

  /// The current search's results; null before the first search.
  VideoListLoader? searchResults;
  SearchFilter searchFilter = SearchFilter.all;

  List<VideoItem> get results => searchResults?.items ?? const [];
  List<ChannelResult> get channelResults => searchResults?.channels ?? const [];
  bool get searching => searchResults?.loading ?? false;
  String? get searchError => searchResults?.error;

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
      await AppLog.open(directories.logs);
      logInfo('YTPlus $appVersion 启动 · ${Platform.operatingSystemVersion}');
      final history = HistoryStore(directories);
      await history.initialize();
      final libraryStore = LibraryStore(File('${directories.data.path}${Platform.pathSeparator}library.json'));
      await libraryStore.load();
      final settingsStore = PlayerSettingsStore(directories);
      final settings = await settingsStore.load();
      final preferencesStore = AppPreferencesStore(directories);
      final preferences = await preferencesStore.load();
      final cacheManager = CacheManager(directories);
      await cacheManager.prepare(settings);
      final cacheBytes = await cacheManager.size(settings);
      final manager = ToolManager(directories, (message) {
        logInfo(message);
        _update(() => status = message);
      });
      _tools = manager;
      await manager.initialize();
      final paths = await manager.ensureReady();
      addToWindowsPath(paths.executableDirectories);
      MediaKit.ensureInitialized(libmpv: paths.mpv);
      final player = Player(configuration: PlayerConfiguration(
        bufferSize: settings.cacheMemoryMb * 1024 * 1024,
        // libmpv draws the subtitles so the 字幕设置 options (sub-scale,
        // sub-pos, border and background) apply; the Flutter subtitle view
        // is turned off on the watch page.
        libass: true,
      ));
      final controller = VideoController(player, configuration: VideoControllerConfiguration(hwdec: settings.hwdec));
      final ignoredOptions = await PlayerOptionApplicator.apply(player, settings);
      await player.setVolume(settings.defaultVolume.toDouble());
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
        _preferencesStore = preferencesStore;
        this.preferences = preferences;
        mode = PageMode.values.where((m) => m.name == preferences.startPage).firstOrNull ?? PageMode.home;
        decodeStates = {...settings.decoderResults};
        _history = history;
        _repository = _repositoryFor(paths, cacheManager, settings);
        final library = this.library = LibraryController(libraryStore, client: _http)
          ..repository = _repository
          ..addListener(notifyListeners);
        account = AccountController(
          clientFile: File('${directories.data.path}${Platform.pathSeparator}google-client.json'),
          credentials: SecureJsonFile(File('${directories.data.path}${Platform.pathSeparator}google-account.bin'), DpapiProtector()),
          client: _http,
          library: library,
          notice: _notice,
        )..addListener(notifyListeners);
        this.player = player;
        videoController = controller;
        _listenTo(player);
        ready = true;
        status = ignoredOptions.isEmpty ? '就绪 · 解码方式将在播放时验证' : '就绪 · 已忽略不支持的设置：${ignoredOptions.join(', ')}';
        error = null;
      });
      if (mode == PageMode.explore) _loadExplore();
      // Do not block the UI while checking newer releases.
      if (preferences.autoCheckUpdates) unawaited(manager.checkUpdates());
      unawaited(_readWindowsVideoInfo());
      unawaited(account?.load());
      logInfo('组件就绪 · libmpv ${manager.libmpv.current?.label ?? '内置'} · yt-dlp ${manager.ytDlpVersion ?? '?'} · ${paths.mpv}');
    } catch (e) {
      _update(() {
        error = e.toString();
        status = '初始化失败';
        logError('初始化失败', e);
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

  Future<void> search(String value, {SearchFilter? filter}) async {
    final query = value.trim();
    if (query.isEmpty || !ready) return;
    final asUrl = parseYoutubeId(query);
    if (asUrl != null) {
      await play(VideoItem(id: asUrl, title: 'YouTube 视频 · $asUrl', channel: 'YouTube', url: 'https://www.youtube.com/watch?v=$asUrl'));
      return;
    }
    player?.pause();
    final repository = _repository!;
    final chosen = filter ?? searchFilter;
    _update(() {
      mode = PageMode.explore;
      playing = null;
      _query = query;
      searchFilter = chosen;
      searchResults?.dispose();
      searchResults = VideoListLoader(() => repository.search(query, filter: chosen))
        ..addListener(notifyListeners)
        ..loadMore();
    });
  }

  /// Fetches the next page of the current search. After a failed page,
  /// scrolling does not retry on its own; [retry] comes from the retry button.
  void loadMoreResults({bool retry = false}) => searchResults?.loadMore(retry: retry);

  /// Leaves search results for the explore topics.
  void clearSearch() {
    _update(() {
      _query = null;
      searchResults?.dispose();
      searchResults = null;
    });
    _loadExplore();
  }

  /// Topics on the explore page: a label and the query searched for.
  static const exploreTopics = [
    ('音乐', '音乐'),
    ('游戏', '游戏'),
    ('科技', '科技 数码'),
    ('新闻', '新闻'),
    ('体育', '体育'),
    ('动画', '动画'),
    ('电影', '电影 预告片'),
    ('美食', '美食'),
    ('旅行', '旅行 vlog'),
    ('知识', '科普'),
  ];

  /// YouTube's filter for videos uploaded this month, most viewed first.
  static const exploreFilter = 'CAMSBAgEEAE%253D';

  int exploreTopic = 0;
  /// The chosen topic's videos.
  VideoListLoader? explore;

  /// Opens the explore page on its topics.
  void openExplore() {
    if (_query != null) {
      _query = null;
      searchResults?.dispose();
      searchResults = null;
    }
    navigate(PageMode.explore);
    _loadExplore();
  }

  void setExploreTopic(int index) {
    if (index == exploreTopic && explore != null) return;
    exploreTopic = index;
    explore?.dispose();
    explore = null;
    _loadExplore();
  }

  void _loadExplore() {
    final repository = _repository;
    if (repository == null || explore != null) return;
    final query = exploreTopics[exploreTopic].$2;
    _update(() => explore = VideoListLoader(() => repository.search(query, sp: exploreFilter))
      ..addListener(notifyListeners)
      ..loadMore());
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
    _saveProgress();
    final serial = ++_playSerial;
    _recovery.reset();
    final resume = preferences.resumePlayback ? library?.progressOf(item.id) : null;
    final start = resume != null && resume.resumable ? resume.position : null;
    _update(() {
      playing = item;
      if (from != null) queue = List.unmodifiable(from);
      playbackError = null;
      details = null;
      loadingDetails = true;
      related?.dispose();
      related = null;
      _segments = const [];
      _skipped.clear();
    });
    unawaited(_loadDetails(item, serial));
    if (settings.sponsorBlock) unawaited(_loadSegments(item, serial));
    if (await _open(item, serial, start: start, play: preferences.autoPlay)) {
      if (settings.defaultSpeed != player.state.rate) await player.setRate(settings.defaultSpeed);
      if (preferences.recordHistory) await _history?.record(item);
      if (start != null) _notice('从 ${_clock(start)} 继续播放');
    }
  }

  static String _clock(Duration d) {
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:$seconds' : '${d.inMinutes}:$seconds';
  }

  /// Records where the current video is, so it can resume later.
  /// [now] writes it to disk at once, for when playback stops.
  void _saveProgress({bool now = false}) {
    final item = _tracking;
    final player = this.player;
    if (item == null || player == null || !preferences.recordProgress) return;
    final duration = player.state.duration;
    if (duration <= Duration.zero) return;
    library?.recordProgress(item.id, player.state.position, duration);
    if (now) unawaited(library?.flush());
  }

  Future<void> _loadSegments(VideoItem item, int serial) async {
    try {
      final segments = await _sponsorBlock.segments(item.id, settings.sponsorCategories);
      if (serial == _playSerial) _update(() => _segments = segments);
    } catch (_) {
      // Playback does not depend on SponsorBlock being reachable.
    }
  }

  void _skipSegments(Duration position) {
    for (final segment in _segments) {
      if (_skipped.contains(segment) || !segment.contains(position)) continue;
      // Each segment is skipped once, so seeking back into it plays it.
      _skipped.add(segment);
      unawaited(player?.seek(segment.end));
      if (settings.sponsorNotice) _notice('已跳过${sponsorCategories[segment.category] ?? '片段'}');
      return;
    }
  }

  /// Opens [item] with the current format settings, from [start] if given.
  Future<bool> _open(VideoItem item, int serial, {Duration? start, bool play = true}) async {
    final player = this.player!;
    try {
      if (!_libmpvConfirmed) await _tools?.libmpv.markPlaying();
      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('ytdl-format', VideoFormatSelector.expressionFor(settings));
      }
      _tracking = null;
      _lastPosition = start ?? Duration.zero;
      await player.open(Media(item.url, start: start), play: play);
      if (serial == _playSerial) _tracking = item;
      unawaited(inspectCurrentDecoder());
      _update(() {});
      return true;
    } catch (e) {
      logError('无法打开视频 ${item.id}', e);
      if (serial == _playSerial) _update(() => playbackError = '$e');
      return false;
    }
  }

  /// Reopens the current video where it stopped after the network failed,
  /// or shows [message] once the attempts are used up.
  Future<void> _recover(String message) async {
    final item = _tracking;
    if (item == null || _recovering) return;
    final position = _lastPosition;
    if (!_recovery.tryAttempt()) {
      logError('播放中断，已放弃自动重连 ${item.id}：$message');
      _update(() => playbackError = message);
      return;
    }
    logInfo('播放中断，从 ${_clock(position)} 重新连接 ${item.id}：$message');
    _notice('网络中断，正在从 ${_clock(position)} 重新连接…');
    _recovering = true;
    try {
      // A new open also asks yt-dlp again, which replaces stream addresses
      // that expired while the video sat paused.
      await _open(item, _playSerial, start: position);
    } finally {
      _recovering = false;
    }
  }

  Future<void> retryPlayback() async {
    final item = playing;
    if (item != null) await play(item);
  }

  void _listenTo(Player player) {
    _playerSubscriptions.addAll([
      // A second of playback proves a downloaded libmpv works on this PC.
      player.stream.position.listen((position) {
        if (_tracking == null) return;
        if (position > Duration.zero) {
          // Ten seconds of playback after a reconnect means it worked.
          if (position - _lastPosition > const Duration(seconds: 10)) _recovery.reset();
          if (!_recovering) _lastPosition = position;
        }
        if (_segments.isNotEmpty) _skipSegments(position);
        final now = DateTime.now();
        if (now.difference(_lastProgressSave) > const Duration(seconds: 5)) {
          _lastProgressSave = now;
          _saveProgress();
        }
        if (_libmpvConfirmed || position < const Duration(seconds: 1)) return;
        _libmpvConfirmed = true;
        unawaited(_tools?.libmpv.confirm());
      }),
      player.stream.completed.listen((done) {
        if (!done || playing == null) return;
        if (_tracking != null && PlaybackRecovery.endedEarly(_lastPosition, player.state.duration)) {
          unawaited(_recover('视频在 ${_clock(_lastPosition)} 意外结束'));
          return;
        }
        _saveProgress();
        unawaited(_playAfterEnd());
      }),
      // libmpv reports failures that happen after open() returned, such as
      // yt-dlp finding no playable format, only through this stream. Errors
      // once the video has loaded (a broken subtitle track) are not fatal.
      player.stream.error.listen((message) {
        if (playing == null || message.isEmpty) return;
        if (player.state.duration == Duration.zero) {
          logError('播放失败 ${playing!.id}：$message');
          _update(() => playbackError = message);
        } else if (PlaybackRecovery.isNetworkError(message)) {
          unawaited(_recover(message));
        }
      }),
      // A stream that stops delivering data leaves mpv buffering forever.
      player.stream.buffering.listen((buffering) {
        _stallTimer?.cancel();
        if (!buffering || _tracking == null) return;
        _stallTimer = Timer(PlaybackRecovery.stallTimeout, () {
          if (player.state.buffering && player.state.playing) unawaited(_recover('缓冲超过 ${PlaybackRecovery.stallTimeout.inSeconds} 秒没有进展'));
        });
      }),
    ]);
  }

  /// Follows [PlayerSettings.playOrder] once a video ends. Single cycle is
  /// mpv's loop-file, so a looping video never ends.
  Future<void> _playAfterEnd() async {
    if (sleepAfterCurrent) {
      _update(() => sleepAfterCurrent = false);
      _notice('定时关闭：当前视频已播完');
      return;
    }
    switch (settings.playOrder) {
      case PlayOrder.pause || PlayOrder.singleCycle:
        return;
      case PlayOrder.listOrder:
        if (upNext.isNotEmpty) await play(upNext.first);
      case PlayOrder.listCycle:
        if (upNext.isNotEmpty) {
          await play(upNext.first);
        } else if (queue.isNotEmpty) {
          await play(queue.first);
        } else if (playing != null) {
          await play(playing!);
        }
      case PlayOrder.autoPlayRelated:
        await playNext();
    }
  }

  /// Plays the next video in the queue, if there is one.
  Future<void> playNext() async {
    final next = upNext;
    final suggestions = relatedItems;
    if (next.isNotEmpty) {
      await play(next.first);
    } else if (suggestions.isNotEmpty) {
      await play(suggestions.first, from: suggestions);
    }
  }

  /// Whether nothing will play once the current video ends.
  bool get stopsAfterEnd =>
      sleepAfterCurrent ||
      switch (settings.playOrder) {
        PlayOrder.pause => true,
        PlayOrder.singleCycle || PlayOrder.listCycle => false,
        PlayOrder.listOrder => upNext.isEmpty,
        PlayOrder.autoPlayRelated => !hasNext,
      };

  /// SponsorBlock segments of the playing video, for the progress bar.
  List<SkipSegment> get segments => _segments;

  /// When the sleep timer pauses playback; null when it is off.
  DateTime? sleepAt;
  /// Pause once the current video ends instead of at [sleepAt].
  bool sleepAfterCurrent = false;
  Timer? _sleepTimer;

  /// Pauses playback after [after], or at the end of the current video when
  /// [afterCurrent]; null turns the timer off. From PiliNara's 定时关闭.
  void setSleepTimer(Duration? after, {bool afterCurrent = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = after == null ? null : Timer(after, () {
      unawaited(player?.pause());
      _update(() => sleepAt = null);
      _notice('定时关闭：已暂停播放');
    });
    _update(() {
      sleepAt = after == null ? null : DateTime.now().add(after);
      sleepAfterCurrent = afterCurrent;
    });
  }

  bool get hasNext => upNext.isNotEmpty || relatedItems.isNotEmpty;

  /// Related videos that pass the content filters.
  List<VideoItem> get relatedItems => visible(related?.items ?? const []);

  /// Seeks by [offset], staying inside the video.
  Future<void> seekBy(Duration offset) async {
    final player = this.player;
    if (player == null) return;
    var target = player.state.position + offset;
    final duration = player.state.duration;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await player.seek(target);
  }

  Future<void> changeVolume(double delta) async {
    final player = this.player;
    if (player != null) await player.setVolume((player.state.volume + delta).clamp(0.0, settings.volumeMax.toDouble()).toDouble());
  }

  Future<void> toggleMute() async {
    final player = this.player;
    if (player == null) return;
    final volume = player.state.volume;
    if (volume > 0) {
      _volumeBeforeMute = volume;
      await player.setVolume(0);
    } else {
      await player.setVolume(_volumeBeforeMute);
    }
  }

  /// Saves the quality limit and reloads the current video where it was.
  Future<void> setMaxHeight(int height) async {
    if (height == settings.maxHeight) return;
    await reloadVideo(settings.copyWith(maxHeight: height));
  }

  /// Saves [next], if given, and reopens the current video where it was,
  /// so format choices take effect at once.
  Future<void> reloadVideo([PlayerSettings? next]) async {
    if (next != null) await saveSettings(next);
    final item = playing;
    final player = this.player;
    if (item == null || player == null) return;
    final position = player.state.position;
    final wasPlaying = player.state.playing;
    _update(() => playbackError = null);
    if (await _open(item, _playSerial, start: position) && !wasPlaying) await player.pause();
  }

  Future<void> setAutoplayNext(bool value) => setPlayOrder(value ? PlayOrder.autoPlayRelated : PlayOrder.pause);

  Future<void> setPlayOrder(PlayOrder order) => saveSettings(settings.copyWith(playOrder: order));

  /// The audio outputs libmpv reports, "auto" first.
  List<AudioDevice> get audioDevices => player?.state.audioDevices ?? const [];

  Future<void> _loadDetails(VideoItem item, int serial) async {
    try {
      final loaded = await _repository!.details(item.id);
      if (serial == _playSerial) {
        _update(() {
          details = loaded;
          if (preferences.showRelated) related = _relatedTo(item, loaded.title.isNotEmpty ? loaded.title : item.title);
        });
      }
    } catch (_) {
      // The page still shows what the list already knew about the video.
    } finally {
      if (serial == _playSerial) _update(() => loadingDetails = false);
    }
  }

  VideoListLoader _relatedTo(VideoItem item, String title) {
    final repository = _repository!;
    // Long titles make poor queries; the first words carry the topic.
    final query = title.length > 60 ? title.substring(0, 60) : title;
    final loader = VideoListLoader(
      () => repository.search(query, filter: SearchFilter.videos),
      pageSize: 13,
      limit: 12,
      where: (other) => other.id != item.id,
    )..addListener(notifyListeners);
    loader.loadMore();
    return loader;
  }

  /// The channel of the playing video, once known.
  ChannelRef? get playingChannel {
    final item = playing;
    if (item == null) return null;
    final id = details?.channelId;
    if (id != null) return ChannelRef(id, details!.channel.isNotEmpty ? details!.channel : item.channel);
    return item.channelRef;
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
    _saveProgress(now: true);
    _tracking = null;
    ++_playSerial;
    _update(() {
      playing = null;
      playbackError = null;
    });
    player?.pause();
  }

  void navigate(PageMode target) {
    _saveProgress(now: true);
    _tracking = null;
    ++_playSerial;
    if (target == PageMode.subscriptions && preferences.feedAutoRefresh) {
      unawaited(library?.refreshFeed(interval: Duration(minutes: preferences.feedRefreshMinutes)));
    }
    _update(() {
      if (_isDetail(target) && !_isDetail(mode)) _returnMode = mode;
      mode = target;
      playing = null;
      playbackError = null;
    });
    player?.pause();
  }

  static bool _isDetail(PageMode mode) => mode == PageMode.channel || mode == PageMode.playlist;

  /// Opens [ref]'s page with its uploads.
  void openChannel(ChannelRef ref) {
    final repository = _repository;
    if (repository == null) return;
    channelVideos?.dispose();
    channel = ref;
    channelQuery = null;
    channelVideos = VideoListLoader(() => repository.channelVideos(ref))
      ..addListener(notifyListeners)
      ..loadMore();
    navigate(PageMode.channel);
  }

  /// Searches the open channel's videos for [query]; an empty query lists
  /// the uploads again.
  void searchChannel(String query) {
    final repository = _repository;
    final ref = channel;
    if (repository == null || ref == null) return;
    final text = query.trim();
    _update(() {
      channelVideos?.dispose();
      channelQuery = text.isEmpty ? null : text;
      channelVideos = VideoListLoader(() => text.isEmpty ? repository.channelVideos(ref) : repository.channelSearch(ref, text))
        ..addListener(notifyListeners)
        ..loadMore();
    });
  }

  void openPlaylist(String id) {
    openPlaylistId = id;
    navigate(PageMode.playlist);
  }

  /// Leaves a channel or playlist page for the page it was opened from.
  void goBack() => navigate(_returnMode);

  void retrySearch() {
    final last = _query;
    if (last != null) unawaited(search(last));
  }

  /// Shows the current search's results of another kind.
  void setSearchFilter(SearchFilter filter) {
    final last = _query;
    if (last != null && filter != searchFilter) unawaited(search(last, filter: filter));
  }

  Future<void> clearHistory() async {
    await _history?.clear();
    _update(() {});
    _notice('观看历史已清空。');
  }

  /// Videos of [items] that pass the privacy and content filters. The
  /// subscriptions feed is filtered only when [AppPreferences.filterSubscriptions].
  List<VideoItem> visible(List<VideoItem> items, {bool subscriptions = false}) {
    final prefs = preferences;
    if (subscriptions && !prefs.filterSubscriptions) return items.where((item) => !prefs.isBlocked(item.channelId)).toList();
    final library = this.library;
    return items.where((item) => prefs.shows(item, watched: library?.progressOf(item.id)?.finished ?? false)).toList();
  }

  Future<void> savePreferences(AppPreferences next) async {
    _update(() => preferences = next);
    try {
      await _preferencesStore?.save(next);
    } on FileSystemException {
      _notice('设置未能保存，本次运行仍然生效。');
    }
  }

  void blockChannel(ChannelRef channel) {
    if (preferences.isBlocked(channel.id)) return;
    unawaited(savePreferences(preferences.copyWith(blockedChannels: [...preferences.blockedChannels, channel])));
    _notice('已屏蔽“${channel.name.isEmpty ? channel.id : channel.name}”，可在 设置 › 隐私设置 中解除');
  }

  void unblockChannel(String id) =>
      unawaited(savePreferences(preferences.copyWith(blockedChannels: preferences.blockedChannels.where((c) => c.id != id).toList())));

  void clearProgress() {
    library?.clearProgress();
    _notice('播放进度已清空。');
  }

  /// Reads the Windows accent colour for [AppearanceSettings.systemAccent].
  Future<void> refreshWindowsAccent() async {
    final color = await readWindowsAccent();
    if (color != null && color != windowsAccent) _update(() => windowsAccent = color);
  }

  /// Settings as one JSON document, for backup. Values that belong to this
  /// computer (cache folder, audio output, decoder results) are left out.
  String exportSettings() => const JsonEncoder.withIndent('  ').convert({
        'app': 'YTPlus',
        'version': 1,
        'exported': DateTime.now().toIso8601String(),
        'player': settings.toJson()
          ..remove('cachePath')
          ..remove('cacheLimitGb')
          ..remove('audioDevice')
          ..remove('decoderResults'),
        'appearance': appearance.toJson(),
        'preferences': preferences.toJson(),
      });

  /// Applies settings exported by [exportSettings]; false when [text] is not
  /// such a file. This computer's own values are kept.
  Future<bool> importSettings(String text) async {
    final Object? data;
    try {
      data = jsonDecode(text);
    } on FormatException {
      return false;
    }
    if (data is! Map || data['app'] != 'YTPlus') return false;
    final player = PlayerSettings.fromJson(data['player']).copyWith(
      cachePath: settings.cachePath,
      clearCachePath: settings.cachePath == null,
      cacheLimitGb: settings.cacheLimitGb,
      clearCacheLimit: settings.cacheLimitGb == null,
      audioDevice: settings.audioDevice,
      decoderResults: settings.decoderResults,
    );
    await saveSettings(player);
    await saveAppearance(AppearanceSettings.fromJson(data['appearance']));
    await savePreferences(AppPreferences.fromJson(data['preferences']));
    logInfo('已导入设置');
    return true;
  }

  /// Restores every default except this computer's cache folder and
  /// decoder results.
  Future<void> resetSettings() async {
    await saveSettings(PlayerSettings(cachePath: settings.cachePath, cacheLimitGb: settings.cacheLimitGb, decoderResults: settings.decoderResults));
    await saveAppearance(const AppearanceSettings());
    await savePreferences(const AppPreferences());
    _notice('已恢复默认设置。');
  }

  Future<void> saveAppearance(AppearanceSettings next) async {
    _applyAppearanceGlobals(next);
    if (next.systemAccent && windowsAccent == null) unawaited(refreshWindowsAccent());
    _update(() => appearance = next);
    try {
      await _appearanceStore?.save(next);
    } on FileSystemException {
      _notice('外观设置未能保存，本次运行仍然生效。');
    }
  }

  ToolManager? get tools => _tools;

  /// Goes back to the libmpv shipped with YTPlus from the next launch on.
  Future<void> rollBackLibmpv() async {
    await _tools?.libmpv.rollBack();
    _update(() {});
    _notice('已改回内置 libmpv，重启 YTPlus 后生效。');
  }

  Future<void> rollBackYtDlp() async {
    await _tools?.rollBackYtDlp();
    _update(() {});
    _notice('已改回上一个 yt-dlp，重启 YTPlus 后生效。');
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
        library?.repository = _repository;
      }
      status = ignoredOptions.isEmpty
          ? '播放器设置已保存${requiresNextVideo ? '；硬件解码和帧插值在下一段视频生效。' : '。'}'
          : '已保存；此 libmpv 不支持：${ignoredOptions.join(', ')}。';
    });
  }

  /// Sets one libmpv property without saving, for live previews such as
  /// the picture sliders.
  Future<void> previewProperty(String name, String value) async {
    final platform = player?.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty(name, value);
    } catch (_) {
      // A preview that libmpv rejects changes nothing.
    }
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

  /// Saves everything and releases the player before the window closes;
  /// dispose() alone does not run when Windows ends the process.
  Future<void> shutdown() async {
    if (_shutDown) return;
    _shutDown = true;
    _saveProgress();
    await library?.flush();
    for (final subscription in _playerSubscriptions) {
      await subscription.cancel();
    }
    _playerSubscriptions.clear();
    _stallTimer?.cancel();
    await player?.pause();
    await player?.dispose();
    logInfo('YTPlus 正常退出');
  }

  /// A summary for bug reports; it names no account, video or file
  /// contents, only versions and settings.
  String diagnostics() {
    final tools = _tools;
    return [
      'YTPlus $appVersion',
      'Windows ${Platform.operatingSystemVersion}',
      'CPU 核心 ${Platform.numberOfProcessors}',
      'GPU ${windowsVideoInfo.gpuNames.isEmpty ? '未知' : windowsVideoInfo.gpuNames.join(' / ')}',
      'libmpv ${tools?.libmpv.current?.label ?? '内置'}',
      'yt-dlp ${tools?.ytDlpVersion ?? '未安装'}',
      'Deno ${tools?.denoVersion ?? '未安装'}',
      '硬件解码设置 ${settings.hwdec} · 当前 $currentCodec · $currentHwdec',
      '画质上限 ${settings.maxHeight == 0 ? '自动' : '${settings.maxHeight}p'} · 编码 ${settings.codec.label} · 音质 ${settings.audioQuality.label}',
      '缓存 ${settings.cacheMode} · ${settings.cacheSeconds} 秒 · ${settings.cacheMemoryMb} MB',
      '数据目录 ${directories?.root.path ?? '未知'}',
    ].join('\n');
  }

  @override
  void dispose() {
    _disposed = true;
    _stallTimer?.cancel();
    _sleepTimer?.cancel();
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    _saveProgress();
    account?.dispose();
    library?.dispose();
    channelVideos?.dispose();
    searchResults?.dispose();
    explore?.dispose();
    related?.dispose();
    _http.close();
    if (!_shutDown) unawaited(player?.dispose());
    _tools?.dispose();
    unawaited(_notices.close());
    super.dispose();
  }
}
