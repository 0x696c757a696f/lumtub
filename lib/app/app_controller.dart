import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color, PaintingBinding, Size;
import 'package:flutter/gestures.dart' show GestureBinding, PointerEvent;
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent, MethodChannel;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app_directories.dart';
import '../app_updater.dart';
import '../app_log.dart';
import '../app_window.dart';
import '../app_preferences.dart';
import '../play_queue.dart';
import '../playback_failure.dart';
import '../playback_recovery.dart';
import '../library_store.dart';
import '../secure_store.dart';
import '../dearrow.dart';
import '../downloads/download_formats.dart';
import '../downloads/download_manager.dart';
import '../downloads/download_models.dart';
import '../downloads/download_selection.dart';
import '../return_dislike.dart';
import '../sponsor_block.dart';
import '../appearance_settings.dart';
import '../cache_manager.dart';
import '../decoder_status.dart';
import '../native_core.dart';
import '../encrypted_dns.dart';
import '../native_http.dart';
import '../live_chat.dart';
import '../models.dart';
import '../network_proxy.dart';
import '../socks_bridge.dart';
import '../cast/cast_controller.dart';
import '../channel_playback.dart';
import '../speech_subtitles.dart';
import '../video_summary.dart';
import '../watch_time.dart';
import '../cast/cast_device.dart';
import '../cast/cast_stream.dart';
import '../invidious_streams.dart';
import '../piped_streams.dart';
import '../search_options.dart';
import '../search_suggestions.dart';
import '../youtube_comments.dart';
import '../youtube_tv_feed.dart';
import '../youtube_tv_sign_in.dart';
import '../youtube_web_sign_in.dart';
import '../tv_samples.dart' as tv_samples;
import '../youtube_related.dart';
import '../recommendations.dart';
import '../chunked_relay.dart';
import '../player_option_applicator.dart';
import '../power.dart';
import '../player_settings.dart';
import '../ffmpeg_component.dart';
import '../thumbnail_trim.dart';
import '../tool_manager.dart';
import '../format_policy.dart';
import '../memory_trim.dart';
import '../video_codec.dart';
import '../community_posts.dart';
import '../blocked_groups.dart';
import '../explore_filters.dart';
import '../explore_topics.dart';
import '../faith_topics.dart';
import '../storyboard.dart';
import '../stream_resolver.dart';
import '../subtitle_files.dart';
import '../subtitle_cues.dart';
import '../subtitle_translation.dart';
import '../translation.dart';
import '../translation_cache.dart';
import '../translation_services.dart';
import 'posts_loader.dart';
import '../video_output_size.dart';
import '../video_repository.dart';
import '../windows_env.dart';
import '../windows_video_info.dart';
import 'account_controller.dart';
import 'home_feed.dart';
import 'back_stack.dart';
import 'library_controller.dart';
import 'video_list_loader.dart';
import '../l10n/l10n.dart';
import '../friendly_error.dart';

enum PageMode { home, explore, subscriptions, history, playlists, downloads, settings, channel, playlist, youtubePlaylist }

/// Application state and actions, kept separate from the widgets that show them.
class AppController extends ChangeNotifier {
  HistoryStore? _history;
  AppDirectories? directories;
  CacheManager? _cacheManager;
  PlayerSettingsStore? _settingsStore;
  ToolManager? _tools;
  VideoRepository? _repository;
  ToolPaths? paths;

  /// 下载: videos saved on this computer; set once ready.
  DownloadManager? downloads;

  Player? player;
  VideoController? videoController;

  int cacheBytes = 0;
  Map<String, DecoderStatus> decodeStates = const {};
  String currentCodec = tr('尚未播放视频');
  String currentHwdec = tr('尚未验证');
  WindowsVideoInfo windowsVideoInfo = const WindowsVideoInfo();
  PlayerSettings settings = const PlayerSettings();
  VideoItem? playing;
  PageMode mode = PageMode.home;
  bool ready = false;
  bool checking = false;
  /// Lumtub's own updates; null until the components are ready.
  AppUpdater? appUpdater;
  String status = tr('正在准备 Windows 原生播放器…');
  /// Startup failure; the setup screen shows it with a retry button.
  String? error;
  String? playbackError;
  /// Whether [playbackError] is a live stream that has not started yet and
  /// is retried by itself.
  bool get waitingForStart => playbackError != null && _waitingForStart;
  bool _waitingForStart = false;

  /// When the stream being played is scheduled to start, if it has not.
  DateTime? get scheduledStart => playing?.scheduledStart ?? details?.scheduledStart;

  /// Favorites, playlists, followed channels and progress; set once ready.
  LibraryController? library;

  /// The optional Google sign-in for importing subscriptions and playlists.
  AccountController? account;

  /// The TV-code sign-in that YouTube's own pages take, for liking comments
  /// and posts.
  YoutubeTvSignIn? tvSignIn;

  /// The cookie sign-in, for liking posts, voting in polls and writing
  /// under posts, which the TV-code sign-in cannot reach.
  YoutubeWebSignIn? webSignIn;

  /// The account's own YouTube pages, read with [tvSignIn].
  YoutubeTvFeed? tvFeed;

  /// The account's YouTube playlists, once read; empty when signed out.
  List<PlaylistResult> tvPlaylists = const [];
  bool tvPlaylistsLoading = false;

  /// The account's YouTube watch history, while 观看历史 shows it.
  VideoListLoader? youtubeHistory;

  /// The open channel page and its uploads.
  ChannelRef? channel;
  VideoListLoader? channelVideos;
  /// What the channel page is searching for; null lists the uploads.
  String? channelQuery;
  /// The id of the open playlist page: a [LocalPlaylist] id, or
  /// [favoritesPlaylistId].
  String? openPlaylistId;
  static const favoritesPlaylistId = 'favorites';
  /// 稍后观看 opens on the same page as a playlist.
  static const watchLaterPlaylistId = 'watch_later';
  /// Where 返回 goes: earlier pages and videos.
  final _back = BackStack();
  /// Set while going back, so the step back is not itself remembered.
  bool _restoring = false;

  /// The open YouTube playlist and its videos.
  PlaylistResult? youtubePlaylist;
  VideoListLoader? youtubePlaylistVideos;

  /// The channel page's tab, and its posts when that tab is open.
  ChannelTab channelTab = ChannelTab.videos;
  PostsLoader? channelPosts;
  late final _posts = CommunityPosts(_http, signIn: comments);

  /// Comments under videos and posts, and liking them and posts, signed in
  /// with the TV code when there is one.
  late final comments = YoutubeComments(_http);

  /// Whether the statistics overlay is shown over the video.
  bool showStats = false;

  void toggleStats() => _update(() => showStats = !showStats);

  /// 置顶: the window stays above the others.
  bool pinned = false;
  /// 画中画: a small borderless window above the others, showing only the
  /// video in its own ratio (ui/pip_view.dart).
  bool pip = false;
  /// 应用内小窗: [playing] keeps playing in a floating card over the other
  /// pages instead of on the watch page (ui/mini_player.dart).
  bool mini = false;
  /// 听视频: mpv decodes no picture, which saves power and bandwidth.
  bool audioOnly = false;

  void togglePinned() {
    if (!AppWindow.setTopmost(!pinned || pip)) return _notice(tr('无法设置窗口置顶'));
    _update(() => pinned = !pinned);
  }

  /// Whether the watch page shows [playing].
  bool get onWatchPage => playing != null && !mini;

  /// Whether leaving the watch page now keeps the video in the mini player.
  bool get _keepsPlaying =>
      playing != null && (mini || (preferences.miniPlayer && player != null && playbackError == null));

  /// Shows [playing] on the watch page again, where it was.
  void expandMini() {
    if (mini) _update(() => mini = false);
  }

  /// Puts the video on the watch page into the mini player (the 应用内小窗
  /// button), over the page it was opened from.
  void enterMini() {
    if (playing == null || mini || player == null) return;
    setPip(false);
    _saveProgress(now: true);
    _update(() => mini = true);
  }

  void setPip(bool on) {
    if (on == pip) return;
    final ok = on ? AppWindow.enterPip(aspect: videoAspect) : AppWindow.exitPip(keepOnTop: pinned);
    if (on && !ok) return _notice(tr('无法进入画中画'));
    _update(() => pip = on);
  }

  VideoOutputSize? _outputSize;

  /// [owner] shows the video in [box], in physical pixels; libmpv draws it
  /// at the size of the largest place it is shown.
  void showVideoIn(Object owner, Size box) => _outputSize?.show(owner, box);

  /// [owner] no longer shows the video.
  void hideVideoIn(Object owner) => _outputSize?.hide(owner);

  /// Whether the picture is zoomed or stretched to fill the player.
  set coverVideo(bool value) => _outputSize?.cover = value;

  /// The playing video's width over height, 16:9 until it is known.
  double get videoAspect {
    final state = player?.state;
    final width = state?.width ?? 0, height = state?.height ?? 0;
    return width > 0 && height > 0 ? width / height : 16 / 9;
  }

  /// The next video may have another ratio: the picture-in-picture window
  /// follows it.
  void updatePipAspect() {
    if (pip) AppWindow.setPipAspect(videoAspect);
  }

  Future<void> toggleAudioOnly() async {
    final platform = player?.platform;
    if (platform is! NativePlayer) return;
    await platform.setProperty('vid', audioOnly ? 'auto' : 'no');
    _update(() => audioOnly = !audioOnly);
    _notice(audioOnly ? tr('只听声音，不解码画面') : tr('已恢复画面'));
  }

  Future<void> toggleSponsorBlock() async {
    await saveSettings(settings.copyWith(sponsorBlock: !settings.sponsorBlock));
    _notice(settings.sponsorBlock ? tr('已开启 SponsorBlock 跳过片段') : tr('已关闭 SponsorBlock'));
  }

  /// Videos like the one playing, found by searching for its title.
  VideoListLoader? related;

  /// The list the current video was opened from, shown as the play queue.
  List<VideoItem> queue = const [];
  /// Videos lined up by hand; they play before [upNext].
  final playQueue = PlayQueue();
  VideoDetails? details;
  bool loadingDetails = false;
  List<LiveChatMessage> replayChat = const [];

  /// Fires when a live chat gains messages, which happens several times a
  /// second: only the chat panel listens, not the whole app.
  final chatMessages = ValueNotifier(0);
  bool loadingReplayChat = false;
  String? replayChatError;
  StreamSubscription<LiveChatMessage>? _currentChat;
  Timer? _currentChatFlushTimer;
  final _currentChatPending = <LiveChatMessage>[];
  final _currentChatIds = <String>{};
  /// Heights the playing video offers, highest first; empty until known.
  List<int> availableHeights = const [];
  /// Heights for the quality menu: automatic, then only what the playing
  /// video offers (just automatic until that is known).
  List<int> get qualityChoices => [0, ...({...availableHeights}.toList()..sort((a, b) => b.compareTo(a)))];

  /// The video opened from addresses resolved ahead of libmpv, if any.
  String? _openedResolved;
  /// The video last opened from a Piped or Invidious server, so a failure
  /// falls back to YouTube (or the other one) once.
  String? _openedVia;
  String? _openedOrigin;
  /// The video playing from its downloaded file, if any.
  String? _openedLocal;
  /// The servers tried for the video being opened, and the 429 YouTube
  /// answered it with, which lets both be tried whatever 播放来源 says.
  final _relaysTried = <RelayKind>{};
  /// What YouTube said when it would not play the video, so Piped and
  /// Invidious stand in for it.
  PlaybackFailure? _youtubeRefused;
  late final _piped = PipedStreams(_http);
  late final _invidious = InvidiousStreams(_http);

  /// The TV or Chromecast the video is cast to, if any.
  final cast = CastController();

  /// What to cast of [playing]: one progressive mp4 with sound, from the
  /// yt-dlp extraction or else from a Piped or Invidious server.
  Future<CastMedia> castMedia(Duration start) async {
    final item = playing;
    if (item == null || item.isLive || _repository == null) throw CastException(tr('没有可以投屏的视频流（需要带声音的 MP4 地址）'));
    CastSource? source;
    try {
      source = castSourceFromYtDlp((await _repository!.streams.resolve(item.id, _format, formatSort: _formatSort)).info, settings: _playback);
    } catch (e) {
      logInfo('Cast: yt-dlp could not resolve: $e');
    }
    for (final kind in RelayKind.values) {
      if (source != null) break;
      try {
        source = castSourceFromRelay(await (kind == RelayKind.piped ? _piped.fetch(item.id) : _invidious.fetch(item.id)), settings: _playback);
      } catch (e) {
        logInfo('Cast: $kind could not resolve: $e');
      }
    }
    if (source == null) throw CastException(tr('没有可以投屏的视频流（需要带声音的 MP4 地址）'));
    final title = details?.title.isNotEmpty == true ? details!.title : item.title;
    return CastMedia(url: source.url, title: title, mime: source.mime, start: start);
  }

  /// The Piped servers, for 设置 › Piped 服务器.
  PipedStreams get piped => _piped;
  /// The Invidious instances, for 设置 › Invidious 实例.
  InvidiousStreams get invidious => _invidious;
  /// Serves YouTube streams to libmpv in pieces YouTube does not throttle.
  StreamRelay? _relay;

  /// lumtub_core's relay, or the Dart one when it cannot start; null when
  /// neither can, and streams connect directly.
  Future<StreamRelay?> _startRelay() async {
    for (final relay in [if (NativeCore.instance case final core?) NativeRelay(core), ChunkedRelay()]) {
      try {
        await relay.start();
        if (relay is ChunkedRelay) logInfo('Using the Dart chunked relay');
        return relay;
      } catch (e) {
        logError('Could not start the local chunked relay', e);
      }
    }
    logInfo('Streams connect directly');
    return null;
  }

  AppearanceSettings appearance;
  final AppearanceSettingsStore? _appearanceStore;
  /// The Windows accent colour, once read, for [AppearanceSettings.systemAccent].
  Color? windowsAccent;

  AppPreferences preferences = const AppPreferences();
  AppPreferencesStore? _preferencesStore;

  AppController({this.appearance = const AppearanceSettings(), AppearanceSettingsStore? appearanceStore}) : _appearanceStore = appearanceStore {
    deArrow.configure(_http, titles: () => settings.deArrowTitles, thumbnails: () => settings.deArrowThumbnails);
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
  final _playerSubscriptions = <StreamSubscription<Object?>>[];
  double _volumeBeforeMute = 100;
  bool _libmpvConfirmed = false;
  /// The video whose position is being recorded; null while switching, so
  /// positions of the previous file are not credited to the next.
  VideoItem? _tracking;
  DateTime _lastProgressSave = DateTime(0);
  List<SkipSegment> _segments = const [];
  final _skipped = <SkipSegment>{};
  final _http = appHttpClient();
  /// Sprite sheets of the progress bar's preview frames.
  late final storyboardSheets = StoryboardSheets(_http);
  late final _google = GoogleTranslator(_http);
  /// Translations already made, kept for a week in the cache folder.
  TranslationCache _translationCache = TranslationCache();
  /// Behind 翻译 buttons and translated subtitles: the service 翻译服务
  /// names; called only when something is to be translated.
  late Translator translator = CachingTranslator(_google, _translationCache, preferences.translation.cacheScope);
  /// The translation services' API keys, by [TranslationService.name],
  /// kept encrypted with DPAPI apart from the settings.
  Map<String, String> translationKeys = const {};
  SecureJsonFile? _translationKeyFile;
  /// The subtitle shown above the main one (双语字幕), if any.
  SubtitleOption? secondarySubtitle;
  /// The second subtitle being fetched or translated, shown as loading in
  /// the 字幕 panel rather than as 关闭.
  SubtitleOption? secondaryLoading;
  /// The video 第二字幕语言 was applied to, so a secondary subtitle turned
  /// off stays off.
  String? _secondaryAutoFor;
  bool _decoderPending = false;
  int _mpvLogLines = 0;
  /// yt-dlp and libmpv error lines for the video being opened, which name
  /// the cause libmpv's own error message usually leaves out.
  final _recentErrors = <String>[];

  /// No prefetching until then, after YouTube answered 429.
  DateTime _rateLimitedUntil = DateTime(0);
  bool _updateCheckedForChallenge = false;
  int _lastDrops = 0;
  /// Ten-second windows in a row that dropped a tenth of the frames or more.
  int _dropStreak = 0;
  /// The quality automatic playback is lowered to for this run after
  /// frames kept dropping; 0 while it is not.
  int _droppedCap = 0;
  DateTime _lastDropLog = DateTime(0);
  DateTime _lastFrameLog = DateTime(0);
  Timer? _dropTimer;
  Timer? _thumbnailTrimTimer;
  final _recovery = PlaybackRecovery();
  /// The last position actually played, which survives a failed stream.
  Duration _lastPosition = Duration.zero;
  final _resumePoint = ResumePoint();
  String? _relayed;
  String? _unrelayed;
  Timer? _stallTimer;
  Timer? _recoveryTimer;
  Timer? _startTimer;
  int _startAttempts = 0;
  bool _recovering = false;
  bool _shutDown = false;
  late final _sponsorBlock = SponsorBlock(_http);
  late final _returnDislike = ReturnDislike(_http);
  /// Each channel's last speed and volume; see [ChannelPlayback].
  ChannelPlayback? channelPlayback;
  /// 语音识别 subtitles made for videos that had none, kept on this computer.
  SpeechSubtitleStore? speechStore;
  /// The 语音识别 running now: the video, what it is doing, parts done of
  /// how many. Its own notifier, so progress repaints only what shows it.
  final speechJob = ValueNotifier<({String videoId, String stage, int done, int total})?>(null);
  /// 观看统计's watch time.
  WatchTime? watchTime;
  /// The channel whose speed and volume changes are remembered now; null
  /// while a video opens and its own settings are applied.
  String? _playbackChannel;
  /// The volume a channel with none of its own plays at: the last chosen.
  double? _sessionVolume;
  /// Playing time not yet added to [watchTime], and when it was counted.
  int _watchMs = 0;
  DateTime? _watchTick;
  /// Return YouTube Dislike's estimate for the video playing, when on.
  DislikeCount? dislikes;
  bool _disposed = false;
  final _notices = StreamController<String>.broadcast();

  /// One-off messages the UI shows as snack bars.
  Stream<String> get notices => _notices.stream;
  final _finishedDownloads = StreamController<DownloadTask>.broadcast();
  /// Downloads as they finish, for a notice that can open the file.
  Stream<DownloadTask> get finishedDownloads => _finishedDownloads.stream;

  List<VideoItem> get history => _history?.items ?? const [];
  @visibleForTesting
  set historyStore(HistoryStore? store) => _history = store;

  /// The text of the current or last search, if any.
  String? get query => _query;

  /// The current search's results; null before the first search.
  VideoListLoader? searchResults;
  SearchFilter searchFilter = SearchFilter.all;

  List<VideoItem> get results => searchResults?.items ?? const [];
  /// The search's channels, without blocked groups unless one is named
  /// exactly.
  List<ChannelResult> get channelResults => [
        for (final c in searchResults?.channels ?? const <ChannelResult>[])
          if (!preferences.isBlocked(c.ref.id) && !preferences.isBlockedName(c.ref.name) && (!preferences.blocksChannel(c.ref.name, id: c.ref.id, handle: c.handle) || isExactName(c.ref.name, _query) || isExactName(c.handle ?? '', _query))) c,
      ];
  List<PlaylistResult> get playlistResults => [
        for (final p in searchResults?.playlists ?? const <PlaylistResult>[])
          if (!preferences.isBlockedName(p.channel) && (!preferences.blocksChannel(p.channel) || isExactName(p.channel, _query))) p,
      ];
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

  /// What asked for the window to be rebuilt since the frame log last
  /// took the counts: a part of the app by name, or `app` for the rest.
  final rebuildCauses = <String, int>{};
  final _passers = <String, VoidCallback>{};

  @override
  void notifyListeners() {
    rebuildCauses.update('app', (n) => n + 1, ifAbsent: () => 1);
    super.notifyListeners();
  }

  /// Passes on a change of the part named [cause], counted under its name.
  /// The same callback comes back for a name, so it can be removed again.
  /// A part only one page shows does not rebuild the window while another
  /// is open; going to that page rebuilds it with what the part has then.
  VoidCallback _passOn(String cause) => _passers[cause] ??= () {
        if (_disposed || !_shows(cause)) return;
        rebuildCauses.update(cause, (n) => n + 1, ifAbsent: () => 1);
        super.notifyListeners();
      };

  bool _shows(String cause) {
    bool page(PageMode shown) => !onWatchPage && mode == shown;
    return switch (cause) {
      'home feed' => page(PageMode.home),
      'channel' => page(PageMode.channel),
      'related' => onWatchPage,
      'search' || 'explore' => page(PageMode.explore),
      'youtube history' => page(PageMode.history),
      _ => true,
    };
  }

  /// Settings › Google 账号 › 保存电视版样本.
  Future<String> saveTvSamples() async {
    final sign = tvSignIn;
    final logs = directories?.logs;
    if (sign == null || !sign.signedIn || logs == null) return tr('需要先在设置 › YouTube 账号里用电视码登录');
    return tv_samples.saveTvSamples(sign, logs);
  }

  bool _tvWasSignedIn = false;

  int _webSignIns = 0;

  void _webSignInChanged() {
    final web = webSignIn;
    // A new sign-in is tried again even after YouTube refused the old one.
    if (web != null && web.signIns != _webSignIns) {
      _webSignIns = web.signIns;
      comments.webRefused = false;
    }
    notifyListeners();
  }

  void _tvSignInChanged() {
    final signedIn = tvSignIn?.signedIn ?? false;
    if (signedIn) comments.refused = false;
    if (signedIn != _tvWasSignedIn) {
      _tvWasSignedIn = signedIn;
      youtubeHistory?.dispose();
      youtubeHistory = null;
      tvPlaylists = const [];
      _tvPlaylistsRead = false;
      // Signed in just now: YouTube's own suggestions join the feed.
      if (signedIn && homeFeed != null) unawaited(refreshHomeFeed(force: true, keep: true));
    }
    notifyListeners();
  }

  bool _tvPlaylistsRead = false;

  /// Reads the account's YouTube playlists the first time 播放列表 shows.
  void ensureTvPlaylists() {
    if (_tvPlaylistsRead || !(tvFeed?.available ?? false)) return;
    _tvPlaylistsRead = true;
    unawaited(loadTvPlaylists());
  }

  /// Reads the account's YouTube playlists again.
  Future<void> loadTvPlaylists() async {
    final feed = tvFeed;
    if (feed == null || !feed.available || tvPlaylistsLoading) return;
    tvPlaylistsLoading = true;
    notifyListeners();
    try {
      final found = await feed.accountPlaylists();
      if (feed.available) tvPlaylists = found;
    } catch (e) {
      logInfo('Could not read the YouTube playlists: $e');
    } finally {
      tvPlaylistsLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// 观看历史 › YouTube: the account's history on YouTube, loaded the first
  /// time it is shown.
  VideoListLoader? openYoutubeHistory({bool reload = false}) {
    final feed = tvFeed;
    if (feed == null || !feed.available) return null;
    if (reload) {
      youtubeHistory?.dispose();
      youtubeHistory = null;
    }
    return youtubeHistory ??= VideoListLoader(() => Listing(() => feed.lines(YoutubeTvFeed.history)), pageSize: 40, name: 'YouTube history')
      ..addListener(_passOn('youtube history'))
      ..loadMore();
  }

  /// Whether [playlist] is the account's own, read signed in.
  bool _isAccountPlaylist(PlaylistResult playlist) =>
      playlist.id == YoutubeTvFeed.watchLaterId || tvPlaylists.any((list) => list.id == playlist.id);

  void _notice(String message) {
    if (!_disposed) _notices.add(message);
  }

  Timer? _afterStart;

  /// 无痕模式: nothing watched or searched is remembered (history, search
  /// history, progress, what 为你推荐 learns, translations kept on disk)
  /// until it is turned off or Lumtub closes. Not saved, so every start is
  /// normal.
  bool incognito = false;

  void setIncognito(bool value) {
    if (value == incognito) return;
    _update(() => incognito = value);
    _translationCache.persist = !value;
    _notice(value ? tr('已开启无痕模式：这次看过、搜过的内容都不会被记下') : tr('已关闭无痕模式'));
    logInfo(value ? 'Incognito on' : 'Incognito off');
  }

  Future<void> initialize() async {
    try {
      final directories = await AppDirectories.create();
      // yt-dlp, including the one libmpv starts, writes some temporary
      // files (format tests) to the working folder, which is the install
      // folder and read-only under Program Files.
      try {
        Directory.current = directories.cache;
      } catch (_) {}
      await AppLog.open(directories.logs);
      logInfo('Lumtub $appVersion started · ${Platform.operatingSystemVersion}');
      final history = HistoryStore(directories);
      searchHistory = SearchHistory(File('${directories.data.path}${Platform.pathSeparator}search_history.json'));
      final notInterested = NotInterested(File('${directories.data.path}${Platform.pathSeparator}not_interested.json'));
      final libraryStore = LibraryStore(File('${directories.data.path}${Platform.pathSeparator}library.json'));
      final channelPlayback = ChannelPlayback(File('${directories.data.path}${Platform.pathSeparator}channel_playback.json'));
      final watchTime = WatchTime(File('${directories.data.path}${Platform.pathSeparator}watch_time.json'));
      final settingsStore = PlayerSettingsStore(directories);
      final preferencesStore = AppPreferencesStore(directories);
      // Separate files: read together rather than one after another.
      final (_, _, _, settings, preferences, _, _) = await (history.initialize(), notInterested.load(), libraryStore.load(), settingsStore.load(), preferencesStore.load(), channelPlayback.load(), watchTime.load()).wait;
      this.channelPlayback = channelPlayback;
      this.watchTime = watchTime;
      speechStore = SpeechSubtitleStore(Directory('${directories.data.path}${Platform.pathSeparator}speech'));
      homeFeed = HomeFeed(notInterested, cacheFile: File('${directories.cache.path}${Platform.pathSeparator}home_feed.json'))..addListener(_passOn('home feed'));
      this.settings = settings;
      final cacheManager = CacheManager(directories);
      final manager = ToolManager(directories, (message, logged) {
        logInfo(logged);
        _update(() => status = message);
      });
      _tools = manager;
      // The proxy comes before the component downloads, which use it too.
      await (_refreshProxy(), cacheManager.prepare(settings), manager.initialize()).wait;
      final paths = await manager.ensureReady();
      addToWindowsPath(paths.executableDirectories);
      MediaKit.ensureInitialized(libmpv: paths.mpv);
      final player = Player(configuration: PlayerConfiguration(
        bufferSize: settings.cacheMemoryMb * 1024 * 1024,
        // With libass, libmpv draws the subtitles and the Flutter subtitle
        // view is turned off on the watch page. It is off by default: the
        // build that turned it on for everyone also brought dropped frames.
        libass: settings.libassSubtitles,
        logLevel: MPVLogLevel.warn,
      ));
      final ignoredOptions = await PlayerOptionApplicator.apply(player, settings);
      // Compiled shaders are kept between runs, so a video's first frame
      // does not wait for them again.
      final platform = player.platform;
      if (platform is NativePlayer) {
        final shaders = Directory('${directories.cache.path}${Platform.pathSeparator}shaders');
        try {
          shaders.createSync(recursive: true);
          await platform.setProperty('gpu-shader-cache-dir', shaders.path);
        } catch (_) {}
      }
      _lightRendering = null;
      await _applyProxy(player);
      _relay = await _startRelay();
      _piped.catalogFile = File('${directories.config.path}${Platform.pathSeparator}piped_servers.json');
      // Measures the Piped servers while the app starts, not on the first click.
      _invidious.catalogFile = File('${directories.config.path}${Platform.pathSeparator}invidious_servers.json');
      switch (settings.playbackSource) {
        case PlaybackSource.pipedAuto:
          unawaited(_piped.servers());
        case PlaybackSource.invidiousAuto:
          unawaited(_invidious.servers());
        default:
      }
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
        cacheBytes = 0;
        _settingsStore = settingsStore;
        this.settings = settings;
        _preferencesStore = preferencesStore;
        this.preferences = preferences;
        mode = PageMode.values.where((m) => m.name == preferences.startPage).firstOrNull ?? PageMode.home;
        decodeStates = {...settings.decoderResults};
        _history = history;
        _repository = _repositoryFor(paths, cacheManager, settings);
        downloads = _downloadsFor(paths, directories)..addListener(_passOn('downloads'));
        final library = this.library = LibraryController(libraryStore, client: _http)
          ..repository = _repository
          ..addListener(_passOn('library'));
        account = AccountController(
          clientFile: File('${directories.data.path}${Platform.pathSeparator}google-client.json'),
          credentials: SecureJsonFile(File('${directories.data.path}${Platform.pathSeparator}google-account.bin'), DpapiProtector()),
          client: _http,
          library: library,
          notice: _notice,
        )..addListener(_passOn('account'));
        final tv = tvSignIn = YoutubeTvSignIn(folder: directories.data.path)..addListener(_tvSignInChanged);
        comments.signIn = tv;
        final web = webSignIn = YoutubeWebSignIn(folder: directories.data.path)..addListener(_webSignInChanged);
        comments.web = web;
        web.load();
        tvFeed = YoutubeTvFeed(tv);
        // Before the first home feed, which mixes in YouTube's own.
        tv.load();
        _tvWasSignedIn = tv.signedIn;
        this.player = player;
        _outputSize = VideoOutputSize((width, height) async => videoController?.setSize(width: width, height: height));
        _listenTo(player);
        _dropTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkDrops());
        _thumbnailTrimTimer?.cancel();
        _thumbnailTrimTimer = Timer.periodic(const Duration(hours: 1), (_) => _trimThumbnails());
        ready = true;
        status = ignoredOptions.isEmpty ? tr('就绪 · 解码方式将在播放时验证') : tr('就绪 · 已忽略不支持的设置：{0}', [ignoredOptions.join(', ')]);
        error = null;
      });
      if (mode == PageMode.explore) _loadExplore();
      if (mode == PageMode.home) unawaited(refreshHomeFeed());
      final updater = AppUpdater(client: _http, directory: Directory('${directories.cache.path}${Platform.pathSeparator}updates'), download: manager.downloadVerified)..addListener(_passOn('updater'));
      appUpdater = updater;
      // Housekeeping waits until the first page has loaded and drawn, so
      // update checks and folder scans do not compete with it.
      unawaited(_warmUp(player));
      _afterStart = Timer(const Duration(seconds: 8), () {
        if (_disposed) return;
        if (preferences.autoCheckUpdates) unawaited(manager.checkUpdates());
        if (preferences.autoCheckUpdates || preferences.autoUpdateApp) updater.start(download: () => preferences.autoUpdateApp);
        unawaited(_refreshCacheSize());
        unawaited(_trimThumbnails());
      });
      unawaited(downloads?.load());
      unawaited(account?.load());
      _translationCache = TranslationCache(file: File('${directories.cache.path}${Platform.pathSeparator}translations.json'));
      _useTranslator();
      _translationKeyFile = SecureJsonFile(File('${directories.data.path}${Platform.pathSeparator}translation-keys.bin'), DpapiProtector());
      unawaited(_loadTranslationKeys());
      logInfo('Components ready · libmpv ${manager.libmpv.current?.label ?? 'bundled'} · yt-dlp ${manager.ytDlpVersion ?? '?'} · ${paths.mpv}');
    } catch (e) {
      _update(() {
        error = e.toString();
        status = tr('初始化失败');
        logError('Initialization failed', e);
      });
    }
  }

  /// Checks for a new Lumtub now and downloads it, for the settings page.
  Future<void> checkAppUpdate() async => appUpdater?.check(download: AppUpdater.canInstall);

  /// Closes Lumtub, installs the downloaded update and starts it again.
  Future<void> restartToUpdate() async {
    final updater = appUpdater;
    if (updater == null || updater.ready == null) return;
    // The installer starts first and waits for Lumtub to end, so a declined
    // administrator prompt leaves Lumtub running as it was.
    if (!await updater.install(relaunch: true)) return;
    await shutdown(install: false);
    exit(0);
  }

  /// Keeps the thumbnail cache under its cap, at startup and then hourly;
  /// skipped while a video plays.
  Future<void> _refreshCacheSize() async {
    final manager = _cacheManager;
    if (manager == null) return;
    try {
      final bytes = await manager.size(settings);
      if (!_disposed) _update(() => cacheBytes = bytes);
    } on FileSystemException catch (error) {
      logInfo('Could not measure cache size: $error');
    }
  }

  Future<void> _trimThumbnails() async {
    final directory = thumbnailDirectory;
    if (_disposed || directory == null || playing != null) return;
    try {
      final freed = await trimThumbnails(directory, thumbnailCapBytes(settings.cacheLimitGb));
      if (freed > 0) {
        logInfo('Thumbnail cache over its limit, freed ${formatBytes(freed)}');
        final manager = _cacheManager;
        if (manager != null) {
          final left = await manager.size(settings);
          _update(() => cacheBytes = left);
        }
      }
    } catch (e) {
      logInfo('Could not trim the thumbnail cache: $e');
    }
  }

  void retryInitialize() {
    _update(() {
      error = null;
      status = tr('重新安装组件…');
    });
    unawaited(initialize());
  }

  VideoRepository _repositoryFor(ToolPaths paths, CacheManager cacheManager, PlayerSettings settings) =>
      VideoRepository(
        paths.ytDlp,
        cacheDirectory: '${cacheManager.rootFor(settings).path}${Platform.pathSeparator}yt-dlp',
        deno: paths.deno,
        toolDirectories: paths.executableDirectories,
        proxy: () => proxy.ytDlpValue(this.settings.proxyMode),
        client: _http,
      );

  DownloadManager _downloadsFor(ToolPaths paths, AppDirectories directories) => DownloadManager(
        file: File('${directories.data.path}${Platform.pathSeparator}downloads.json'),
        ytDlpPath: paths.ytDlp,
        onFinished: (task) {
          if (!_disposed) _finishedDownloads.add(task);
        },
        defaultDirectory: DownloadManager.defaultDirectoryFor(Platform.environment, '${directories.data.path}${Platform.pathSeparator}downloads'),
        environment: () => _repository!.processEnvironment,
        ffmpegDirectory: () {
          final env = _repository!.processEnvironment;
          final path = env.entries.where((e) => e.key.toUpperCase() == 'PATH').firstOrNull?.value;
          return DownloadManager.findFfmpeg([if (_tools?.ffmpegDirectory != null) _tools!.ffmpegDirectory!, ...paths.executableDirectories, '${directories.components.path}${Platform.pathSeparator}ffmpeg'], path);
        },
        options: () => DownloadOptions(
          proxy: proxy.ytDlpValue(settings.proxyMode),
          deno: paths.deno,
          cacheDirectory: _repository?.cacheDirectory,
          subtitleLanguages: settings.subtitleLanguage.ytDlpLangs,
          autoSubtitles: settings.subtitleMode == SubtitleMode.always,
        ),
        sponsorSegments: (id) => _sponsorBlock.segments(id, settings.sponsorCategories),
      );

  /// Queues [item] for download, and says so.
  /// A file name for [item]'s [suffix] (such as `.jpg`) in the download folder.
  String _downloadPath(VideoItem item, String suffix) {
    final title = item.title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').replaceAll(RegExp(r'\s+'), ' ').trim();
    final short = title.length > 120 ? title.substring(0, 120).trim() : title;
    final folder = downloads?.directory ?? Directory.systemTemp.path;
    return '$folder${Platform.pathSeparator}${short.isEmpty ? item.id : short} [${item.id}]$suffix';
  }

  /// Saves [item]'s largest cover image next to the downloads and returns
  /// its path.
  Future<String> saveCover(VideoItem item) async {
    for (final name in const ['maxresdefault', 'sddefault', 'hqdefault']) {
      final http.Response response;
      try {
        response = await _http.get(Uri.https('i.ytimg.com', '/vi/${item.id}/$name.jpg')).timeout(const Duration(seconds: 20));
      } catch (_) {
        throw StateError(tr('无法下载封面，请检查网络或代理'));
      }
      // YouTube answers a missing size with a small placeholder or 404.
      if (response.statusCode != 200 || response.bodyBytes.length < 2000) continue;
      final file = File(_downloadPath(item, '.jpg'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);
      return file.path;
    }
    throw StateError(tr('这个视频没有封面'));
  }

  /// The subtitles [item] offers, with the one translated into 第一字幕语言
  /// when the video has none in it.
  Future<List<SubtitleOption>> subtitleOptionsFor(VideoItem item) async {
    final known = playing?.id == item.id ? details : null;
    final repository = _repository;
    final offered = known?.subtitles ?? (repository == null ? const <SubtitleOption>[] : (await repository.details(item.id)).subtitles);
    final target = settings.subtitleLanguage.translation;
    final translation = hasOwnSubtitle(offered, target) ? null : translationOf(offered, target);
    return [if (translation != null) translation, ...offered.where((o) => o.kind != SubtitleKind.translated)];
  }

  /// Saves [option] of [item] next to the downloads, as SRT or as WebVTT,
  /// and returns its path.
  Future<String> saveSubtitle(VideoItem item, SubtitleOption option, {bool srt = true}) async {
    final vtt = await File(await _subtitleFiles.wholePathFor(option)).readAsString();
    final file = File(_downloadPath(item, '.${option.language}.${srt ? 'srt' : 'vtt'}'));
    await file.parent.create(recursive: true);
    await file.writeAsString(srt ? toSrt(parseSubtitleCues(vtt)) : vtt);
    return file.path;
  }

  void download(VideoItem item, DownloadQuality quality, {DownloadSelection? selection}) {
    final manager = downloads;
    if (manager == null || item.isLive || item.isUpcoming) return _notice(tr('直播无法下载'));
    _notice(manager.add(item, quality, selection: selection) == null ? tr('已在下载列表中') : tr('已加入下载'));
  }

  /// The streams [videoId] can be downloaded as, from the extraction the
  /// player shares (one yt-dlp run per video).
  Future<DownloadFormats> downloadFormats(String videoId) async {
    final repository = _repository;
    if (repository == null) throw StateError(tr('组件尚未就绪'));
    final info = (await repository.streams.resolve(videoId, _format, formatSort: _formatSort)).info;
    // Automatic picks follow the playback order, so a download is in a codec
    // this PC decodes well; the quality strategy takes the best picture.
    final preference = settings.strategy == PlaybackStrategy.quality ? const <VideoCodec>[] : FormatPolicy.codecOrder(settings);
    return DownloadFormats.parseInBackground(info, preference: preference);
  }

  /// The proxy everything currently goes through.
  NetworkProxy proxy = NetworkProxy.direct;
  DateTime _proxyRead = DateTime(0);

  /// Reads the proxy setting again; for 跟随系统 also the Windows proxy,
  /// which a proxy tool may have turned on or off since.
  Future<void> _refreshProxy({bool ifStale = false}) async {
    final now = DateTime.now();
    if (ifStale && now.difference(_proxyRead) < const Duration(seconds: 30)) return;
    _proxyRead = now;
    final next = await NetworkProxy.resolve(settings.proxyMode, settings.proxyAddress);
    await _routeThroughBridge(next);
    appHttpOverrides.endpoint = proxyEndpoint;
    appHttpOverrides.useEnvironment = settings.proxyMode == ProxyMode.system;
    NativeHttp.configure(
      proxy: nativeProxy(next.url),
      system: settings.proxyMode == ProxyMode.system,
      dns: DnsServer.of(settings.dnsServer, settings.dnsCustomUrl),
    );
    if (next.url != proxy.url) logInfo(next.url == null ? 'Network: direct connection' : 'Network: using proxy ${next.redacted}');
    proxy = next;
    final player = this.player;
    if (player != null) await _applyProxy(player);
  }

  SocksBridge? _bridge;
  String? _bridgeFor;

  /// `host:port` of the HTTP proxy libmpv and dart:io use: the proxy itself,
  /// or the local bridge to a SOCKS one. A SOCKS proxy whose bridge could
  /// not start gets a dead port, so requests fail instead of going direct.
  String? proxyEndpoint;

  /// Starts, replaces or stops the bridge so it matches [next].
  Future<void> _routeThroughBridge(NetworkProxy next) async {
    final old = _bridge;
    if (next.isSocks && next.url == _bridgeFor && old != null) return;
    _bridge = null;
    _bridgeFor = next.url;
    if (next.isSocks) {
      try {
        _bridge = await SocksBridge.start(next.url!);
      } catch (e) {
        logError('Could not start the local SOCKS bridge; requests will fail rather than go direct', e);
      }
    }
    proxyEndpoint = next.isSocks ? (_bridge?.hostPort ?? '127.0.0.1:1') : next.isHttp ? next.hostPort : null;
    await old?.close();
  }

  /// libmpv's streams can only use an HTTP proxy.
  Future<void> _applyProxy(Player player) async {
    final platform = player.platform;
    if (platform is NativePlayer) await platform.setProperty('http-proxy', proxyEndpoint == null ? '' : 'http://$proxyEndpoint');
  }

  Future<void> search(String value, {SearchFilter? filter}) async {
    final query = value.trim();
    if (query.isEmpty || !ready) return;
    final asUrl = parseYoutubeId(query);
    if (asUrl != null) {
      await play(VideoItem(id: asUrl, title: tr('YouTube 视频 · {0}', [asUrl]), channel: 'YouTube', url: 'https://www.youtube.com/watch?v=$asUrl'));
      return;
    }
    if (query != _query || mode != PageMode.explore || onWatchPage) _remember();
    final keep = _keepsPlaying;
    if (!keep) _unload();
    final repository = _repository!;
    final chosen = filter ?? searchFilter;
    if (preferences.recordHistory && !incognito) unawaited(searchHistory?.add(query));
    final sp = searchParams(type: chosen, sort: searchSort, date: searchDate, duration: searchDuration);
    _update(() {
      mode = PageMode.explore;
      if (keep) {
        mini = true;
      } else {
        playing = null;
      }
      _query = query;
      searchFilter = chosen;
      searchResults?.dispose();
      searchResults = VideoListLoader(() => sp == null ? repository.search(query) : repository.search(query, sp: sp))
        ..addListener(_passOn('search'))
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

  /// The explore page: its part, zone, sub-category (0 for all of the
  /// zone) and the sub-category's own (0 for all of it), how videos are
  /// picked, and the filters.
  ExploreSection exploreSection = ExploreSection.popular;
  int exploreTopic = 0;
  int exploreSub = 0;
  int exploreLeaf = 0;
  ExploreMode exploreMode = ExploreMode.popular;
  SearchUploadDate explorePeriod = SearchUploadDate.month;
  SearchDuration exploreDuration = SearchDuration.any;
  SearchQuality exploreQuality = SearchQuality.any;
  /// The 类型 and 视角 filters: 宗教与信仰's own lists there, general ones
  /// elsewhere ([exploreFormats], [exploreViews]).
  WordFilter exploreFormat = ContentFormat.any;
  WordFilter exploreView = ContentView.any;

  static List<WordFilter> formatsOf(ExploreSection section) => section.isFaith ? FaithFormat.values : ContentFormat.values;
  static List<WordFilter> viewsOf(ExploreSection section) => section.isFaith ? FaithView.values : ContentView.values;
  List<WordFilter> get exploreFormats => formatsOf(exploreSection);
  List<WordFilter> get exploreViews => viewsOf(exploreSection);
  /// The chosen zone's videos.
  VideoListLoader? explore;

  /// Every zone of [section], built in and the user's, in no set order.
  List<ExploreTopic> allExploreTopics(ExploreSection section) => exploreTopicsOf(section, preferences.exploreCustomTopics);

  /// The zones of [section] the strip shows, in the user's order.
  List<ExploreTopic> exploreTopicsFor(ExploreSection section) => arrangeTopics(
        allExploreTopics(section),
        preferences.exploreOrder[section.name] ?? const [],
        {...?preferences.exploreHidden[section.name]},
      );

  ExploreTopic get exploreTopicNow {
    final topics = exploreTopicsFor(exploreSection);
    return topics[exploreTopic.clamp(0, topics.length - 1)];
  }

  /// The sub-category shown, if one is.
  ExploreSub? get exploreSubNow {
    final subs = exploreTopicNow.subs;
    return exploreSub > 0 && exploreSub <= subs.length ? subs[exploreSub - 1] : null;
  }

  /// The sub-category's own sub-category shown, if one is.
  ExploreSub? get exploreLeafNow {
    final subs = exploreSubNow?.subs ?? const [];
    return exploreLeaf > 0 && exploreLeaf <= subs.length ? subs[exploreLeaf - 1] : null;
  }

  /// The words searched for: the narrowest sub-category's, or the whole
  /// zone's, with 宗教与信仰's filter words.
  String get exploreQuery => [
        (exploreLeafNow ?? exploreSubNow)?.query ?? exploreTopicNow.query,
        exploreFormat.words,
        exploreView.words,
      ].where((w) => w.isNotEmpty).join(' ');

  /// Adds a category of the user's own and shows it.
  Future<void> addExploreTopic(CustomTopic topic) async {
    final kept = preferences.exploreCustomTopics.where((t) => !(t.section == topic.section && t.label == topic.label)).toList();
    final key = topic.topic.key;
    await savePreferences(preferences.copyWith(
      exploreCustomTopics: [...kept, topic],
      exploreHidden: {...preferences.exploreHidden, topic.section.name: [...?preferences.exploreHidden[topic.section.name]]..remove(key)},
    ));
    final index = exploreTopicsFor(topic.section).indexWhere((t) => t.key == key);
    _reloadExplore(section: topic.section, topic: index);
  }

  /// Removes one of the user's categories, keeping the one shown if it stays.
  Future<void> removeExploreTopic(ExploreSection section, String label) async {
    final key = 'custom:$label';
    await _arrangeExplore(section, () => savePreferences(preferences.copyWith(
          exploreCustomTopics: preferences.exploreCustomTopics.where((t) => !(t.section == section && t.label == label)).toList(),
          exploreOrder: {...preferences.exploreOrder, section.name: [...?preferences.exploreOrder[section.name]]..remove(key)},
          exploreHidden: {...preferences.exploreHidden, section.name: [...?preferences.exploreHidden[section.name]]..remove(key)},
        )));
  }

  /// Saves the order and hidden zones of [section] from the manage dialog.
  Future<void> arrangeExploreTopics(ExploreSection section, List<String> order, Set<String> hidden) => _arrangeExplore(
        section,
        () => savePreferences(preferences.copyWith(
          exploreOrder: {...preferences.exploreOrder, section.name: order},
          exploreHidden: {...preferences.exploreHidden, section.name: hidden.toList()},
        )),
      );

  /// Runs [change] and keeps the zone shown if it is still in the strip.
  Future<void> _arrangeExplore(ExploreSection section, Future<void> Function() change) async {
    final shown = exploreTopicNow.key;
    await change();
    if (section != exploreSection) return;
    final index = exploreTopicsFor(section).indexWhere((t) => t.key == shown);
    if (index == exploreTopic) {
      notifyListeners();
    } else if (index >= 0) {
      // Same zone at another place: nothing to load again.
      _update(() => exploreTopic = index);
    } else {
      _reloadExplore(topic: 0);
    }
  }

  void _reloadExplore({ExploreSection? section, required int topic}) {
    explore?.dispose();
    explore = null;
    setExplore(section: section, topic: topic < 0 ? 0 : topic);
  }

  /// Opens the explore page on its topics.
  void openExplore() {
    _remember();
    if (_query != null) {
      _query = null;
      searchResults?.dispose();
      searchResults = null;
    }
    _go(PageMode.explore);
    _loadExplore();
  }

  (ExploreSection, int) _topicBeforeFaith = (ExploreSection.popular, 0);

  /// Leaves 宗教与信仰 for the video zones, on the zone shown before.
  /// 视频 or 直播, whichever 宗教信仰 was opened from while its tabs show.
  ExploreSection get exploreHalf => exploreSection.isFaith ? _topicBeforeFaith.$1 : exploreSection;

  void leaveFaith() {
    final (section, topic) = _topicBeforeFaith;
    final topics = exploreTopicsFor(section);
    final index = topic.clamp(0, topics.length - 1);
    // Not back into 宗教信仰 itself, say when it is pinned first.
    final back = topics[index].opens == null ? index : topics.indexWhere((t) => t.opens == null);
    if (back >= 0) setExplore(section: section, topic: back);
  }

  /// Shows another part, zone, sub-category, mode, period or filter of the
  /// explore page. A new part starts on its first zone, and on its usual
  /// mode unless the one shown also suits it; a new zone on all of it.
  void setExplore({
    ExploreSection? section,
    int? topic,
    int? sub,
    int? leaf,
    ExploreMode? mode,
    SearchUploadDate? period,
    SearchDuration? duration,
    SearchQuality? quality,
    WordFilter? format,
    WordFilter? view,
    ExploreRegion? region,
    ExploreLanguage? language,
  }) {
    if ((region != null && region != preferences.exploreRegion) || (language != null && language != preferences.exploreLanguage)) {
      unawaited(savePreferences(preferences.copyWith(exploreRegion: region, exploreLanguage: language)));
      explore?.dispose();
      explore = null;
    }
    final nextSection = section ?? exploreSection;
    final newSection = nextSection != exploreSection;
    final topics = exploreTopicsFor(nextSection);
    final nextTopic = (topic ?? (newSection ? 0 : exploreTopic)).clamp(0, topics.length - 1);
    // 宗教信仰 among the video zones opens 宗教与信仰's tabs; leaving them
    // goes back to the zone shown before.
    final opens = topics[nextTopic].opens;
    if (opens != null) {
      if (!exploreSection.isFaith) _topicBeforeFaith = (exploreSection, exploreTopic);
      setExplore(section: opens);
      return;
    }
    final nextSub = sub ?? (newSection || nextTopic != exploreTopic ? 0 : exploreSub);
    final nextLeaf = leaf ?? (newSection || nextTopic != exploreTopic || nextSub != exploreSub ? 0 : exploreLeaf);
    final modes = ExploreMode.of(nextSection);
    final sameKind = nextSection.isFaith == exploreSection.isFaith && nextSection.isLive == exploreSection.isLive;
    final nextMode = mode != null && modes.contains(mode)
        ? mode
        : !newSection || (sameKind && modes.contains(exploreMode))
            ? exploreMode
            : ExploreMode.defaultOf(nextSection);
    final nextPeriod = period ?? explorePeriod;
    final nextDuration = duration ?? exploreDuration;
    final nextQuality = quality ?? exploreQuality;
    // A filter of the other kind's list starts over at 不限.
    final formats = formatsOf(nextSection), views = viewsOf(nextSection);
    final nextFormat = format ?? (formats.contains(exploreFormat) ? exploreFormat : formats.first);
    final nextView = view ?? (views.contains(exploreView) ? exploreView : views.first);
    if (!newSection &&
        nextTopic == exploreTopic &&
        nextSub == exploreSub &&
        nextLeaf == exploreLeaf &&
        nextMode == exploreMode &&
        nextPeriod == explorePeriod &&
        nextDuration == exploreDuration &&
        nextQuality == exploreQuality &&
        nextFormat == exploreFormat &&
        nextView == exploreView &&
        explore != null) {
      return;
    }
    _update(() {
      _putAwayExplore();
      exploreSection = nextSection;
      exploreTopic = nextTopic;
      exploreSub = nextSub;
      exploreLeaf = nextLeaf;
      exploreFormat = nextFormat;
      exploreView = nextView;
      exploreMode = nextMode;
      explorePeriod = nextPeriod;
      exploreDuration = nextDuration;
      exploreQuality = nextQuality;
    });
    _loadExplore();
  }

  /// Lists of zones shown lately, so going back to one shows it again
  /// instead of searching anew. 全部 is left out, as each visit brings
  /// others, and so is a list that failed.
  final _recentExplore = <Object, (DateTime, VideoListLoader)>{};
  static const _keepExplore = Duration(minutes: 15);

  Object get _exploreKey => (exploreSection, exploreTopic, exploreSub, exploreLeaf, exploreMode, explorePeriod, exploreDuration, exploreQuality, exploreFormat, exploreView, preferences.exploreRegion, preferences.exploreLanguage);

  void _putAwayExplore() {
    final loader = explore;
    explore = null;
    if (loader == null) return;
    if (exploreTopicNow.mix || loader.error != null) {
      loader.dispose();
      return;
    }
    loader.removeListener(_passOn('explore'));
    final key = _exploreKey;
    final older = _recentExplore.remove(key)?.$2;
    if (older != null && !identical(older, loader)) older.dispose();
    _recentExplore[key] = (DateTime.now(), loader);
    while (_recentExplore.length > 4) {
      _recentExplore.remove(_recentExplore.keys.first)!.$2.dispose();
    }
  }

  void _loadExplore() {
    final repository = _repository;
    if (repository == null || explore != null) return;
    if (exploreTopicNow.opens case final opens?) {
      setExplore(section: opens);
      return;
    }
    if (_recentExplore.remove(_exploreKey) case (final at, final loader)) {
      if (DateTime.now().difference(at) < _keepExplore) {
        logInfo('Explore ${exploreSection.name} · ${exploreTopicNow.label}: shown again from ${DateTime.now().difference(at).inSeconds} s ago');
        _update(() => explore = loader..addListener(_passOn('explore')));
        return;
      }
      loader.dispose();
    }
    final query = exploreQuery;
    final mode = exploreMode;
    final mix = exploreTopicNow.mix;
    // 全球热门 is the same everywhere, whatever region and language are set.
    final global = exploreTopicNow.global;
    final region = global ? null : preferences.exploreRegion.gl;
    final language = global ? ExploreLanguage.any : preferences.exploreLanguage;
    final perChannel = <String, int>{};
    final sp = exploreParams(mode, period: explorePeriod, duration: exploreDuration, quality: exploreQuality);
    final taste = mode == ExploreMode.forYou ? _exploreTaste() : null;
    // The Home and Explore "For You" lists share these choices.  Explore has
    // its own loader, so it must apply the mix here instead of relying on
    // HomeFeed's ranking pass.
    final feedMix = mode == ExploreMode.forYou ? preferences.feedMix : null;
    final notInterested = homeFeed?.notInterested;
    final faith = exploreSection.isFaith ? faithFilter() : null;
    final seen = mix ? {for (final item in history) item.id, ...?homeFeed?.items.map((item) => item.id)} : const <String>{};
    final known = mode == ExploreMode.fresh
        ? {for (final item in history) TasteProfile.channelKey(item), for (final channel in library?.channels ?? const <ChannelRef>[]) channel.id}
        : const <String>{};
    final dropped = <String, int>{};
    bool drop(String why) {
      dropped.update(why, (n) => n + 1, ifAbsent: () => 1);
      return false;
    }

    bool where(VideoItem item) {
      if (notInterested != null && notInterested.videos.contains(item.id)) return drop('not interested');
      // Left out here too, so that hiding them still fills the page.
      if (preferences.blocksGroup(item) || preferences.isUnrecommended(item.channelId)) return drop('blocked');
      // "Don't recommend" is a hard exclusion.  "Fewer" remains in the
      // list, but its score is reduced below in the ranking callback.
      if (feedMix != null && feedMix.penaltyOf(item) == null) return drop('Shorts or vertical');
      if (taste != null && taste.channelAffinity(item) < -0.3) return drop('often skipped channel');
      if (mode == ExploreMode.liveUpcoming && !item.isUpcoming) return drop('not upcoming');
      if (mode == ExploreMode.liveReplay && item.liveStatus != 'was_live') return drop('not a replay');
      final seconds = item.duration;
      if (mode == ExploreMode.gems) {
        final views = item.viewCount;
        if (views == null || views > gemMaxViews || seconds == null || seconds < 240) return drop('not a hidden gem');
      }
      if (mode == ExploreMode.fresh) {
        final views = item.viewCount;
        if (views == null || views > freshMaxViews || seconds == null || seconds < 60) return drop('not new');
        if (known.contains(TasteProfile.channelKey(item))) return drop('known channel');
      }
      if (mode == ExploreMode.curated && seconds != null && seconds < 240) return drop('too short');
      if (!language.matches(item.title)) return drop('language');
      // 全部 is for finding more: not what was watched or what 为你推荐
      // already shows. It keeps any one channel from filling it.
      if (mix && seen.contains(item.id)) return drop('already seen');
      if (mix && (perChannel[TasteProfile.channelKey(item)] = (perChannel[TasteProfile.channelKey(item)] ?? 0) + 1) > 2) return drop('more than 2 per channel');
      // Last, as it counts the videos that show.
      return faith == null || faith(item) || drop('faith filter');
    }

    _update(() => explore = VideoListLoader(
          () => mix ? repository.searchMix(exploreMixQueries(exploreSection), sp: sp, region: region) : repository.search(query, sp: sp, region: region),
          where: where,
          fill: switch (mode) {
            ExploreMode.gems || ExploreMode.fresh || ExploreMode.liveReplay => 8,
            ExploreMode.liveUpcoming => 4,
            _ => faith != null || mix || language != ExploreLanguage.any ? 8 : 1,
          },
          rank: taste == null
              ? null
              : (item) => exploreScore(taste, item) - (feedMix?.penaltyOf(item) ?? 0),
          name: 'Explore ${exploreSection.name} · ${exploreTopicNow.label} · ${mode.name}',
          dropped: dropped,
        )
          ..addListener(_passOn('explore'))
          ..loadMore());
  }

  /// 全部's searches: zones of [section] picked at random each time, so
  /// every visit brings others. Personal picks are left to 为你推荐 on the
  /// home page.
  @visibleForTesting
  List<String> exploreMixQueries(ExploreSection section, {Random? random}) {
    final zones = [
      for (final topic in exploreTopicsFor(section))
        if (!topic.mix && topic.opens == null) topic.subs.isEmpty ? topic.query : (topic.subs.toList()..shuffle(random)).first.query,
    ]..shuffle(random);
    final filter = [exploreFormat.words, exploreView.words].where((w) => w.isNotEmpty).join(' ');
    return [for (final query in zones.take(6)) filter.isEmpty ? query : '$query $filter'];
  }

  /// Shows 全部 or the zone shown with other videos.
  void refreshExplore() {
    explore?.dispose();
    explore = null;
    _loadExplore();
  }

  /// What the history says about taste, for 为你推荐 in a zone.
  TasteProfile _exploreTaste() {
    final library = this.library;
    return TasteProfile.from(
      history: history,
      progressOf: library?.progressOf,
      favorites: [...?library?.favorites, ...?account?.likedVideos.take(50)],
      followed: {for (final c in library?.channels ?? const <ChannelRef>[]) c.id},
      decay: 0.97,
    );
  }

  /// 为你推荐 in a zone: title words and channels like the history's
  /// first, then more viewed.
  static double exploreScore(TasteProfile taste, VideoItem item) {
    final views = item.viewCount ?? 0;
    return 0.55 * taste.titleMatch(item) + 0.35 * max(0.0, taste.channelAffinity(item)) + 0.1 * min(1.0, log(views + 1) / ln10 / 7);
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
  /// Opens [item] on the watch page; [at] is where to start, else where
  /// it was left off. [keepMini] plays it in the mini player when that is
  /// where the last video was (the queue moving on by itself).
  Future<void> play(VideoItem item, {List<VideoItem>? from, Duration? at, bool keepMini = false, bool retryingStart = false}) async {
    final player = this.player;
    if (player == null) return;
    if (mini && playing?.id == item.id && at == null && !retryingStart) return expandMini();
    _ensureVideo(player);
    _startTimer?.cancel();
    if (!retryingStart) _startAttempts = 0;
    // A loop belongs to the video it was set in.
    if (playing?.id != item.id) unawaited(clearLoop());
    if (playing?.id != item.id) {
      _shownOptions.clear();
      unawaited(cast.stop());
      if (playing case final left?) {
        _played.removeWhere((v) => v.id == left.id);
        _played.add(left);
        if (_played.length > 50) _played.removeAt(0);
      }
      _remember();
      _finishWatching();
      _watching = item;
    }
    unawaited(account?.loadRating(item.id));
    _saveProgress();
    _countWatchTime(flush: true);
    _playbackChannel = null;
    _stopCurrentChat();
    final serial = ++_playSerial;
    _recoveryTimer?.cancel();
    _recovery.reset();
    final resume = preferences.resumePlayback ? library?.progressOf(item.id) : null;
    final start = at ?? (resume != null && resume.resumable ? resume.position : null);
    _update(() {
      playing = item;
      mini = keepMini && mini;
      if (from != null) queue = List.unmodifiable(from);
      // A stream being waited for keeps saying so until it plays.
      if (!retryingStart) {
        playbackError = null;
        _waitingForStart = false;
      }
      details = null;
      loadingDetails = true;
      replayChat = const [];
      loadingReplayChat = false;
      replayChatError = null;
      availableHeights = const [];
      related?.dispose();
      related = null;
      _segments = const [];
      _skipped.clear();
      dislikes = null;
    });
    unawaited(_loadDetails(item, serial));
    if (settings.returnDislike) unawaited(_loadDislikes(item, serial));
    if (settings.sponsorBlock) unawaited(_loadSegments(item, serial));
    if (await _open(item, serial, start: start, play: preferences.autoPlay)) {
      await _applyChannelPlayback(item, player);
      if (preferences.recordHistory && !incognito) await _history?.record(item);
      if (start != null && at == null) _notice(tr('从 {0} 继续播放', [_clock(start)]));
      final next = upNext.firstOrNull;
      if (next != null) prefetch(next);
      if (item.isLive) {
        _startCurrentChat(item, serial);
      } else if (item.liveStatus == 'was_live') {
        unawaited(_loadReplayChat(item, serial));
      }
    }
  }

  void _startCurrentChat(VideoItem item, int serial) {
    final repository = _repository;
    if (repository == null || serial != _playSerial) return;
    _update(() {
      loadingReplayChat = true;
      replayChatError = null;
    });
    _currentChat = repository.liveChat.current(item.id).listen(
      (message) {
        if (serial != _playSerial || !_currentChatIds.add(message.id)) return;
        _currentChatPending.add(message);
        _currentChatFlushTimer ??= Timer(const Duration(milliseconds: 300), () {
          _currentChatFlushTimer = null;
          _flushCurrentChat(serial);
        });
      },
      onError: (Object error) {
        if (serial == _playSerial) {
          _update(() {
            replayChatError = friendlyError(error);
            loadingReplayChat = false;
          });
        }
      },
      onDone: () {
        _flushCurrentChat(serial);
        if (serial == _playSerial) {
          _update(() => loadingReplayChat = false);
        }
      },
    );
  }

  void _flushCurrentChat(int serial) {
    if (serial != _playSerial || _currentChatPending.isEmpty) return;
    final next = [...replayChat, ..._currentChatPending];
    _currentChatPending.clear();
    replayChat = List.unmodifiable(next.length > 2000 ? next.sublist(next.length - 2000) : next);
    if (loadingReplayChat) {
      _update(() => loadingReplayChat = false);
    } else if (!_disposed) {
      chatMessages.value++;
    }
  }

  void _stopCurrentChat() {
    _currentChatFlushTimer?.cancel();
    _currentChatFlushTimer = null;
    _currentChatPending.clear();
    _currentChatIds.clear();
    unawaited(_currentChat?.cancel());
    _currentChat = null;
  }

  /// Asks again for the chat of the video playing after it failed.
  void retryChat() {
    final item = playing;
    if (item == null) return;
    if (item.isLive) {
      unawaited(_currentChat?.cancel());
      _startCurrentChat(item, _playSerial);
    } else {
      unawaited(_loadReplayChat(item, _playSerial));
    }
  }

  Future<void> _loadReplayChat(VideoItem item, int serial) async {
    final repository = _repository;
    if (repository == null || serial != _playSerial) return;
    _update(() {
      loadingReplayChat = true;
      replayChatError = null;
    });
    try {
      final messages = await repository.liveChat.replay(item.id);
      if (serial == _playSerial) _update(() => replayChat = messages);
    } catch (error) {
      if (serial == _playSerial) _update(() => replayChatError = friendlyError(error));
    } finally {
      if (serial == _playSerial) _update(() => loadingReplayChat = false);
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
    if (item == null || player == null || !preferences.recordProgress || incognito) return;
    final duration = player.state.duration;
    if (duration <= Duration.zero) return;
    library?.recordProgress(item.id, player.state.position, duration);
    if (now) unawaited(library?.flush());
  }

  Future<void> _loadSegments(VideoItem item, int serial) async {
    try {
      final local = await downloads?.localVideo(item.id);
      final saved = [for (final s in local?.segments ?? const <SkipSegment>[]) if (settings.sponsorCategories.contains(s.category)) s];
      final segments = saved.isNotEmpty ? saved : await _sponsorBlock.segments(item.id, settings.sponsorCategories);
      if (serial == _playSerial) _update(() => _segments = segments);
    } catch (_) {
      // Playback does not depend on SponsorBlock being reachable.
    }
  }

  Future<void> _loadDislikes(VideoItem item, int serial) async {
    try {
      final count = await _returnDislike.votes(item.id);
      if (serial == _playSerial) _update(() => dislikes = count);
    } catch (_) {
      // The page shows the likes without it.
    }
  }

  void _skipSegments(Duration position) {
    for (final segment in _segments) {
      if (_skipped.contains(segment) || !segment.contains(position)) continue;
      // Each segment is skipped once, so seeking back into it plays it.
      _skipped.add(segment);
      unawaited(player?.seek(segment.end));
      if (settings.sponsorNotice) _notice(tr('已跳过{0}', [sponsorCategories[segment.category] ?? tr('片段')]));
      return;
    }
  }

  /// Opens [item] with the current format settings, from [start] if given.
  ///
  /// The video is resolved by yt-dlp first, usually already done for the
  /// watch page or while the pointer rested on its card. libmpv then plays
  /// the picked streams directly, or has its ytdl_hook pick formats and
  /// subtitles from the saved extraction without asking YouTube again.
  /// [resolved] false, or a failed resolution, leaves everything to
  /// ytdl_hook as before.
  Future<bool> _open(VideoItem item, int serial, {Duration? start, bool play = true, bool resolved = true, bool piped = true, bool allowLocal = true}) async {
    // Opened again (reconnecting, another quality): the subtitles shown
    // come back, as the new file starts with none of the ones added.
    final kept = _tracking?.id == item.id ? _shownSubtitles() : null;
    final opened = await _openOnce(item, serial, start: start, play: play, resolved: resolved, piped: piped, allowLocal: allowLocal);
    if (opened && kept != null) unawaited(_restoreSubtitles(kept, serial));
    return opened;
  }

  /// The subtitles shown now: the main one by its label (empty: turned
  /// off) and the second one.
  ({String? main, SubtitleOption? second}) _shownSubtitles() {
    final track = player?.state.track.subtitle;
    final main = track == null || track.id == 'auto' ? null : track.id == 'no' ? '' : track.title;
    return (main: main, second: secondarySubtitle);
  }

  Future<void> _restoreSubtitles(({String? main, SubtitleOption? second}) kept, int serial) async {
    final player = this.player;
    if (player == null) return;
    try {
      await player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      return;
    }
    if (serial != _playSerial || this.player != player) return;
    final main = kept.main;
    if (main == '') {
      await player.setSubtitleTrack(SubtitleTrack.no());
    } else if (main != null) {
      final option = _shownOptions[main] ?? details?.subtitles.where((o) => o.label == main).firstOrNull;
      if (option != null && player.state.track.subtitle.title != main) await showSubtitle(option);
    }
    if (serial != _playSerial || this.player != player) return;
    final second = kept.second;
    if (second != null && secondarySubtitle?.label != second.label) {
      logInfo('Showing ${second.language} (${second.kind.name}) as the second subtitle again');
      await setSecondarySubtitle(second);
    }
  }

  /// The subtitles shown in this video, by label, so a reopened video can
  /// show them again.
  final _shownOptions = <String, SubtitleOption>{};

  /// Gets the first video ready while nothing else happens: reads the
  /// player's files from disk once they may be cold after an update,
  /// probes the hardware decoders, and makes the picture output when the
  /// mouse and keyboard have been still for a moment. Opening a video
  /// first does whatever is still left there and then.
  Future<void> _warmUp(Player player) async {
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (_disposed) return;
    final read = Stopwatch()..start();
    final folder = File(Platform.resolvedExecutable).parent.path;
    final mpv = paths?.mpv;
    final bytes = await Isolate.run(_readingPlayerFiles(folder, mpv));
    logInfo('Read ${bytes >> 20} MB of player files in ${read.elapsedMilliseconds} ms');
    final directories = this.directories;
    if (directories != null) {
      try {
        final shaders = Directory('${directories.cache.path}${Platform.pathSeparator}shaders').listSync().whereType<File>().length;
        logInfo('Shader cache holds $shaders shaders');
      } catch (_) {}
    }
    await _measureDecoders();
    var lastInput = DateTime.now();
    void touched(PointerEvent _) => lastInput = DateTime.now();
    bool pressed(KeyEvent _) {
      lastInput = DateTime.now();
      return false;
    }

    GestureBinding.instance.pointerRouter.addGlobalRoute(touched);
    HardwareKeyboard.instance.addHandler(pressed);
    try {
      while (!_disposed && videoController == null && this.player == player) {
        final still = DateTime.now().difference(lastInput);
        if (still >= const Duration(milliseconds: 1500)) {
          _ensureVideo(player);
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500) - still);
      }
    } finally {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(touched);
      HardwareKeyboard.instance.removeHandler(pressed);
    }
  }

  /// Makes the video's picture output, from [_warmUp] or when the first
  /// video plays. Made right at start it held up drawing the window for
  /// most of a second.
  void _ensureVideo(Player player) {
    if (videoController != null) return;
    final made = Stopwatch()..start();
    final controller = videoController = VideoController(player, configuration: VideoControllerConfiguration(hwdec: settings.hwdec));
    // It is made after the next frame, and an idle window draws none.
    WidgetsBinding.instance.scheduleFrame();
    unawaited(controller.platform.future.then((_) => logInfo('Video output made in ${made.elapsedMilliseconds} ms'), onError: (Object error) => logError('Video output failed', error)));
  }

  Future<bool> _openOnce(VideoItem item, int serial, {Duration? start, bool play = true, bool resolved = true, bool piped = true, bool allowLocal = true}) async {
    final player = this.player!;
    _ensureVideo(player);
    try {
      if (!_libmpvConfirmed) await _tools?.libmpv.markPlaying();
      if (settings.proxyMode == ProxyMode.system) await _refreshProxy(ifStale: true);
      final local = allowLocal && resolved && piped && !item.isLive ? await downloads?.localVideo(item.id) : null;
      _openedLocal = null;
      // A download in a codec the playback rules disable (AV1 decoded in
      // software, say) streams instead, in a codec the rules allow.
      final localCodec = local?.videoCodec;
      if (local != null && !FormatPolicy.allows(settings, localCodec)) {
        logInfo('The download of ${item.id} is ${localCodec!.label}, a codec the playback rules disable; playing online instead');
        _notice(tr('下载的文件是 {0} 编码，已按播放规则改为在线播放', [localCodec.label]));
      } else if (local != null) {
        return await _openLocal(item, serial, local, start: start, play: play);
      }
      final format = _format;
      final formatSort = _formatSort;
      _openedVia = null;
      if (resolved && piped) {
        _recentErrors.clear();
        _relaysTried.clear();
        _youtubeRefused = null;
      }
      // Piped or Invidious first, as chosen in 播放来源.
      if (piped) {
        if (await _openViaRelays(item, serial, start: start, play: play)) return true;
        if (serial != _playSerial) return false;
      }
      ResolvedVideo? video;
      if (resolved) {
        try {
          video = await _repository!.streams.resolve(item.id, format, formatSort: formatSort);
        } catch (e) {
          _recentErrors.add('$e');
          final failure = PlaybackFailure.classify(['$e']);
          if (!failure.retryable) {
            // libmpv's ytdl_hook would ask YouTube again and fail the same way.
            if (_serversMayHelp(failure.kind)) return await _fallBack(item, serial, failure, start: start, play: play);
            if (serial == _playSerial) _fail(item, failure);
            return false;
          }
          logError('Prefetching ${item.id} failed, letting libmpv resolve it', e);
        }
        if (serial != _playSerial) return false;
      }
      final subtitles = settings.subtitleMode != SubtitleMode.off;
      // Through the relay when the app's own connections reach YouTube the
      // way libmpv's would: directly or through an HTTP proxy.
      // A video whose stream broke through it is reopened without it.
      final relay = (proxy.url == null || proxy.isHttp) && _unrelayed != item.id ? _relay : null;
      final agent = video?.userAgent;
      final direct = video != null && video.format == format && !subtitles
          ? video.directAddress(relay: relay == null ? null : (url, size) => relay.register(url, size: size, userAgent: agent, proxy: proxy.url))
          : null;
      _relayed = direct != null && relay != null ? item.id : null;
      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('ytdl-format', format);
        await platform.setProperty('ytdl-raw-options', PlayerOptionApplicator.ytdlRawOptions(settings, infoJson: direct == null ? video?.file.path : null, proxy: proxy.ytDlpValue(settings.proxyMode)));
        if (direct != null && agent != null) await platform.setProperty('user-agent', agent);
      }
      _tracking = null;
      if (secondarySubtitle != null) {
        secondarySubtitle = null;
        if (platform is NativePlayer) unawaited(platform.setProperty('secondary-sid', 'no').catchError((_) {}));
      }
      _lastPosition = start ?? Duration.zero;
      _resumePoint.start(_lastPosition);
      _openedResolved = video == null ? null : item.id;
      _openedOrigin = video?.origin;
      if (video != null) _update(() => availableHeights = video!.heightsFor(settings));
      await player.open(Media(direct ?? item.url, start: start), play: play);
      if (serial == _playSerial) _tracking = item;
      _mpvLogLines = 0;
      _lastDrops = 0;
      _dropStreak = 0;
      // The decoder is known once frames are shown; resolving the video
      // can take longer than any fixed delay.
      _decoderPending = true;
      _update(() {});
      return true;
    } catch (e) {
      logError('Could not open video ${item.id}', e);
      if (serial == _playSerial) _fail(item, PlaybackFailure.classify(['$e', ..._recentErrors]));
      return false;
    }
  }

  /// Plays the downloaded file of [item] instead of asking YouTube.
  Future<bool> _openLocal(VideoItem item, int serial, LocalVideo local, {Duration? start, bool play = true}) async {
    final player = this.player!;
    _recentErrors.clear();
    _openedVia = null;
    _openedResolved = null;
    _tracking = null;
    if (secondarySubtitle != null) {
      secondarySubtitle = null;
      final platform = player.platform;
      if (platform is NativePlayer) unawaited(platform.setProperty('secondary-sid', 'no').catchError((_) {}));
    }
    _lastPosition = start ?? Duration.zero;
    _resumePoint.start(_lastPosition);
    _openedLocal = item.id;
    await player.open(Media(local.file.path, start: start), play: play);
    if (serial == _playSerial) _tracking = item;
    _mpvLogLines = 0;
    _lastDrops = 0;
    _dropStreak = 0;
    _decoderPending = true;
    _update(() {});
    unawaited(_addLocalSubtitles(local, serial));
    return true;
  }

  /// Adds the subtitle files saved next to a downloaded video, the one in
  /// the preferred language selected, unless subtitles are set to stay off.
  Future<void> _addLocalSubtitles(LocalVideo local, int serial) async {
    final player = this.player;
    final platform = player?.platform;
    if (player == null || platform is! NativePlayer || local.subtitles.isEmpty || settings.subtitleMode == SubtitleMode.off) return;
    try {
      await player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 15));
      if (serial != _playSerial) return;
      final first = local.preferredSubtitle(settings.subtitleLanguage.mpvLangs.split(','));
      await platform.command(['sub-add', first.path, 'select']);
      await syncMainSubtitle();
      for (final other in local.subtitles.where((f) => f != first)) {
        await platform.command(['sub-add', other.path, 'auto']);
      }
    } catch (e) {
      logError('Could not load offline subtitles', e);
    }
  }

  /// The server network to try next for [item], or null for YouTube.
  /// Normally the one 播放来源 names, and only without subtitles, which
  /// these servers do not give libmpv. After YouTube refused the video
  /// (429, a bot check, a challenge yt-dlp could not solve, or an error
  /// that remained after resolving again) both are tried (that one first),
  /// subtitles or not, since playing beats failing.
  RelayKind? _nextRelay(VideoItem item) {
    if (item.isLive) return null;
    final preferred = settings.playbackSource.relay;
    final candidates = _youtubeRefused != null
        ? [if (preferred != null) preferred, ...RelayKind.values.where((k) => k != preferred)]
        : [if (preferred != null && settings.subtitleMode == SubtitleMode.off) preferred];
    return candidates.where((k) => !_relaysTried.contains(k)).firstOrNull;
  }

  /// Opens [item] from the next server [_nextRelay] names, moving on to the
  /// one after when a server cannot resolve it; false when none plays it.
  Future<bool> _openViaRelays(VideoItem item, int serial, {Duration? start, bool play = true}) async {
    final player = this.player!;
    while (true) {
      final kind = _nextRelay(item);
      if (kind == null) return false;
      _relaysTried.add(kind);
      final address = await _relayAddress(item, kind);
      if (serial != _playSerial) return false;
      if (address == null) continue;
      _tracking = null;
      _lastPosition = start ?? Duration.zero;
      _resumePoint.start(_lastPosition);
      _openedResolved = null;
      _openedVia = item.id;
      await player.open(Media(address, start: start), play: play);
      if (serial == _playSerial) _tracking = item;
      _mpvLogLines = 0;
      _lastDrops = 0;
      _dropStreak = 0;
      _decoderPending = true;
      _update(() {});
      return true;
    }
  }

  /// Whether Piped or Invidious may play what YouTube would not. Not for
  /// what the video itself is (private, upcoming, no allowed format) or for
  /// a network that is down.
  static bool _serversMayHelp(FailureKind kind) =>
      const {FailureKind.rateLimited, FailureKind.botCheck, FailureKind.challenge, FailureKind.forbidden, FailureKind.unknown}.contains(kind);

  /// YouTube would not play [item]: plays it from the Piped or Invidious
  /// server not yet tried, and only when there is none shows the error.
  Future<bool> _fallBack(VideoItem item, int serial, PlaybackFailure failure, {Duration? start, bool play = true}) async {
    if (failure.kind == FailureKind.rateLimited) _rateLimitedUntil = DateTime.now().add(const Duration(minutes: 10));
    if (_youtubeRefused == null) logInfo('YouTube would not play ${item.id} (${failure.kind.name}); trying Piped and Invidious');
    _youtubeRefused = failure;
    if (await _openViaRelays(item, serial, start: start, play: play)) return true;
    if (serial == _playSerial) _fail(item, PlaybackFailure(failure.kind, failure.detail, tried: [for (final k in _relaysTried) k == RelayKind.piped ? 'Piped' : 'Invidious']));
    return false;
  }

  /// The play address for [item] from a [kind] server, or null to go on.
  Future<String?> _relayAddress(VideoItem item, RelayKind kind) async {
    final watch = Stopwatch()..start();
    final name = kind == RelayKind.piped ? 'Piped' : 'Invidious';
    try {
      final source = settings.playbackSource;
      final named = source.relay == kind && source.isCustom ? (kind == RelayKind.piped ? settings.pipedServer : settings.invidiousServer) : '';
      final server = named.isEmpty ? null : named;
      final video = await (kind == RelayKind.piped ? _piped.fetch(item.id, server: server) : _invidious.fetch(item.id, server: server));
      final address = video.edl(_playback);
      if (address == null) return null;
      _update(() => availableHeights = video.heightsFor(settings));
      logInfo('Playing ${item.id} from $name ${video.server}, took ${watch.elapsedMilliseconds} ms');
      return address;
    } catch (e) {
      logInfo('$e; not using $name');
      return null;
    }
  }

  /// Shows why [item] cannot play and acts on the cause.
  void _fail(VideoItem item, PlaybackFailure failure) {
    _recoveryTimer?.cancel();
    _recovery.cancelPending();
    logError('Playback failed ${item.id} (${failure.kind.name}): ${failure.detail}');
    if (failure.kind == FailureKind.noFormat) failure = PlaybackFailure(failure.kind, failure.detail, disabled: FormatPolicy.disabledNames(settings));
    switch (failure.kind) {
      case FailureKind.rateLimited:
        _rateLimitedUntil = DateTime.now().add(const Duration(minutes: 10));
      case FailureKind.challenge:
        if (!_updateCheckedForChallenge) {
          _updateCheckedForChallenge = true;
          unawaited(checkUpdates());
        }
      case FailureKind.upcoming:
        _waitForStart(item);
      default:
    }
    _update(() {
      playbackError = failure.message;
      _waitingForStart = failure.kind == FailureKind.upcoming;
    });
  }

  /// Opens [item] again once it may have started: at its scheduled time
  /// when that is still ahead, otherwise every half minute, then less often.
  void _waitForStart(VideoItem item) {
    _startTimer?.cancel();
    final serial = _playSerial;
    final scheduled = (playing?.id == item.id ? scheduledStart : item.scheduledStart)?.difference(DateTime.now());
    final delay = scheduled != null && scheduled > const Duration(minutes: 1)
        ? scheduled + const Duration(seconds: 15)
        : Duration(seconds: min(30 * (1 << min(_startAttempts, 2)), 120));
    _startAttempts++;
    logInfo('${item.id} has not started, opening it again in ${delay.inSeconds} s');
    _startTimer = Timer(delay, () {
      if (_disposed || serial != _playSerial || playing?.id != item.id || !waitingForStart) return;
      unawaited(play(item, keepMini: true, retryingStart: true));
    });
  }

  /// Reopens the current video where it stopped after the network failed,
  /// or shows [message] once the attempts are used up.
  Future<void> _recover(String message) async {
    final item = _tracking;
    if (item == null || _recovering) return;
    final position = _resumePoint.beforeFailure;
    if (!_recovery.tryAttempt(position: position)) {
      logError('Playback interrupted, gave up reconnecting ${item.id}: $message');
      _fail(item, PlaybackFailure.classify([message, ..._recentErrors]));
      return;
    }
    logInfo('Playback interrupted, reconnecting ${item.id} at ${_clock(position)}: $message');
    if (_relayed == item.id) {
      _unrelayed = item.id;
      logInfo('Playing ${item.id} without the local chunked relay');
    }
    _notice(tr('网络中断，正在从 {0} 重新连接…', [_clock(position)]));
    _recovering = true;
    _recoveryTimer?.cancel();
    final serial = _playSerial;
    try {
      // A new open also asks yt-dlp again, which replaces stream addresses
      // that expired while the video sat paused.
      _repository?.streams.forget(item.id);
      final opened = await _open(item, serial, start: position);
      if (!opened || serial != _playSerial) return;
      _recoveryTimer = Timer.periodic(PlaybackRecovery.stallTimeout, (_) {
        if (serial != _playSerial || !_recovery.awaitingProgress) {
          _recoveryTimer?.cancel();
        } else if (_recovery.stalled && player!.state.playing) {
          unawaited(_recover('Playback did not advance after reopening'));
        }
      });
    } finally {
      _recovering = false;
    }
  }

  late final _subtitleFiles = SubtitleFiles(
    _http,
    Directory('${Directory.systemTemp.path}${Platform.pathSeparator}Lumtub subtitles'),
    () => translator,
    byTranslator: () => preferences.subtitlesByService && preferences.translation.service != TranslationService.google,
    position: () => player?.state.position ?? Duration.zero,
    onUpdated: (path) => unawaited(_subtitleFileUpdated(path)),
  );

  /// Swaps the loaded track of [path] for the file's new contents (the
  /// rest of a translation), keeping it where it was shown: main, second or
  /// not at all. mpv's sub-reload would select it as the main one.
  Future<void> _subtitleFileUpdated(String path) async {
    final platform = player?.platform;
    if (platform is! NativePlayer) return;
    try {
      Future<List<Map<dynamic, dynamic>>> tracks() async {
        final list = jsonDecode(await platform.getProperty('track-list'));
        return [if (list is List) for (final t in list.whereType<Map>()) if (t['type'] == 'sub' && t['external-filename'] == path) t];
      }

      final old = (await tracks()).firstOrNull;
      if (old == null) return;
      final id = '${old['id']}';
      final main = await platform.getProperty('sid');
      final second = await platform.getProperty('secondary-sid');
      await platform.command(['sub-add', path, 'auto', '${old['title'] ?? ''}', '${old['lang'] ?? ''}']);
      final added = (await tracks()).where((t) => '${t['id']}' != id).lastOrNull;
      if (added == null) return;
      if (main == id) await platform.setProperty('sid', '${added['id']}');
      if (second == id) await platform.setProperty('secondary-sid', '${added['id']}');
      await platform.command(['sub-remove', id]);
      if (main == id) await syncMainSubtitle();
      logInfo('Subtitle translation finished; track $id replaced by ${added['id']}');
    } catch (e) {
      logInfo('Could not reload the finished subtitle translation: $e');
    }
  }

  /// Tells media_kit which main subtitle mpv shows, and this controller
  /// which second one. media_kit only learns of one chosen through its own
  /// setSubtitleTrack, not of one mpv picked as the file loaded, selected
  /// by sub-add or a sid change, and the subtitle panel reads both.
  Future<void> syncMainSubtitle() async {
    final player = this.player;
    final platform = player?.platform;
    if (player == null || platform is! NativePlayer) return;
    try {
      final second = await platform.getProperty('secondary-sid');
      if (secondarySubtitle == null && second.isNotEmpty && second != 'no') {
        final title = player.state.tracks.subtitle.where((t) => t.id == second).firstOrNull?.title;
        final option = details?.subtitles.where((o) => o.label == title).firstOrNull;
        if (option != null) _update(() => secondarySubtitle = option);
      }
    } catch (_) {}
    try {
      final sid = await platform.getProperty('sid');
      if (sid.isEmpty || sid == player.state.track.subtitle.id) return;
      if (sid == 'no') return await player.setSubtitleTrack(SubtitleTrack.no());
      SubtitleTrack? find(Tracks tracks) => tracks.subtitle.where((t) => t.id == sid).firstOrNull;
      final track = find(player.state.tracks) ?? await player.stream.tracks.map(find).firstWhere((t) => t != null).timeout(const Duration(seconds: 3));
      if (track != null) await player.setSubtitleTrack(track);
    } catch (e) {
      logInfo('Could not read the selected subtitle: $e');
    }
  }

  /// [option] as a local file, fetched with retries; see [SubtitleFiles].
  Future<String> _subtitleFile(SubtitleOption option) async {
    try {
      return await _subtitleFiles.pathFor(option);
    } catch (e) {
      logInfo('Could not fetch subtitles ${option.language}: $e');
      rethrow;
    }
  }

  final _cues = <String, List<SubtitleCue>>{};

  /// The lines for 字幕列表: of the main subtitle, each with the second
  /// subtitle's words spoken at the same time, or of the second one while
  /// it is the only one on. Read from the file the track came from, ours or
  /// the one mpv was given. Empty when there is no subtitle or it is not
  /// WebVTT or SRT.
  Future<List<PairedCue>> listedSubtitleCues() async {
    final player = this.player;
    final platform = player?.platform;
    if (player == null || platform is! NativePlayer) return const [];
    final track = player.state.track.subtitle;
    final off = track.id == 'no' || track.id == 'auto';
    final second = secondarySubtitle;
    final mode = preferences.subtitleListMode;
    if (off || (second != null && mode == SubtitleListMode.second)) {
      return second == null ? const [] : pairSubtitleCues(await _optionCues(second), const []);
    }
    final main = await _trackCues(platform, track);
    if (second == null || mode == SubtitleListMode.first) return pairSubtitleCues(main, const []);
    return pairSubtitleCues(main, await _optionCues(second));
  }

  Future<List<SubtitleCue>> _optionCues(SubtitleOption option) => _cached('${playing?.id}\u0000${option.url}', () async => File(await _subtitleFile(option)).readAsString());

  Future<List<SubtitleCue>> _trackCues(NativePlayer platform, SubtitleTrack track) async {
    final option = details?.subtitles.where((o) => o.label == track.title).firstOrNull;
    if (option != null) return _optionCues(option);
    final cues = await _cached('${playing?.id}\u0000${track.id}\u0000${track.title}', () async {
      final list = jsonDecode(await platform.getProperty('track-list'));
      final entry = list is List ? list.whereType<Map>().where((t) => t['type'] == 'sub' && '${t['id']}' == track.id).firstOrNull : null;
      final source = entry?['external-filename'];
      if (source is String && source.startsWith(RegExp('https?://'))) {
        final response = await _http.get(Uri.parse(source)).timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) return utf8.decode(response.bodyBytes, allowMalformed: true);
      } else if (source is String && await File(source).exists()) {
        return File(source).readAsString();
      }
      return null;
    });
    if (cues.isNotEmpty) return cues;
    // A track libmpv's ytdl_hook added has its own title, and its address
    // may be refused; the same language from the list reads the same lines.
    final language = track.language;
    final same = language == null ? null : details?.subtitles.where((o) => o.kind != SubtitleKind.translated && sameLanguage(o.language, language)).firstOrNull;
    return same == null ? cues : _optionCues(same);
  }

  Future<List<SubtitleCue>> _cached(String key, Future<String?> Function() read) async {
    if (_cues[key] case final cues?) return cues;
    String? text;
    try {
      text = await read();
    } catch (e) {
      logInfo('Could not read the subtitle lines: $e');
    }
    final cues = text == null ? const <SubtitleCue>[] : parseSubtitleCues(text);
    if (cues.isNotEmpty) {
      if (_cues.length >= 4) _cues.remove(_cues.keys.first);
      _cues[key] = cues;
    }
    return cues;
  }

  /// The text of the subtitles on screen now, main and second.
  String get currentSubtitleText => [
        for (final line in player?.state.subtitle ?? const <String>[])
          if (line.trim().isNotEmpty) line.trim(),
      ].join('\n');

  /// Shows [option], adding it to the player first if it is not loaded.
  Future<void> showSubtitle(SubtitleOption option) async {
    final player = this.player;
    final platform = player?.platform;
    if (player == null || platform is! NativePlayer) return;
    _shownOptions[option.label] = option;
    final loaded = player.state.tracks.subtitle.where((t) => t.title == option.label).firstOrNull;
    try {
      if (loaded != null) {
        await player.setSubtitleTrack(loaded);
      } else {
        final file = await _subtitleFile(option);
        if (this.player != player) return;
        await platform.command(['sub-add', file, 'select', option.label, option.language]);
        await syncMainSubtitle();
      }
    } catch (e) {
      logError('Could not load subtitles ${option.language}', e);
      _notice(tr('无法加载这条字幕'));
    }
  }

  /// Once the main subtitle is on, shows it in 第一字幕语言 (YouTube's
  /// translation when the video has none in it) and the subtitle 第二字幕语言
  /// names above it, unless that is the main one already.
  Future<void> _autoSubtitles(VideoItem item, VideoDetails details, int serial) async {
    final player = this.player;
    if (player == null || details.subtitles.isEmpty || settings.subtitleMode == SubtitleMode.off) return;
    if (_secondaryAutoFor == item.id || _openedLocal == item.id) return;
    bool shown(SubtitleTrack t) => t.id != 'no' && t.id != 'auto';
    // mpv picks the track itself as the file loads and does not say so;
    // ask it for a few seconds, then pick one here.
    for (var i = 0; i < 6 && !shown(player.state.track.subtitle); i++) {
      await syncMainSubtitle();
      if (serial != _playSerial || this.player != player) return;
      if (shown(player.state.track.subtitle)) break;
      await player.stream.track.firstWhere((t) => shown(t.subtitle)).timeout(const Duration(seconds: 1), onTimeout: () => player.state.track);
    }
    if (serial != _playSerial || this.player != player || _secondaryAutoFor == item.id) return;
    _secondaryAutoFor = item.id;
    var mainTitle = shown(player.state.track.subtitle) ? player.state.track.subtitle.title : null;
    var mainLanguage = shown(player.state.track.subtitle) ? player.state.track.subtitle.language : null;
    final first = settings.subtitleLanguage.translation;
    final spoken = settings.subtitleOriginal ? originalSubtitle(details.subtitles, language: details.language) : null;
    final mainWanted = settings.subtitleMode == SubtitleMode.always || mainTitle != null;
    if (mainWanted && (mainTitle == null || (spoken != null ? spoken.label != mainTitle && !sameLanguage(spoken.language, mainLanguage) : !speaks(mainLanguage, first)))) {
      final option = spoken ?? subtitleIn(details.subtitles, first);
      if (option != null && option.label != mainTitle) {
        logInfo('Showing ${option.language} (${option.kind.name}) as the main subtitle');
        await showSubtitle(option);
        if (serial != _playSerial || this.player != player) return;
        mainTitle = option.label;
        mainLanguage = option.language;
      }
    }
    final wanted = settings.secondarySubtitleLanguage;
    final target = TranslationLanguage.maybeByCode(wanted);
    final SubtitleOption? option;
    if (wanted == PlayerSettings.originalSubtitle) {
      option = originalSubtitle(details.subtitles, language: details.language);
      if (option == null || sameLanguage(option.language, mainLanguage)) return;
    } else {
      option = target == null ? null : subtitleIn(details.subtitles, target);
      if (option == null || speaks(mainLanguage, target!)) {
        if (wanted.isNotEmpty) logInfo('No second subtitle in $wanted beside $mainLanguage');
        return;
      }
    }
    if (option.label == mainTitle || secondarySubtitle != null) return;
    logInfo('Showing ${option.language} (${option.kind.name}) as the second subtitle');
    await setSecondarySubtitle(option);
  }

  /// Keeps what was just chosen in the 字幕 panel for the videos after this
  /// one: the first subtitle ([primary]) on or off and in which language,
  /// or the second. [option] null is 关闭. Saved without a notice.
  Future<void> rememberSubtitleChoice({required bool primary, SubtitleOption? option}) async {
    final details = this.details;
    final spoken = details == null ? null : originalSubtitle(details.subtitles, language: details.language);
    final original = option != null && spoken != null && option.label == spoken.label;
    PlayerSettings next;
    if (primary) {
      if (option == null) {
        next = settings.copyWith(subtitleMode: SubtitleMode.off);
      } else {
        final language = SubtitleLanguage.values.where((l) => l != SubtitleLanguage.auto && speaks(option.language, l.translation)).firstOrNull;
        // Uploaded subtitles alone would miss the automatic one chosen.
        final mode = settings.subtitleMode == SubtitleMode.manual && option.kind == SubtitleKind.uploaded ? SubtitleMode.manual : SubtitleMode.always;
        next = settings.copyWith(
          subtitleMode: mode,
          subtitleOriginal: original,
          subtitleLanguage: original ? null : language == null || language == settings.subtitleLanguage.resolved ? null : language,
        );
      }
    } else {
      final target = option == null ? null : TranslationLanguage.all.where((l) => speaks(option.language, l)).firstOrNull;
      next = settings.copyWith(
        secondarySubtitleLanguage: option == null ? '' : original ? PlayerSettings.originalSubtitle : target?.code,
        // A second subtitle needs the first one on to come back by itself.
        subtitleMode: option != null && settings.subtitleMode == SubtitleMode.off ? SubtitleMode.always : null,
      );
    }
    if (jsonEncode(next.toJson()) == jsonEncode(settings.toJson())) return;
    final player = this.player;
    if (player != null) await PlayerOptionApplicator.apply(player, next, previous: settings);
    _update(() => settings = next);
    await _settingsStore?.save(next);
  }

  /// Shows [option] (null: none) above the main subtitle.
  Future<void> setSecondarySubtitle(SubtitleOption? option) async {
    final player = this.player;
    if (player == null) return;
    if (option != null) _update(() => secondaryLoading = option);
    try {
      final loaded = option == null || player.state.tracks.subtitle.any((t) => t.title == option.label);
      final file = loaded ? null : await _subtitleFile(option);
      if (this.player != player) return;
      if (!await SecondarySubtitle.set(player, option, file: file)) throw StateError('字幕未加载');
      _update(() => secondarySubtitle = option);
    } catch (e) {
      logError('Could not set secondary subtitles ${option?.language}', e);
      _notice(tr('无法加载这条字幕'));
    } finally {
      if (identical(secondaryLoading, option)) _update(() => secondaryLoading = null);
    }
  }

  Future<void> retryPlayback() async {
    final item = playing;
    if (item != null) await play(item);
  }

  void _listenTo(Player player) {
    void videoSize(_) => _outputSize?.video = Size((player.state.width ?? 0).toDouble(), (player.state.height ?? 0).toDouble());
    _playerSubscriptions.addAll([
      player.stream.width.listen(videoSize),
      player.stream.height.listen(videoSize),
      player.stream.playing.listen((_) {
        _updateEfficiency();
        _countWatchTime();
      }),
      player.stream.rate.listen((rate) => _rememberPlayback(rate: rate)),
      player.stream.volume.listen((volume) => _rememberPlayback(volume: volume)),
      // A second of playback proves a downloaded libmpv works on this PC.
      player.stream.position.listen((position) {
        if (_tracking == null) return;
        if (position > Duration.zero) {
          if (waitingForStart) {
            _update(() {
              _waitingForStart = false;
              playbackError = null;
            });
          }
          if (_recovery.observeProgress(position,
            playing: player.state.playing,
            buffering: player.state.buffering,
            decoded: audioOnly || _backgroundAudioOnly || (player.state.width ?? 0) > 0,
            rate: player.state.rate,
          )) {
            _recoveryTimer?.cancel();
            logInfo('Playback recovered after ten seconds of decoded progress');
          }
          _lastPosition = position;
          _resumePoint.observe(position, rate: player.state.rate);
        }
        if (_decoderPending && position > const Duration(milliseconds: 500) && (player.state.width ?? 0) > 0) {
          _decoderPending = false;
          unawaited(inspectCurrentDecoder(delay: const Duration(milliseconds: 500)));
        }
        if (_segments.isNotEmpty) _skipSegments(position);
        _countWatchTime();
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
          unawaited(_recover(tr('视频在 {0} 意外结束', [_clock(_lastPosition)])));
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
        if (isSubtitleError(message)) {
          logInfo('Subtitles failed to load, video keeps playing: $message');
          return;
        }
        // FFmpeg may log the HTTP status before naming the request. Keep
        // it diagnostic-only; media URL failures, EOF and stalls drive recovery.
        if (isUnattributedHttpError(message)) return;
        _onPlayerError(player, message, loaded: player.state.duration > Duration.zero);
      }),
      // libmpv's warnings go to the log, a limited number per video, so
      // problems such as dropped frames can be read after the fact.
      player.stream.log.listen((log) {
        final text = log.text.trim();
        final subtitle = isSubtitleError(text) || log.prefix == 'sub' || log.prefix.startsWith('sub/');
        if ((log.level == 'error' || log.prefix == 'ytdl_hook') && _recentErrors.length < 20 && !subtitle && !isUnattributedHttpError(text)) _recentErrors.add(text);
        // curl gave up on a stream; when it was the video's, the sound
        // plays on over the last picture.
        if (log.prefix == 'curl' && text.startsWith('transfer failed')) _streamLostIn = _playSerial;
        if (_mpvLogLines >= 200) return;
        _mpvLogLines++;
        logInfo('mpv [${log.prefix}] ${log.level}: $text');
      }),
      // A stream that stops delivering data leaves mpv buffering forever.
      player.stream.buffering.listen((buffering) {
        _stallTimer?.cancel();
        if (!buffering || _tracking == null) return;
        _stallTimer = Timer(PlaybackRecovery.stallTimeout, () {
          if (player.state.buffering && player.state.playing) unawaited(_recover(tr('缓冲超过 {0} 秒没有进展', [PlaybackRecovery.stallTimeout.inSeconds])));
        });
      }),
    ]);
  }

  /// An mpv error that was not about a subtitle.
  void _onPlayerError(Player player, String message, {required bool loaded}) {
    if (!loaded) {
      final item = playing!;
      final viaRelay = _openedVia == item.id;
      _openedVia = null;
      // What a server's address says is not what YouTube said earlier.
      final failure = PlaybackFailure.classify(viaRelay ? [message] : [message, ..._recentErrors]);
      final position = _lastPosition > Duration.zero ? _lastPosition : null;
      if (viaRelay) {
        if (!failure.retryable && !_serversMayHelp(failure.kind)) {
          _fail(item, failure);
          return;
        }
        final limited = _youtubeRefused;
        logInfo('Piped or Invidious address did not play ($message); ${limited != null ? 'trying the next server' : 'connecting to YouTube directly'}');
        unawaited(limited != null ? _fallBack(item, _playSerial, limited, start: position) : _open(item, _playSerial, start: position, piped: false));
        return;
      }
      if (!failure.retryable) {
        _serversMayHelp(failure.kind) ? unawaited(_fallBack(item, _playSerial, failure, start: position)) : _fail(item, failure);
        return;
      }
      if (_openedResolved == item.id) {
        // Addresses resolved ahead may have gone stale; let libmpv's
        // ytdl_hook resolve the video itself once.
        _openedResolved = null;
        _repository?.streams.forget(item.id);
        logInfo('Prefetched address did not play ($message; $_openedOrigin); libmpv resolves ${item.id} again');
        unawaited(_open(item, _playSerial, start: _lastPosition > Duration.zero ? _lastPosition : null, resolved: false));
        return;
      }
      // Resolved again and still refused: the servers are the last way.
      _serversMayHelp(failure.kind) ? unawaited(_fallBack(item, _playSerial, failure, start: position)) : _fail(item, failure);
    } else if (PlaybackRecovery.isNetworkError(message)) {
      final failure = PlaybackFailure.classify([message, ..._recentErrors]);
      if (failure.retryable) {
        unawaited(_recover(message));
      } else {
        _fail(playing!, failure);
      }
    }
  }

  /// Follows [PlayerSettings.playOrder] once a video ends. Single cycle is
  /// mpv's loop-file, so a looping video never ends.
  Future<void> _playAfterEnd() async {
    final done = playing;
    if (done != null && preferences.watchLaterAutoRemove) library?.removeWatchLater(done.id);
    if (sleepAfterCurrent) {
      _update(() => sleepAfterCurrent = false);
      _notice(tr('定时关闭：当前视频已播完'));
      return;
    }
    if (await playQueued()) return;
    switch (settings.playOrder) {
      case PlayOrder.pause || PlayOrder.singleCycle:
        return;
      case PlayOrder.listOrder:
        if (upNext.isNotEmpty) await play(upNext.first, keepMini: true);
      case PlayOrder.listCycle:
        if (upNext.isNotEmpty) {
          await play(upNext.first, keepMini: true);
        } else if (queue.isNotEmpty) {
          await play(queue.first, keepMini: true, at: mini && queue.first.id == playing?.id ? Duration.zero : null);
        } else if (playing != null) {
          await play(playing!, keepMini: true, at: Duration.zero);
        }
      case PlayOrder.autoPlayRelated:
        await playNext(keepMini: true);
    }
  }

  /// Plays the next video in the queue, if there is one.
  Future<void> playNext({bool keepMini = false}) async {
    if (await playQueued(null, keepMini)) return;
    final next = upNext;
    final suggestions = relatedItems;
    if (next.isNotEmpty) {
      await play(next.first, keepMini: keepMini);
    } else if (suggestions.isNotEmpty) {
      await play(suggestions.first, from: suggestions, keepMini: keepMini);
    }
  }

  @visibleForTesting
  Future<void> playAfterEndForTest() => _playAfterEnd();

  /// 下一个播放: [item] goes to the front of [playQueue].
  void queueNext(VideoItem item) {
    _update(() => playQueue.addNext(item));
    _notice(tr('将在当前视频之后播放'));
  }

  /// 加入播放队列: [item] goes to the end of [playQueue].
  void queueLast(VideoItem item) {
    final added = playQueue.addLast(item);
    _update(() {});
    _notice(added ? tr('已加入播放队列') : tr('播放队列里已经有这个视频'));
  }

  void removeQueued(String id) => _update(() => playQueue.remove(id));

  void clearQueue() => _update(playQueue.clear);

  void moveQueued(int from, int to) => _update(() => playQueue.move(from, to));

  /// Plays [item], or the first of [playQueue], and takes it off the queue.
  /// The list the current video came from carries on after the queued ones.
  /// False when there was nothing to play.
  Future<bool> playQueued([VideoItem? item, bool keepMini = false]) async {
    final next = item ?? playQueue.items.firstOrNull;
    if (next == null) return false;
    _update(() => playQueue.remove(next.id));
    final at = playing == null ? -1 : queue.indexWhere((other) => other.id == playing!.id);
    final rest = [for (final other in queue) if (other.id != next.id) other];
    final from = at < 0 ? null : [...rest.take(at + 1), next, ...rest.skip(at + 1)];
    await play(next, from: from, keepMini: keepMini);
    return true;
  }

  /// The video before the current one in the queue, if it was opened from one.
  VideoItem? get previousInQueue {
    final current = playing;
    if (current == null) return null;
    final index = queue.indexWhere((item) => item.id == current.id);
    return index > 0 ? queue[index - 1] : null;
  }

  bool _backgroundAudioOnly = false;
  bool _windowHidden = false;
  bool? _efficient;

  /// Hidden and not playing, Lumtub runs in Windows' efficiency mode; any
  /// playback (a media key while hidden, too) turns it off.
  void _updateEfficiency() {
    final on = _windowHidden && !(player?.state.playing ?? false);
    if (on == _efficient) return;
    _efficient = on;
    NativeCore.efficiencyMode(on);
  }

  /// While the window is minimised or in the tray with the setting on, mpv
  /// decodes no picture; [hidden] false brings it back. A user's own 听视频
  /// choice is left alone.
  Future<void> setBackgroundAudioOnly(bool hidden) async {
    _outputSize?.hidden = hidden;
    _windowHidden = hidden;
    _updateEfficiency();
    final platform = player?.platform;
    if (platform is! NativePlayer) return;
    if (hidden) {
      if (!preferences.audioOnlyInBackground || audioOnly || _backgroundAudioOnly || !player!.state.playing) return;
      _backgroundAudioOnly = true;
      await platform.setProperty('vid', 'no');
    } else if (_backgroundAudioOnly) {
      _backgroundAudioOnly = false;
      if (audioOnly) return;
      await platform.setProperty('vid', 'auto');
      // The decoder starts again at the next keyframe, which in a stream can
      // be far off: until then the last picture stays. An exact seek to
      // here decodes up to now at once.
      try {
        await platform.command(['seek', '0', 'relative+exact']);
      } catch (e) {
        logInfo('Could not refresh the picture after restoring: $e');
      }
    }
  }

  /// Whether nothing will play once the current video ends.
  bool get stopsAfterEnd =>
      sleepAfterCurrent ||
      playQueue.isEmpty &&
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
      _notice(tr('定时关闭：已暂停播放'));
    });
    _update(() {
      sleepAt = after == null ? null : DateTime.now().add(after);
      sleepAfterCurrent = afterCurrent;
    });
  }

  bool get hasNext => playQueue.isNotEmpty || upNext.isNotEmpty || relatedItems.isNotEmpty;

  /// Videos played before the current one, the latest last.
  final _played = <VideoItem>[];

  bool get hasPrevious => _played.isNotEmpty || previousInQueue != null;

  /// Plays the video that was playing before this one, or else the one
  /// before it in the list it was opened from.
  Future<void> playPrevious() async {
    if (_played.isEmpty) {
      if (previousInQueue case final previous?) await play(previous);
      return;
    }
    final item = _played.removeLast();
    await play(item);
    // play() noted the video left behind; going back is not a new step.
    if (_played.isNotEmpty && _played.last.id == item.id) _played.removeLast();
  }

  /// yt-dlp's result for the playing video, when it was extracted already
  /// (storyboards and the replay heatmap come from it); null otherwise,
  /// for example when Piped or Invidious played it.
  Future<Map<String, dynamic>?> playingInfo() async {
    final id = playing?.id;
    final cached = id == null ? null : _repository?.streams.cached(id);
    if (cached == null) return null;
    try {
      return (await cached).info;
    } catch (_) {
      return null;
    }
  }

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

  /// A-B 循环: where the loop starts, then where it ends; mpv plays the
  /// part between them again and again.
  Duration? loopA;
  Duration? loopB;

  /// Steps the A-B loop on at the current position: the first press marks
  /// A, the second B and starts the loop, the third clears it.
  Future<void> markLoop() async {
    final player = this.player;
    if (player == null) return;
    final now = player.state.position;
    if (loopA == null || loopB != null) {
      final clearing = loopB != null;
      _update(() {
        loopA = clearing ? null : now;
        loopB = null;
      });
      await _applyLoop();
      return;
    }
    // B before A swaps them, so the loop still runs forwards.
    final a = loopA!;
    _update(() {
      loopA = now < a ? now : a;
      loopB = now < a ? a : now;
    });
    if (loopB! - loopA! < const Duration(milliseconds: 500)) {
      _update(() => loopB = null);
      return;
    }
    await _applyLoop();
    await player.seek(loopA!);
  }

  Future<void> clearLoop() async {
    if (loopA == null && loopB == null) return;
    _update(() {
      loopA = null;
      loopB = null;
    });
    await _applyLoop();
  }

  Future<void> _applyLoop() async {
    final platform = player?.platform;
    if (platform is! NativePlayer) return;
    String at(Duration? d) => d == null || loopB == null ? 'no' : (d.inMilliseconds / 1000).toStringAsFixed(3);
    await platform.setProperty('ab-loop-a', at(loopA));
    await platform.setProperty('ab-loop-b', at(loopB));
  }

  /// Plays [item] at its channel's remembered speed and volume, else at
  /// 默认倍速 and the volume chosen last.
  Future<void> _applyChannelPlayback(VideoItem item, Player player) async {
    _playbackChannel = null;
    final key = ChannelPlayback.keyOf(item);
    final saved = preferences.rememberChannelPlayback && key != null ? channelPlayback?.of(key) : null;
    final rate = saved?.rate ?? settings.defaultSpeed;
    if (rate != player.state.rate) await player.setRate(rate);
    // Said once, so a speed that came back on its own is not a surprise.
    if (saved?.rate case final kept? when kept != settings.defaultSpeed) _notice(tr('这个频道按上次的 {0}x 倍速播放', [rateText(kept)]));
    final volume = saved?.volume?.toDouble() ?? _sessionVolume;
    if (volume != null && volume != player.state.volume) await player.setVolume(volume.clamp(0.0, settings.volumeMax.toDouble()).toDouble());
    if (this.player == player && playing == item) _playbackChannel = key;
  }

  /// Keeps a speed or volume chosen while a channel plays for its next
  /// videos. Mute is not a volume to come back to.
  void _rememberPlayback({double? rate, double? volume}) {
    final key = _playbackChannel;
    if (volume != null && volume > 0 && key != null) _sessionVolume = volume;
    if (key == null || !preferences.rememberChannelPlayback) return;
    final store = channelPlayback;
    if (store == null) return;
    if (rate != null) {
      if (rate == store.of(key)?.rate) return;
      store.remember(key, rate: rate, forgetRate: rate == settings.defaultSpeed);
    } else if (volume != null && volume > 0 && volume.round() != store.of(key)?.volume) {
      store.remember(key, volume: volume.round());
    }
  }

  /// AI 总结 already made this session, by video id.
  final _summaries = <String, String>{};

  /// Whether [details] has subtitles other than 语音识别's.
  static bool hasOwnSubtitles(VideoDetails? details) => details?.subtitles.any((s) => s.kind != SubtitleKind.speech) ?? false;

  /// Whether 语音识别 has its address, model and key.
  bool get canRecognizeSpeech => speechReady(preferences.translation, translationKeys);

  Future<SubtitleOption?> _speechOptionFor(String videoId, VideoDetails details) async {
    if (hasOwnSubtitles(details)) return null;
    final saved = await speechStore?.of(videoId);
    return saved == null ? null : SubtitleOption(language: saved.language, name: '', url: saved.file.uri.toString(), kind: SubtitleKind.speech);
  }

  /// Shows [speech], or its translation into 第一字幕语言, unless subtitles
  /// are off.
  Future<void> _showSpeech(SubtitleOption speech, int serial) async {
    if (settings.subtitleMode == SubtitleMode.off || serial != _playSerial) return;
    final first = settings.subtitleLanguage.translation;
    final option = settings.subtitleOriginal || speaks(speech.language, first) ? speech : translationOf([speech], first) ?? speech;
    await showSubtitle(option);
  }

  /// Makes subtitles for the video playing from its audio (语音识别), shows
  /// them and keeps them for next time. The audio goes to the service set
  /// up under 翻译与 AI only now, when asked. With [withFfmpeg] a long video
  /// installs ffmpeg, the one downloads use, to be cut; without it that
  /// throws [SpeechNeedsFfmpeg] and the audio is kept for the next try.
  Future<SubtitleOption> recognizeSpeech({bool withFfmpeg = false}) async {
    final item = playing;
    final details = this.details;
    final repository = _repository;
    final paths = this.paths;
    final store = speechStore;
    if (item == null || details == null || repository == null || paths == null || store == null) throw TranslationException(tr('没有正在播放的视频'));
    if (speechJob.value != null) throw TranslationException(tr('正在识别另一个视频，请稍候'));
    final config = preferences.translation;
    if (!canRecognizeSpeech) throw TranslationException(tr('请先在“翻译与 AI”里设置语音识别接口和密钥'));
    final recognizer = SpeechRecognizer(_http, baseUrl: config.effectiveSpeechBaseUrl, key: speechKeyFor(config, translationKeys), model: config.effectiveSpeechModel);
    final serial = _playSerial;
    final folder = Directory('${(directories?.cache ?? Directory.systemTemp).path}${Platform.pathSeparator}speech-${item.id}');
    void stage(String text, [int done = 0, int total = 0]) => speechJob.value = (videoId: item.id, stage: text, done: done, total: total);
    var keepAudio = false;
    Future<List<SpeechPart>> fetch() {
      final ffmpegDir = downloads?.ffmpegDirectory?.call();
      return SpeechAudio.fetch(
        item.id,
        folder,
        ytDlp: repository.ytDlpPath,
        environment: repository.processEnvironment,
        proxy: proxy.ytDlpValue(settings.proxyMode),
        cacheDirectory: repository.cacheDirectory,
        deno: paths.deno,
        ffmpeg: ffmpegDir == null ? null : '$ffmpegDir${Platform.pathSeparator}${Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg'}',
      );
    }

    try {
      stage(tr('正在下载音频…'));
      List<SpeechPart> parts;
      try {
        parts = await fetch();
      } on SpeechNeedsFfmpeg {
        if (!withFfmpeg) {
          keepAudio = true;
          rethrow;
        }
        stage(tr('正在安装 ffmpeg…'));
        if (!await installFfmpeg()) throw TranslationException(tr('ffmpeg 没装好，无法分段识别'));
        stage(tr('正在下载音频…'));
        parts = await fetch();
      }
      final hint = details.language?.split('-').first.toLowerCase();
      final answers = List<({Duration offset, Map<String, dynamic> answer})?>.filled(parts.length, null);
      var done = 0;
      var next = 0;
      stage(tr('正在识别语音…'), 0, parts.length);
      // Two parts at a time: twice as fast without the burst a free tier
      // answers with 429.
      Future<void> worker() async {
        while (next < parts.length) {
          final i = next++;
          answers[i] = (offset: parts[i].offset, answer: await recognizer.transcribe(parts[i].file, language: hint));
          stage(tr('正在识别语音…'), ++done, parts.length);
        }
      }

      await Future.wait([for (var i = 0; i < min(2, parts.length); i++) worker()]);
      final heard = [for (final a in answers) a!];
      final vtt = await speechVtt(heard);
      if (!vtt.contains('-->')) throw TranslationException(tr('没有识别出说话的内容'));
      final language = (hint == null || hint.isEmpty ? null : details.language) ?? speechLanguageTag(heard.first.answer['language']) ?? 'und';
      final file = await store.save(item.id, language, vtt);
      logInfo('Recognized speech of ${item.id} in ${parts.length} part(s)');
      final option = SubtitleOption(language: language, name: '', url: file.uri.toString(), kind: SubtitleKind.speech);
      if (serial == _playSerial && playing?.id == item.id) {
        _summaries.remove(item.id);
        _update(() => this.details = this.details?.withSpeechSubtitle(option));
        await _showSpeech(option, serial);
      }
      return option;
    } on TranslationException {
      rethrow;
    } catch (e) {
      logError('Speech recognition failed for ${item.id}', e);
      throw TranslationException(tr('语音识别失败：{0}', [e]));
    } finally {
      speechJob.value = null;
      try {
        if (!keepAudio && await folder.exists()) await folder.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Forgets [videoId]'s AI 总结, so the next one is made again.
  void forgetSummary(String videoId) => _summaries.remove(videoId);

  String? summaryOf(String id) => _summaries[id];

  /// Whether AI 总结 has an AI service to ask.
  bool get canSummarize => aiServiceFor(preferences.translation, translationKeys, _http) != null;

  /// AI 总结 of the video playing, from its subtitles in its own language,
  /// by the AI service set up under 翻译服务. Only the transcript and the
  /// title are sent, and only when asked.
  Future<String> summarize({void Function(int done, int total)? onProgress}) async {
    final item = playing;
    final details = this.details;
    if (item == null) throw TranslationException(tr('没有正在播放的视频'));
    if (_summaries[item.id] case final done?) return done;
    final ai = aiServiceFor(preferences.translation, translationKeys, _http);
    if (ai == null) throw TranslationException(tr('请先在“翻译与 AI”里设置 AI 接口和密钥'));
    final subtitles = details?.subtitles ?? const <SubtitleOption>[];
    final option = originalSubtitle(subtitles, language: details?.language) ?? subtitles.firstOrNull;
    final title = details?.title.isNotEmpty == true ? details!.title : item.title;
    final String summary;
    if (option == null) {
      // No subtitles, not even YouTube's automatic ones: the description
      // and chapters are all there is to go on.
      final description = details?.description ?? '';
      final chapters = [for (final c in details?.chapters ?? const <Chapter>[]) (start: c.start, title: c.title)];
      if (!canSummarizeDescription(description, chapters)) throw TranslationException(tr('这个视频没有字幕，简介也太短，无法总结'));
      summary = await summarizeDescription(ai, title, description, chapters);
      logInfo('Summarized ${item.id} from its description');
    } else {
      final source = await File(await _subtitleFile(option)).readAsString();
      final transcript = await summaryTranscript(source);
      summary = await summarizeTranscript(ai, title, transcript, onProgress: onProgress);
      logInfo('Summarized ${item.id} from ${transcript.chunks.length} part(s)');
    }
    if (_summaries.length >= 30) _summaries.remove(_summaries.keys.first);
    return _summaries[item.id] = summary;
  }

  /// Counts the time played up to now into 观看统计, before it is shown.
  void flushWatchTime() => _countWatchTime(flush: true);

  /// Adds the time played since the last call to 观看统计, a minute or
  /// a pause at a time; nothing in 无痕模式 or with history off.
  void _countWatchTime({bool flush = false}) {
    final player = this.player;
    final item = _tracking;
    final now = DateTime.now();
    final last = _watchTick;
    final playing = player != null && player.state.playing && !player.state.buffering && item != null;
    _watchTick = playing ? now : null;
    if (last != null) {
      final gap = now.difference(last).inMilliseconds;
      // A long gap is a sleep or a stall, not watching.
      if (gap > 0 && gap < 5000) _watchMs += gap;
    }
    if (_watchMs < 60000 && !(flush || !playing) || _watchMs < 1000) return;
    final seconds = _watchMs ~/ 1000;
    _watchMs -= seconds * 1000;
    final key = item == null ? null : ChannelPlayback.keyOf(item);
    if (key == null || !preferences.recordHistory || incognito) return;
    watchTime?.add(key, item!.channel, seconds);
  }

  Future<void> changeVolume(double delta) async {
    final player = this.player;
    if (player != null) await player.setVolume((player.state.volume + delta).clamp(0.0, settings.volumeMax.toDouble()).toDouble());
  }

  /// The video's brightness, -100 to 100, as 画面与音画同步调节 keeps it.
  int get brightness => settings.picture['brightness'] ?? 0;
  Timer? _brightnessSave;

  /// Brightens or darkens the video by [delta] and returns the new value;
  /// saved, and shown to the rest of the app, once the changes pause, not
  /// at every wheel notch or slide step.
  Future<int> changeBrightness(int delta) async {
    final value = (brightness + delta).clamp(-100, 100);
    settings = settings.copyWith(picture: {...settings.picture, 'brightness': value});
    _brightnessSave?.cancel();
    _brightnessSave = Timer(const Duration(seconds: 1), () {
      _update(() {});
      unawaited(_settingsStore?.save(settings));
    });
    final platform = player?.platform;
    if (platform is NativePlayer) await platform.setProperty('brightness', '$value');
    return value;
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
  /// Sets the quality cap; [asDefault] when it was chosen in the settings
  /// rather than for the video playing.
  Future<void> setMaxHeight(int height, {bool asDefault = false}) async {
    // 自动 again lifts the quality lowered for dropped frames.
    if (height == 0 && _droppedCap > 0) {
      _droppedCap = 0;
      if (settings.maxHeight == 0) return reloadVideo();
    }
    if (height == settings.maxHeight) return;
    // Automatic codecs follow the quality: above 1080p VP9 stays enabled.
    final next = settings.copyWith(maxHeight: height);
    if (height > 1080) {
      final usable = [VideoCodec.vp9, VideoCodec.av1].where((codec) => !next.disabledCodecs.contains(codec));
      if (usable.isEmpty) {
        if (asDefault) _notice(tr('VP9 和 AV1 都已禁用，H.264 最高只能到 1080p'));
      } else if (!usable.any((codec) => FormatPolicy.hardware(next, codec))) {
        _notice(tr('这台电脑不能硬解 VP9 和 AV1，1440p 和 4K 只能用 CPU 软解，占用会很高'));
      }
    }
    await reloadVideo(next);
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

  String get _format => FormatPolicy.expression(_playback);

  String? get _formatSort => FormatPolicy.formatSort(_playback);

  /// [settings] as playback picks streams with them: automatic quality is
  /// capped at the tallest display.
  PlayerSettings get _playback {
    final playback = FormatPolicy.forDisplay(settings, _displayHeight);
    if (_droppedCap == 0 || settings.maxHeight != 0 || (playback.maxHeight > 0 && playback.maxHeight <= _droppedCap)) return playback;
    return playback.copyWith(maxHeight: _droppedCap);
  }

  int get _displayHeight {
    var tallest = 0.0;
    for (final display in PlatformDispatcher.instance.displays) {
      tallest = max(tallest, display.size.height);
    }
    return tallest.round();
  }

  /// Starts resolving [item] before it is opened, such as when the pointer
  /// rests on its card ([hover]). Not on hover while a video plays: the
  /// yt-dlp run would take CPU from the playback for a guess.
  void prefetch(VideoItem item, {bool hover = false}) {
    // Each one starts yt-dlp; on battery only the next video in line is.
    if (hover && Power.saving) return;
    if (hover && player?.state.playing == true) return;
    if (ready && playing?.id != item.id && DateTime.now().isAfter(_rateLimitedUntil)) _repository?.streams.prefetch(item.id, _format, formatSort: _formatSort);
  }

  Future<void> _loadDetails(VideoItem item, int serial) async {
    try {
      VideoDetails loaded;
      final local = await downloads?.localVideo(item.id);
      if (local != null && local.info['title'] != null) {
        // Saved with the download, so the page works offline.
        loaded = VideoDetails.fromJson(local.info);
      } else {
        try {
          // The extraction playback uses carries the details too.
          final resolved = await _repository!.streams.resolve(item.id, _format, formatSort: _formatSort);
          loaded = resolved.details;
          if (serial == _playSerial) {
            _update(() => availableHeights = resolved.heightsFor(settings));
            final lost = resolved.lostToDisabled(settings, _playback.maxHeight);
            if (lost != null) {
              _notice(tr('这个视频的 {0}p 只有 {1}，已被禁用，正在播放 {2}p', [lost.height, lost.codecs.map((c) => c.label).join(' / '), lost.playing]));
            }
          }
        } catch (e) {
          // A second yt-dlp would meet the same 429, or the same network
          // the first one already tried twice.
          if (DateTime.now().isBefore(_rateLimitedUntil) || RegExp(r'\b429\b|Too Many Requests').hasMatch('$e') || StreamResolver.isTransient(e)) rethrow;
          loaded = await _repository!.details(item.id);
        }
      }
      // A video with no subtitles keeps the ones 语音识别 made for it.
      final speech = await _speechOptionFor(item.id, loaded);
      if (speech != null) loaded = loaded.withSpeechSubtitle(speech);
      if (serial == _playSerial) {
        _update(() {
          details = loaded;
          if (preferences.showRelated) related = _relatedTo(item, loaded.title.isNotEmpty ? loaded.title : item.title);
        });
        // Once yt-dlp names the start time, wait for it rather than poll.
        if (waitingForStart && item.scheduledStart == null && loaded.scheduledStart != null) _waitForStart(item);
        unawaited(_localizeDetails(item.id, serial));
        if (speech != null && loaded.subtitles.length == 1) {
          unawaited(_showSpeech(speech, serial));
        } else {
          unawaited(_autoSubtitles(item, loaded, serial));
        }
      }
    } catch (_) {
      // The page still shows what the list already knew about the video.
    } finally {
      if (serial == _playSerial) _update(() => loadingDetails = false);
    }
  }

  /// yt-dlp asks YouTube in English, as it reads view counts and dates
  /// only in English; the title, description and chapter names are then
  /// fetched again in the interface language.
  Future<void> _localizeDetails(String videoId, int serial) async {
    final text = await relatedVideos.textFor(videoId);
    final current = details;
    if (text == null || current == null || serial != _playSerial) return;
    _update(() => details = current.localized(text.title, text.description, likes: text.likes));
  }

  VideoListLoader _relatedTo(VideoItem item, String title) {
    final repository = _repository!;
    // Long titles make poor queries; the first words carry the topic.
    final query = title.length > 60 ? title.substring(0, 60) : title;
    // YouTube's own suggestions come with the /next request the localized
    // title already makes; a search on the title stands in without them.
    final loader = VideoListLoader(
      () => repository.videosOr(() => relatedVideos.forVideo(item.id), query),
      pageSize: 13,
      limit: 12,
      where: (other) => other.id != item.id && !preferences.blocksGroup(other) && !preferences.isUnrecommended(other.channelId),
    )..addListener(_passOn('related'));
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

  /// Stops the video and closes the watch page or the mini player.
  void stopWatching() {
    _stopCurrentChat();
    setPip(false);
    _finishWatching();
    _saveProgress(now: true);
    _countWatchTime(flush: true);
    _playbackChannel = null;
    _tracking = null;
    _recoveryTimer?.cancel();
    _startTimer?.cancel();
    _recovery.reset();
    ++_playSerial;
    _update(() {
      playing = null;
      mini = false;
      playbackError = null;
      _waitingForStart = false;
    });
    _unload();
  }

  /// Closes the video in libmpv rather than pausing it, so its cache,
  /// decoded frames and textures are freed, then hands the freed memory back
  /// to Windows. Coming back to the video opens it again where it was left.
  void _unload() {
    final player = this.player;
    if (player == null) return;
    unawaited(player.stop().then((_) => releaseMemory()));
  }

  /// Hands memory freed by closed videos back to Windows.
  void releaseMemory() {
    if (!Platform.isWindows) return;
    final before = ProcessInfo.currentRss;
    releaseFreedMemory();
    logInfo('Released idle memory: ${before >> 20} MB → ${ProcessInfo.currentRss >> 20} MB');
  }

  /// Opens [target]; 返回 comes back to where this was.
  void navigate(PageMode target) {
    if (target != mode || onWatchPage) _remember();
    _go(target);
  }

  void _go(PageMode target) {
    setPip(false);
    final keep = _keepsPlaying;
    if (!keep) {
      if (playing != null) _finishWatching();
      _tracking = null;
      _recoveryTimer?.cancel();
      _recovery.reset();
      ++_playSerial;
    }
    if (target == PageMode.home) unawaited(refreshHomeFeed());
    _saveProgress(now: true);
    if (target == PageMode.subscriptions && preferences.feedAutoRefresh) {
      unawaited(library?.refreshFeed(interval: Duration(minutes: preferences.feedRefreshMinutes)));
    }
    _update(() {
      mode = target;
      if (keep) {
        mini = true;
      } else {
        playing = null;
        playbackError = null;
      }
    });
    if (!keep) _unload();
  }

  /// What is on screen now, as 返回 would come back to it.
  BackEntry get _here {
    final video = playing;
    if (video != null && !mini) {
      final state = player?.state;
      // A video that had finished starts over rather than ending again.
      final ended = state == null || (state.duration > Duration.zero && state.position > state.duration - const Duration(seconds: 5));
      return BackEntry.video(video, mode: mode, position: ended ? null : state.position, queue: queue);
    }
    return BackEntry.page(mode, query: _query, channel: channel, channelTab: channelTab, playlistId: openPlaylistId, youtubePlaylist: youtubePlaylist);
  }

  void _remember() {
    if (!_restoring && ready) _back.push(_here);
  }

  /// Whether 返回 has somewhere to go.
  bool get canGoBack => !_back.isEmpty || onWatchPage || _query != null || mode != PageMode.home || channelQuery != null;

  /// Goes back to the previous page or video: a search inside a channel is
  /// cleared first; with nothing earlier it closes the video, then the
  /// search, then goes home.
  void goBack() {
    if (!onWatchPage && mode == PageMode.channel && channelQuery != null) return searchChannel('');
    BackEntry? entry;
    do {
      entry = _back.pop();
    } while (entry != null && !onWatchPage && entry.same(_here));
    _restoring = true;
    try {
      if (entry != null) {
        _restore(entry);
      } else if (onWatchPage) {
        // Nothing earlier: leave the watch page for the page under it.
        _go(mode);
      } else if (_query != null) {
        clearSearch();
      } else if (mode != PageMode.home) {
        _go(PageMode.home);
      }
    } finally {
      _restoring = false;
    }
  }

  void _restore(BackEntry entry) {
    final video = entry.video;
    if (video != null) {
      if (mini && playing?.id == video.id) return expandMini();
      unawaited(play(video, from: entry.queue.isEmpty ? null : entry.queue, at: entry.position));
      return;
    }
    switch (entry.mode) {
      case PageMode.explore:
        final query = entry.query;
        if (query == null) {
          openExplore();
        } else if (query == _query) {
          _go(PageMode.explore);
        } else {
          unawaited(search(query));
        }
      case PageMode.channel:
        final ref = entry.channel;
        if (ref == null) return _go(PageMode.home);
        if (ref.id != channel?.id) {
          openChannel(ref);
        } else {
          _go(PageMode.channel);
        }
        if (entry.channelTab != channelTab) setChannelTab(entry.channelTab);
      case PageMode.youtubePlaylist:
        final playlist = entry.youtubePlaylist;
        if (playlist == null) return _go(PageMode.home);
        if (playlist.id != youtubePlaylist?.id) {
          openYoutubePlaylist(playlist);
        } else {
          _go(PageMode.youtubePlaylist);
        }
      case PageMode.playlist:
        final id = entry.playlistId;
        if (id == null) return _go(PageMode.home);
        openPlaylist(id);
      case final mode:
        _go(mode);
    }
  }

  /// Opens [ref]'s page with its uploads.
  void openChannel(ChannelRef ref) {
    final repository = _repository;
    if (repository == null) return;
    _remember();
    channelVideos?.dispose();
    channelPosts?.dispose();
    channelPosts = null;
    channel = ref;
    channelQuery = null;
    channelTab = ChannelTab.videos;
    channelVideos = VideoListLoader(() => repository.channelVideos(ref))
      ..addListener(_passOn('channel'))
      ..loadMore();
    _go(PageMode.channel);
  }

  /// Shows another tab of the open channel.
  void setChannelTab(ChannelTab tab) {
    final repository = _repository;
    final ref = channel;
    if (repository == null || ref == null) return;
    _update(() {
      channelTab = tab;
      channelQuery = null;
      channelVideos?.dispose();
      channelVideos = null;
      channelPosts?.dispose();
      channelPosts = null;
      if (tab == ChannelTab.posts) {
        channelPosts = PostsLoader(_posts, ref)..addListener(_passOn('channel'));
        unawaited(channelPosts!.loadMore());
      } else {
        channelVideos = VideoListLoader(() => repository.channelTab(ref, tab))
          ..addListener(_passOn('channel'))
          ..loadMore();
      }
    });
  }

  /// Opens a YouTube playlist's page.
  void openYoutubePlaylist(PlaylistResult playlist) {
    final repository = _repository;
    if (repository == null) return;
    _remember();
    youtubePlaylistVideos?.dispose();
    youtubePlaylist = playlist;
    final feed = tvFeed;
    final signedIn = feed != null && feed.available && _isAccountPlaylist(playlist);
    youtubePlaylistVideos = VideoListLoader(() => signedIn ? Listing(() => feed.lines('VL${playlist.id}', pages: 50)) : repository.playlist(playlist.id), pageSize: 50)
      ..addListener(_passOn('channel'))
      ..loadMore();
    _go(PageMode.youtubePlaylist);
  }

  /// Searches the open channel's videos for [query]; an empty query lists
  /// the uploads again.
  /// What a search inside the channel covers: null for YouTube's own
  /// channel search, else one tab whose titles are filtered.
  ChannelTab? channelSearchTab;

  /// Searches the open channel; an empty [query] lists the tab again.
  void searchChannel(String query, {ChannelTab? within}) {
    final repository = _repository;
    final ref = channel;
    if (repository == null || ref == null) return;
    final text = query.trim();
    _update(() {
      channelVideos?.dispose();
      channelVideos = null;
      channelPosts?.dispose();
      channelPosts = null;
      channelQuery = text.isEmpty ? null : text;
      channelSearchTab = text.isEmpty ? null : within;
      if (text.isEmpty) {
        // Back to the tab that was open.
        if (channelTab == ChannelTab.posts) {
          channelPosts = PostsLoader(_posts, ref)..addListener(_passOn('channel'));
          unawaited(channelPosts!.loadMore());
        } else {
          final tab = channelTab;
          channelVideos = VideoListLoader(() => repository.channelTab(ref, tab))
            ..addListener(_passOn('channel'))
            ..loadMore();
        }
        return;
      }
      final words = text.toLowerCase().split(RegExp(r'\s+'));
      bool matches(String title) {
        final lower = title.toLowerCase();
        return words.every(lower.contains);
      }

      if (within == ChannelTab.posts) {
        channelPosts = PostsLoader(_posts, ref, matches: matches)..addListener(_passOn('channel'));
        unawaited(channelPosts!.loadMore());
      } else {
        channelVideos = (within == null
            ? VideoListLoader(() => repository.channelSearch(ref, text))
            : VideoListLoader(() => repository.channelTab(ref, within), matches: matches))
          ..addListener(_passOn('channel'))
          ..loadMore();
      }
    });
  }

  void openPlaylist(String id) {
    _remember();
    openPlaylistId = id;
    _go(PageMode.playlist);
  }

  void retrySearch() {
    final last = _query;
    if (last != null) unawaited(search(last));
  }

  SearchSort searchSort = SearchSort.relevance;
  SearchUploadDate searchDate = SearchUploadDate.any;
  SearchDuration searchDuration = SearchDuration.any;

  /// Searches again with another order, upload date or length.
  void setSearchOptions({SearchSort? sort, SearchUploadDate? date, SearchDuration? duration}) {
    searchSort = sort ?? searchSort;
    searchDate = date ?? searchDate;
    searchDuration = duration ?? searchDuration;
    retrySearch();
  }

  /// 为你推荐 on the home page.
  HomeFeed? homeFeed;
  late final relatedVideos = YoutubeRelated(_http);

  /// Gathers recommendations again when they are old, or when [force]d;
  /// with [keep], the videos shown stay and new ones follow them.
  Future<void> refreshHomeFeed({bool force = false, bool keep = false}) async {
    final feed = homeFeed;
    final repository = _repository;
    final library = this.library;
    if (feed == null || repository == null || !preferences.homeShowRecommended || preferences.focusHideHome || feed.loading) return;
    if (!force && !feed.stale && feed.items.isNotEmpty) return;
    // The last launch's feed shows while a new one is gathered.
    await feed.restore(filter: visible);
    if (!force && !preferences.homeAutoRefresh && feed.items.isNotEmpty) return;
    if (library != null && library.channels.isNotEmpty && library.feed.isEmpty) {
      await library.refreshFeed().timeout(const Duration(seconds: 20), onTimeout: () {});
    }
    feed.mix = preferences.feedMix;
    await feed.refresh(await _homeSources(repository), filter: visible, keep: keep);
  }

  /// The next page of 为你推荐, as the home page scrolls to its end.
  Future<void> loadMoreHomeFeed() async {
    final feed = homeFeed;
    if (feed == null) return;
    // Kept from the last launch without refreshing: gather now, after it.
    if (!feed.gathered) return refreshHomeFeed(force: true, keep: true);
    await feed.loadMore();
  }

  /// The video being watched, to learn from once it is left.
  VideoItem? _watching;

  /// Tells 为你推荐 about the video just left: watched a while, it steers
  /// what comes next; left within seconds, it counts against its channel.
  void _finishWatching() {
    final item = _watching;
    _watching = null;
    if (item != null) _reportWatchedToYoutube(item);
    final feed = homeFeed;
    final repository = _repository;
    final player = this.player;
    if (item == null || feed == null || repository == null || player == null || !preferences.homeShowRecommended || incognito) return;
    final position = player.state.position;
    final duration = player.state.duration;
    final fraction = duration > Duration.zero ? position.inMilliseconds / duration.inMilliseconds : 0.0;
    final skipped = position < const Duration(seconds: 15) && fraction < 0.1;
    if (!skipped && position < const Duration(seconds: 30) && fraction < 0.3) return;
    unawaited(() async {
      await feed.learn(item, await _homeSources(repository), skipped: skipped);
    }());
  }

  /// 观看记录同步到 YouTube: adds the video just left to the account's
  /// history, as SmartTube does: from the start for the first three minutes,
  /// else where it was left; nearly finished marks it watched.
  void _reportWatchedToYoutube(VideoItem item) {
    final sign = tvSignIn;
    final player = this.player;
    if (sign == null || !sign.signedIn || player == null || !preferences.syncHistoryToYoutube || !preferences.recordHistory || incognito) return;
    final to = player.state.position.inMilliseconds / 1000;
    if (to < 5) return;
    final length = player.state.duration.inMilliseconds / 1000;
    unawaited(() async {
      final why = await sign.reportWatched(item.id, from: to < 180 ? 0 : to, to: to, length: length);
      if (why != null) logInfo('Could not add ${item.id} to the YouTube history: $why');
    }());
  }

  Future<HomeFeedSources> _homeSources(VideoRepository repository) async {
    final library = this.library;
    final weekly = searchParams(type: SearchFilter.videos, sort: SearchSort.views, date: SearchUploadDate.week);
    return HomeFeedSources(
        history: history,
        progressOf: library?.progressOf,
        favorites: [...?library?.favorites, ...?account?.likedVideos.take(50)],
        followed: library?.channels ?? const [],
        subscriptions: library?.feed ?? const [],
        searches: preferences.recordHistory ? await searchHistory?.items() ?? const [] : const [],
        youtubeHome: tvFeed?.available ?? false ? () => tvFeed!.videos(YoutubeTvFeed.home, limit: 40) : null,
        related: relatedVideos.forVideo,
        channelUploads: library?.uploadsOf ?? (_) async => const [],
        search: (query) async {
          final listing = repository.search(query, sp: weekly);
          try {
            return (await listing.next(10).toList()).whereType<VideoItem>().toList();
          } finally {
            listing.close();
          }
        },
      );
  }

  /// Follows or unfollows [channel] here, and on YouTube when signed in
  /// and [AppPreferences.syncFollowToYoutube]. Returns whether it is
  /// followed now.
  bool toggleFollow(ChannelRef channel) {
    final library = this.library;
    if (library == null) return false;
    final following = library.toggleFollow(channel);
    final account = this.account;
    if (account != null && account.canWrite && preferences.syncFollowToYoutube) unawaited(account.setSubscribed(channel, following));
    return following;
  }

  /// 换一批.
  void shuffleHomeFeed() {
    homeFeed?.mix = preferences.feedMix;
    homeFeed?.shuffle(filter: visible);
  }

  /// 不感兴趣: hides [item] and shows less from its channel.
  Future<void> dismissRecommendation(VideoItem item) async {
    await homeFeed?.dismiss(item);
    _notice(tr('将减少推荐类似内容'));
  }

  Future<void> clearNotInterested() async {
    await homeFeed?.notInterested.clear();
    _notice(tr('已清空“不感兴趣”记录'));
  }

  /// Words typed before, newest first, and YouTube's suggestions.
  SearchHistory? searchHistory;
  late final searchSuggestions = SearchSuggestions(_http);

  /// Shows the current search's results of another kind.
  void setSearchFilter(SearchFilter filter) {
    final last = _query;
    if (last != null && filter != searchFilter) unawaited(search(last, filter: filter));
  }

  Future<void> clearSearchHistory() async {
    await searchHistory?.clear();
    _notice(tr('搜索记录已清空。'));
  }

  /// Forgets the videos with these [ids] from the watch history.
  Future<void> removeFromHistory(Set<String> ids) async {
    await _history?.remove(ids);
    _update(() {});
  }

  Future<void> clearHistory() async {
    await _history?.clear();
    _update(() {});
    _notice(tr('观看历史已清空。'));
  }

  /// Videos of [items] that pass the privacy and content filters. The
  /// subscriptions feed is filtered only when [AppPreferences.filterSubscriptions].
  List<VideoItem> visible(List<VideoItem> items, {bool subscriptions = false, bool search = false}) {
    final prefs = preferences;
    // Pages filter their lists on every rebuild, and a feed runs to a
    // thousand items: the answer is kept while the list and the preferences
    // stay. Hiding watched videos also follows which videos are finished.
    final key = (prefs, subscriptions, search, search ? _query : null, prefs.hideWatched ? (library?.store, library?.store.finishedVersion) : null);
    if (_visible[items] case (final known, final kept) when known == key) return kept;
    final kept = _filter(items, prefs, subscriptions: subscriptions, search: search);
    _visible[items] = (key, kept);
    return kept;
  }

  final _visible = Expando<(Object, List<VideoItem>)>();

  List<VideoItem> _filter(List<VideoItem> items, AppPreferences prefs, {required bool subscriptions, required bool search}) {
    if (subscriptions && !prefs.filterSubscriptions) return items.where((item) => !prefs.isBlocked(item.channelId)).toList();
    final library = this.library;
    // Blocked groups show in a search only for their channel's exact name,
    // channels not to recommend in any search; followed channels are the
    // user's choice and stay.
    bool hidden(VideoItem item) =>
        !subscriptions &&
        ((prefs.blocksGroup(item) && !(search && isExactName(item.channel, _query))) || (!search && prefs.isUnrecommended(item.channelId)));
    return items.where((item) => !hidden(item) && prefs.shows(item, watched: library?.progressOf(item.id)?.finished ?? false)).toList();
  }

  Future<void> savePreferences(AppPreferences next) async {
    final service = next.translation != preferences.translation;
    _update(() => preferences = next);
    if (service) _useTranslator();
    try {
      await _preferencesStore?.save(next);
    } on FileSystemException {
      _notice(tr('设置未能保存，本次运行仍然生效。'));
    }
  }

  Future<void> _loadTranslationKeys() async {
    final saved = await _translationKeyFile?.read();
    if (saved == null) return;
    translationKeys = {for (final MapEntry(:key, :value) in saved.entries) if (value is String && value.isNotEmpty) key: value};
    _useTranslator();
    _update(() {});
  }

  void _useTranslator() {
    translator = CachingTranslator(translatorFor(preferences.translation, translationKeys, _http, fallback: _google), _translationCache, preferences.translation.cacheScope);
    logInfo('Translating with ${preferences.translation.service.name}');
  }

  /// Saves the API key of [service]; an empty one removes it.
  Future<void> saveTranslationKey(TranslationService service, String key) => saveApiKey(service.name, key);

  /// Saves the API key kept under [name] (a [TranslationService.name], or
  /// `speech` for 语音识别); an empty one removes it.
  Future<void> saveApiKey(String name, String key) async {
    final keys = {...translationKeys}..remove(name);
    if (key.trim().isNotEmpty) keys[name] = key.trim();
    _update(() => translationKeys = keys);
    _useTranslator();
    try {
      final file = _translationKeyFile;
      if (file == null) return;
      keys.isEmpty ? await file.delete() : await file.write(keys);
    } catch (e) {
      logError('Could not save the translation key', e);
      _notice(tr('密钥未能保存，本次运行仍然生效。'));
    }
  }

  /// The models the chosen AI endpoint lists.
  Future<List<String>> listAiModels() {
    final config = preferences.translation;
    return AiTranslator.listModels(_http, config.effectiveAiBaseUrl, translationKeys[TranslationService.ai.name] ?? '');
  }

  /// A one-line answer from the AI interface, to check it works whichever
  /// service translates.
  Future<String> testAi() async {
    final ai = aiServiceFor(preferences.translation, translationKeys, _http);
    if (ai == null) throw TranslationException(tr('请先填写 AI 接口的地址、模型和密钥'));
    final answer = await ai.complete('Answer in one short sentence.', 'Say hello and name the model you are.');
    return answer.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  }

  /// A short sentence put through the chosen service, to check it works.
  Future<String> testTranslation() => (translator is CachingTranslator ? (translator as CachingTranslator).inner : translator).translate('Subtitles and comments can be translated here.', preferences.translateTarget);

  void blockChannel(ChannelRef channel) {
    if (preferences.isBlocked(channel.id)) return;
    unawaited(savePreferences(preferences.copyWith(blockedChannels: [...preferences.blockedChannels, channel])));
    _notice(tr('已屏蔽“{0}”，可在 设置 › 隐私设置 中解除', [channel.name.isEmpty ? channel.id : channel.name]));
  }

  /// Blocks a channel the user typed in: a link or id with its `UC…` id,
  /// else its exact name. Returns what was blocked, or null if nothing.
  String? blockChannelTyped(String text) {
    final typed = text.trim();
    if (typed.isEmpty) return null;
    final id = RegExp(r'UC[\w-]{22}').firstMatch(typed)?[0];
    if (id != null) {
      if (!preferences.isBlocked(id)) unawaited(savePreferences(preferences.copyWith(blockedChannels: [...preferences.blockedChannels, ChannelRef(id, '')])));
      return id;
    }
    if (!preferences.isBlockedName(typed)) unawaited(savePreferences(preferences.copyWith(blockedChannelNames: [...preferences.blockedChannelNames, typed])));
    return typed;
  }

  void unblockChannelName(String name) =>
      unawaited(savePreferences(preferences.copyWith(blockedChannelNames: preferences.blockedChannelNames.where((n) => n != name).toList())));

  /// Stops or resumes recommending [channel]'s videos.
  void setRecommendChannel(ChannelRef channel, bool recommend) {
    final rest = preferences.unrecommendedChannels.where((c) => c.id != channel.id).toList();
    unawaited(savePreferences(preferences.copyWith(unrecommendedChannels: recommend ? rest : [...rest, channel])));
    final name = channel.name.isEmpty ? channel.id : channel.name;
    _notice(recommend ? tr('已恢复推荐“{0}”', [name]) : tr('不再推荐“{0}”的视频，搜索和关注不受影响', [name]));
  }

  void unblockChannel(String id) =>
      unawaited(savePreferences(preferences.copyWith(blockedChannels: preferences.blockedChannels.where((c) => c.id != id).toList())));

  void clearProgress() {
    library?.clearProgress();
    _notice(tr('播放进度已清空。'));
  }

  /// Reads the Windows accent colour for [AppearanceSettings.systemAccent].
  Future<void> refreshWindowsAccent() async {
    final color = await readWindowsAccent();
    if (color != null && color != windowsAccent) _update(() => windowsAccent = color);
  }

  /// Settings as one JSON document, for backup. Values that belong to this
  /// computer (cache folder, audio output, decoder results) are left out.
  String exportSettings() => const JsonEncoder.withIndent('  ').convert({
        'app': 'Lumtub',
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
    if (data is! Map || (data['app'] != 'Lumtub' && data['app'] != 'YTPlus')) return false;
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
    logInfo('Settings imported');
    return true;
  }

  /// Restores every default except this computer's cache folder and
  /// decoder results.
  Future<void> resetSettings() async {
    await saveSettings(PlayerSettings(cachePath: settings.cachePath, cacheLimitGb: settings.cacheLimitGb, decoderResults: settings.decoderResults));
    await saveAppearance(const AppearanceSettings());
    await savePreferences(const AppPreferences());
    _notice(tr('已恢复默认设置。'));
  }

  Future<void> saveAppearance(AppearanceSettings next) async {
    _applyAppearanceGlobals(next);
    if (next.systemAccent && windowsAccent == null) unawaited(refreshWindowsAccent());
    _update(() => appearance = next);
    // The text size slider saves at every step; only the last one is written.
    _appearanceSaveTimer?.cancel();
    _appearanceSaveTimer = Timer(const Duration(milliseconds: 500), () => unawaited(_writeAppearance()));
  }

  Timer? _appearanceSaveTimer;

  /// Writes the appearance now if a save is still waiting for its delay.
  Future<void> _flushAppearance() async {
    if (!(_appearanceSaveTimer?.isActive ?? false)) return;
    _appearanceSaveTimer!.cancel();
    await _writeAppearance();
  }

  Future<void> _writeAppearance() async {
    try {
      await _appearanceStore?.save(appearance);
    } on FileSystemException {
      _notice(tr('外观设置未能保存，本次运行仍然生效。'));
    }
  }

  ToolManager? get tools => _tools;

  /// Goes back to the libmpv shipped with Lumtub from the next launch on.
  Future<void> rollBackLibmpv() async {
    await _tools?.libmpv.rollBack();
    _update(() {});
    _notice(tr('已改回内置 libmpv，重启 Lumtub 后生效。'));
  }

  Future<void> rollBackYtDlp() async {
    await _tools?.rollBackYtDlp();
    _update(() {});
    _notice(tr('已改回上一个 yt-dlp，重启 Lumtub 后生效。'));
  }

  /// Download progress (0..1, null when unknown) while ffmpeg installs.
  double? ffmpegProgress;
  bool installingFfmpeg = false;

  /// Whether ffmpeg is there, so downloads can merge video and audio.
  bool get ffmpegInstalled => downloads?.canMerge ?? false;

  /// Whether starting a download in [quality] merges, goes single-file or
  /// needs to ask about installing ffmpeg first.
  FfmpegChoice ffmpegChoice(DownloadQuality quality) =>
      ffmpegChoiceFor(quality, installed: ffmpegInstalled, declined: preferences.skipFfmpegPrompt);

  /// Remembers that the user wants single-file downloads without being asked.
  Future<void> declineFfmpegPrompt() => savePreferences(preferences.copyWith(skipFfmpegPrompt: true));

  /// The size of the ffmpeg download in bytes, or null when unknown.
  Future<int?> ffmpegDownloadSize() async {
    try {
      return await _tools?.ffmpegDownloadSize();
    } catch (_) {
      return null;
    }
  }

  /// Installs or updates ffmpeg; true when it is usable afterwards.
  Future<bool> installFfmpeg() async {
    final tools = _tools;
    if (tools == null || installingFfmpeg) return false;
    _update(() {
      installingFfmpeg = true;
      ffmpegProgress = null;
    });
    try {
      await tools.installFfmpeg(onProgress: (received, total) {
        final fraction = total == null || total == 0 ? null : received / total;
        if (fraction == null || fraction - (ffmpegProgress ?? 0) >= 0.01) _update(() => ffmpegProgress = fraction);
      });
      if (preferences.skipFfmpegPrompt) await savePreferences(preferences.copyWith(skipFfmpegPrompt: false));
      return true;
    } catch (e) {
      logError('ffmpeg installation failed', e);
      _notice(tr('ffmpeg 安装失败：{0}', [e]));
      return false;
    } finally {
      _update(() => installingFfmpeg = false);
    }
  }

  Future<void> removeFfmpeg() async {
    try {
      await _tools?.removeFfmpeg();
    } on FileSystemException catch (e) {
      _notice(tr('无法删除 ffmpeg（可能正在使用）：{0}', [e.message]));
    }
    _update(() {});
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
    // Lighter scaling set for a busy GPU is not in the settings, so then
    // every option is set again.
    final ignoredOptions = await PlayerOptionApplicator.apply(player, next, previous: _lightRendering == null ? oldSettings : null);
    _lightRendering = null;
    await store.save(next);
    _update(() => settings = next);
    if (next.proxyMode != oldSettings.proxyMode ||
        next.proxyAddress != oldSettings.proxyAddress ||
        next.dnsServer != oldSettings.dnsServer ||
        next.dnsCustomUrl != oldSettings.dnsCustomUrl) {
      await _refreshProxy();
    }
    _update(() {
      final paths = this.paths;
      final cacheManager = _cacheManager;
      if (paths != null && cacheManager != null && next.cachePath != oldSettings.cachePath) {
        _repository = _repositoryFor(paths, cacheManager, next);
        library?.repository = _repository;
      }
      status = ignoredOptions.isEmpty
          ? tr('播放器设置已保存{0}', [
              _zeroCopyDxva2(next.hwdec) != _zeroCopyDxva2(oldSettings.hwdec) && videoController != null
                  ? tr('；DXVA2 零拷贝要重启 Lumtub 后生效。')
                  : requiresNextVideo
                      ? tr('；硬件解码和帧插值在下一段视频生效。')
                      : '。'
            ])
          : tr('已保存；此 libmpv 不支持：{0}。', [ignoredOptions.join(', ')]);
    });
  }

  /// Shows [next] at once without saving or touching libmpv, while a
  /// slider of the subtitle style panel moves; [saveSettings] follows when
  /// it is let go.
  void previewSettings(PlayerSettings next) => _update(() => settings = next);

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

  /// Asks the GPU what it decodes in hardware, once per graphics adapter
  /// and driver: the automatic codecs follow the answer.
  Future<void> _measureDecoders() async {
    try {
      final json = await Isolate.run(NativeCore.hwDecodersNow);
      if (json == null || _disposed) return;
      final probe = jsonDecode(json) as Map<String, dynamic>;
      final adapter = probe['adapter']?.toString() ?? '';
      if (adapter.isEmpty || adapter == settings.decoderAdapter) return;
      int height(String key) => (probe[key] as num?)?.toInt() ?? 0;
      logInfo('Hardware decoding on $adapter: H.264 ${height('h264')}p, VP9 ${height('vp9')}p, AV1 ${height('av1')}p');
      final results = {
        for (final key in ['h264', 'vp9', 'av1']) key: height(key) >= 1080 ? const DecoderStatus.hardware('d3d11va') : const DecoderStatus.software(),
      };
      _update(() => decodeStates = results);
      settings = settings.copyWith(decoderResults: results, decoderAdapter: adapter);
      await _settingsStore?.save(settings);
    } catch (e) {
      logError('Could not ask the GPU what it decodes', e);
    }
  }

  Future<void> inspectCurrentDecoder({Duration delay = Duration.zero}) async {
    final platform = player?.platform;
    if (platform is! NativePlayer) {
      _notice(tr('当前播放器无法读取 libmpv 解码状态。'));
      return;
    }
    try {
      await Future<void>.delayed(delay);
      final codec = (await platform.getProperty('video-codec')).trim().toLowerCase();
      final decoder = DecoderStatus.fromMpv(await platform.getProperty('hwdec-current'));
      final normalized = DecoderStatus.codecKey(codec);
      _update(() {
        currentCodec = codec.isEmpty ? tr('尚未验证') : codec;
        currentHwdec = decoder.label;
        if (normalized != null) decodeStates = {...decodeStates, normalized: decoder};
      });
      final width = int.tryParse(await platform.getProperty('video-params/w')) ?? 0;
      final height = int.tryParse(await platform.getProperty('video-params/h')) ?? 0;
      final crop = DecoderStatus.paddingCrop(width, height, hardware: decoder.kind == DecoderKind.hardware);
      if (crop != _paddingCrop) {
        _paddingCrop = crop;
        await platform.setProperty('video-crop', crop);
        if (crop.isNotEmpty) logInfo('Cropping $crop of ${width}x$height to keep the decoder padding off the picture');
      }
      if (normalized != null) {
        settings = settings.copyWith(decoderResults: decodeStates);
        unawaited(_settingsStore?.save(settings));
      }
      // A download older than its codec in the sidecar: only libmpv can
      // tell it is in a codec the playback rules disable.
      final item = playing;
      final fileCodec = VideoCodec.of(normalized);
      if (item != null && _openedLocal == item.id && !FormatPolicy.allows(settings, fileCodec)) {
        logInfo('The download of ${item.id} is ${fileCodec!.label}, a codec the playback rules disable; playing online instead');
        _notice(tr('下载的文件是 {0} 编码，已按播放规则改为在线播放', [fileCodec.label]));
        unawaited(_open(item, _playSerial, start: player?.state.position, allowLocal: false));
      }
    } catch (_) {
      _update(() => currentHwdec = tr('尚未验证'));
    }
  }

  /// The `video-crop` last set, so an unchanged one is not set again.
  String _paddingCrop = '';

  /// Logs playback timing when frames are being dropped, at most once a
  /// minute, so the log shows why a video stutters.
  Future<void> _checkDrops() async {
    final platform = player?.platform;
    if (platform is! NativePlayer || _tracking == null || !(player?.state.playing ?? false)) return;
    await _logMemory(platform);
    try {
      final drops = int.tryParse(await platform.getProperty('frame-drop-count')) ?? 0;
      final added = drops - _lastDrops;
      _lastDrops = drops;
      // Read every time, so the timings cover these 10 seconds.
      final frames = await _frameStats(platform);
      await _watchPicture(platform, frames);
      await _lightenIfBusy(platform, frames);
      await _stepDownIfDropping(platform, added);
      if (added < 20 || DateTime.now().difference(_lastDropLog) < const Duration(minutes: 1)) {
        // Smooth playback is logged too, every few minutes, so a stutter can
        // be compared with how the same machine plays normally.
        if (frames != null && DateTime.now().difference(_lastFrameLog) >= const Duration(minutes: 3)) {
          _lastFrameLog = DateTime.now();
          logInfo('Frames in 10 s, $added dropped: $frames');
        }
        return;
      }
      _lastDropLog = DateTime.now();
      final values = <String>[];
      for (final name in ['avsync', 'estimated-vf-fps', 'container-fps', 'display-fps', 'vo-delayed-frame-count', 'mistimed-frame-count', 'decoder-frame-drop-count', 'hwdec-current', 'video-sync', 'speed', 'video-params/w', 'video-params/h', 'time-pos', 'audio-pts', 'audio-params/samplerate', 'audio-out-params/samplerate', 'current-ao', 'd3d11va-zero-copy', 'vd-lavc-dr', 'video-codec', 'video-out-params/pixelformat']) {
        values.add('$name=${await platform.getProperty(name)}');
      }
      logInfo('Dropped $added frames in 10 s ($drops total): ${values.join(' ')}${frames == null ? '' : ' · frames $frames'}');
    } catch (_) {
      // Statistics are best effort.
    }
  }

  DateTime _lastPictureFix = DateTime(2000);

  /// The open in which libmpv's curl gave up on a stream.
  int? _streamLostIn;

  /// The open in which the decoder was restarted for a stalled picture.
  int? _pictureRestartedIn;

  /// Brings back a picture that stopped while the sound plays on: when no
  /// frame was drawn in 10 s, the decoder is restarted from here; when
  /// frames were drawn but none reached the screen, the texture is
  /// registered again. Only while the video is on screen, at most once a
  /// minute.
  Future<void> _watchPicture(NativePlayer platform, String? frames) async {
    final match = frames == null ? null : RegExp(r'frames=(\d+)/(\d+)').firstMatch(frames);
    final outputSize = _outputSize;
    if (match == null || outputSize == null || !outputSize.onScreen || audioOnly || _backgroundAudioOnly || _windowHidden) return;
    if ((player?.state.width ?? 0) == 0 || DateTime.now().difference(_lastPictureFix) < const Duration(minutes: 1)) return;
    final drawn = int.parse(match[1]!), shown = int.parse(match[2]!);
    if (drawn > 0 && shown > 0) return;
    _lastPictureFix = DateTime.now();
    // A video stream that broke off, or a restart that brought nothing
    // back, needs the video opened again at the same place.
    if (drawn == 0 && (_streamLostIn == _playSerial || _pictureRestartedIn == _playSerial)) {
      logInfo('Picture stalled while playing ($frames); the video stream is gone, reopening');
      _pictureRestartedIn = null;
      _streamLostIn = null;
      unawaited(_recover('The video stream stopped while the sound played on'));
      return;
    }
    logInfo('Picture stalled while playing ($frames); ${drawn == 0 ? 'restarting the decoder' : 'registering the texture again'}');
    try {
      if (drawn == 0) {
        _pictureRestartedIn = _playSerial;
        await platform.command(['seek', '0', 'relative+exact']);
      } else {
        await outputSize.refresh();
      }
    } catch (e) {
      logInfo('Could not bring the picture back: $e');
    }
  }

  /// The video output's timings for each frame since the last call: libmpv's
  /// render, the ANGLE draw and Flutter's read, as count/average/max.
  /// Why scaling was switched to the cheap kind: the GPU could not keep
  /// up (until the settings change), or the PC runs on battery (until it
  /// is plugged in); null while it is not.
  String? _lightRendering;

  /// In 智能自动, switches mpv to the cheapest scaling (as 低资源占用优先
  /// does) on battery or with battery saver, and once drawing a frame takes
  /// most of its time: on a weak or busy GPU the filters cost dropped
  /// frames, and at window size the difference is hard to see.
  Future<void> _lightenIfBusy(NativePlayer platform, String? frames) async {
    final player = this.player;
    if (player == null) return;
    if (_lightRendering == 'battery' && !Power.saving) {
      _lightRendering = null;
      await PlayerOptionApplicator.apply(player, settings);
      logInfo('Plugged in again; scaling back to normal');
      return;
    }
    // Filters the person turned on are kept.
    if (_lightRendering != null || settings.strategy != PlaybackStrategy.auto || settings.scale != const PlayerSettings().scale || settings.deband || settings.interpolation) return;
    String reason;
    if (Power.saving) {
      reason = 'battery';
    } else {
      final busy = frames == null ? null : drawBusy(frames, double.tryParse(await platform.getProperty('container-fps')) ?? 0);
      if (busy == null) return;
      reason = 'busy';
      logInfo('Frames take ${busy.toStringAsFixed(1)} ms to draw, most of their time');
    }
    _lightRendering = reason;
    for (final MapEntry(:key, :value) in PlayerOptionApplicator.fastRendering.entries) {
      if (settings.customOptions.containsKey(key)) continue;
      try {
        await platform.setProperty(key, value);
      } catch (_) {}
    }
    logInfo(reason == 'battery' ? 'On battery; scaling switched to the fast kind' : 'Scaling switched to the fast kind');
  }

  /// With automatic quality, a video that keeps dropping frames (a tenth
  /// of them for 30 seconds, after the cheap scaling above) is reopened one
  /// quality lower, such as 1080p60 at 720p60, and later videos of this run
  /// stay at most there. Choosing 自动 again lifts it.
  Future<void> _stepDownIfDropping(NativePlayer platform, int added) async {
    if (settings.maxHeight != 0 || settings.strategy == PlaybackStrategy.quality) return;
    final fps = double.tryParse(await platform.getProperty('container-fps')) ?? 0;
    _dropStreak = fps > 0 && added >= fps ? _dropStreak + 1 : 0;
    if (_dropStreak < 3) return;
    _dropStreak = 0;
    final height = int.tryParse(await platform.getProperty('video-params/h')) ?? 0;
    final lower = stepDownHeight(height, availableHeights);
    if (lower == null) return;
    _droppedCap = lower;
    logInfo('Frames kept dropping at ${height}p${fps.round()}; automatic quality lowered to ${lower}p for this run');
    _notice(tr('播放一直掉帧，自动画质已降到 {0}p（本次运行有效，重新选“自动”可恢复）', ['$lower']));
    await reloadVideo();
  }

  Future<String?> _frameStats(NativePlayer platform) async {
    try {
      final stats = await _videoChannel.invokeMethod<String>('VideoOutputManager.Stats', {'handle': '${await platform.handle}'});
      return stats == null || stats.isEmpty ? null : stats;
    } catch (_) {
      // An older plugin without timings.
      return null;
    }
  }

  static const _videoChannel = MethodChannel('com.alexmercerind/media_kit_video');

  DateTime _lastMemoryLog = DateTime(0);

  /// Logs the app's memory and what libmpv's cache holds every two minutes
  /// while a video plays, so the log shows where memory goes.
  Future<void> _logMemory(NativePlayer platform) async {
    if (DateTime.now().difference(_lastMemoryLog) < const Duration(minutes: 2)) return;
    _lastMemoryLog = DateTime.now();
    try {
      String mb(Object? bytes) => bytes is num ? '${(bytes / (1 << 20)).round()} MB' : '?';
      final cache = jsonDecode(await platform.getProperty('demuxer-cache-state'));
      final ahead = cache is Map ? cache['fw-bytes'] : null;
      final total = cache is Map ? cache['total-bytes'] : null;
      final values = <String>[];
      for (final name in ['video-params/w', 'video-params/h', 'video-codec', 'hwdec-current', 'video-out-params/pixelformat']) {
        values.add('$name=${await platform.getProperty(name)}');
      }
      logInfo('Memory: process ${mb(ProcessInfo.currentRss)} (peak ${mb(ProcessInfo.maxRss)}) · playback cache ${mb(total)} (ahead ${mb(ahead)}) · image cache ${mb(PaintingBinding.instance.imageCache.currentSizeBytes)} · ${values.join(' ')}');
    } catch (_) {
      // Statistics are best effort.
    }
  }

  Future<void> _readWindowsVideoInfo() async {
    final info = await WindowsVideoInfo.read();
    _update(() => windowsVideoInfo = info);
  }

  /// Reads optional Windows Media Foundation codec extensions only when the
  /// decoder-status settings section is opened. libmpv itself does not use
  /// these extensions.
  void refreshWindowsVideoInfo() => unawaited(_readWindowsVideoInfo());

  Future<void> openStore(String url) async {
    try {
      await Process.start('explorer.exe', [url]);
    } catch (_) {
      _notice(tr('无法打开 Microsoft Store 链接。'));
    }
  }

  /// Moves the managed cache under [selectedFolder]. [confirmMigrate] asks
  /// whether existing cache folders should move with it.
  Future<void> changeCacheLocation(String selectedFolder, Future<bool?> Function(String targetPath) confirmMigrate) async {
    final manager = _cacheManager;
    if (directories == null || manager == null) return;
    final target = Directory('$selectedFolder${Platform.pathSeparator}LumtubCache');
    final next = settings.copyWith(cachePath: target.path);
    try {
      await manager.prepare(next);
      final migrate = await confirmMigrate(target.path);
      // The old folders are deleted only after the new location is saved.
      if (migrate == true) {
        await manager.migrate(settings, next, commit: () => saveSettings(next));
      } else {
        await saveSettings(next);
      }
      _update(() => cacheBytes = 0);
      _notice(tr('缓存位置已保存。yt-dlp 缓存在下一次搜索时使用新位置。'));
    } on FileSystemException catch (error) {
      _notice(tr('新缓存位置不可用，继续使用原位置：{0}', [error.message]));
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
    if (!ensureNotPlaying(tr('正在播放时不会清理缓存。请先返回列表。'))) return;
    try {
      _translationCache.clear();
      final (:freed, :skipped) = await manager.clear(settings);
      final left = await manager.size(settings);
      _update(() => cacheBytes = left);
      _notice(skipped == 0
          ? tr('已清理 {0} 缓存。', [formatBytes(freed)])
          : tr('已清理 {0} 缓存；{1} 个文件正被使用，留到下次。', [formatBytes(freed), skipped]));
    } on FileSystemException catch (error) {
      logError('Could not clear the cache', error);
      _notice(tr('清理缓存失败：{0}', [error.message]));
    }
  }

  /// 清除本地数据: removes the chosen [kinds] from this computer. Favourites,
  /// playlists and followed channels are never touched here.
  Future<void> clearLocalData(Set<LocalData> kinds) async {
    if (kinds.contains(LocalData.cache) && !ensureNotPlaying(tr('正在播放时不会清理缓存。请先返回列表。'))) return;
    logInfo('Clearing local data: ${kinds.map((k) => k.name).join(', ')}');
    for (final kind in LocalData.values.where(kinds.contains)) {
      try {
        switch (kind) {
          case LocalData.history:
            await _history?.clear();
            await searchHistory?.clear();
          case LocalData.progress:
            library?.clearProgress();
          case LocalData.recommendations:
            await homeFeed?.notInterested.clear();
          case LocalData.cache:
            _translationCache.clear();
            final manager = _cacheManager;
            if (manager != null) {
              await manager.clear(settings);
              cacheBytes = await manager.size(settings);
            }
          case LocalData.account:
            await account?.signOut();
          case LocalData.keys:
            translationKeys = const {};
            _useTranslator();
            await _translationKeyFile?.delete();
          case LocalData.settings:
            await saveSettings(PlayerSettings(cachePath: settings.cachePath, cacheLimitGb: settings.cacheLimitGb, decoderResults: settings.decoderResults));
            await saveAppearance(const AppearanceSettings());
            await savePreferences(const AppPreferences());
        }
      } catch (e) {
        logError('Could not clear ${kind.name}', e);
      }
    }
    _update(() {});
    _notice(tr('已清除所选的本地数据'));
  }

  /// Saves everything and releases the player before the window closes;
  /// dispose() alone does not run when Windows ends the process.
  Future<void> shutdown({bool install = true}) async {
    if (_shutDown) return;
    _shutDown = true;
    if (install) await appUpdater?.install();
    _saveProgress();
    _countWatchTime(flush: true);
    await (watchTime?.save() ?? Future.value(), channelPlayback?.save() ?? Future.value()).wait;
    await library?.flush();
    await downloads?.flush();
    await _translationCache.save();
    await _flushAppearance();
    for (final subscription in _playerSubscriptions) {
      await subscription.cancel();
    }
    _playerSubscriptions.clear();
    _stallTimer?.cancel();
    _recoveryTimer?.cancel();
    await player?.pause();
    await player?.dispose();
    logInfo('Lumtub exited normally');
    await AppLog.current?.flush();
  }

  /// A summary for bug reports; it names no account, video or file
  /// contents, only versions and settings.
  String diagnostics() {
    final tools = _tools;
    return [
      'Lumtub $appVersion',
      'Windows ${Platform.operatingSystemVersion}',
      tr('CPU 核心 {0}', [Platform.numberOfProcessors]),
      'GPU ${windowsVideoInfo.gpuNames.isEmpty ? '未知' : windowsVideoInfo.gpuNames.join(' / ')}',
      'libmpv ${tools?.libmpv.current?.label ?? '内置'}',
      'yt-dlp ${tools?.ytDlpVersion ?? '未安装'}',
      'Deno ${tools?.denoVersion ?? '未安装'}',
      tr('硬件解码设置 {0} · 当前 {1} · {2}', [settings.hwdec, currentCodec, currentHwdec]),
      tr('画质上限 {0} · 播放策略 {1} · 禁用编码 {2} · 音质 {3}', [settings.maxHeight == 0 ? tr('自动') : '${settings.maxHeight}p', settings.strategy.label, FormatPolicy.disabledNames(settings).isEmpty ? tr('无') : FormatPolicy.disabledNames(settings), settings.audioQuality.label]),
      tr('缓存 {0} · {1} 秒 · {2} MB', [settings.cacheMode, settings.cacheSeconds, settings.cacheMemoryMb]),
      tr('数据目录 {0}', [directories?.root.path ?? tr('未知')]),
    ].join('\n');
  }

  @override
  void dispose() {
    _disposed = true;
    _stopCurrentChat();
    chatMessages.dispose();
    speechJob.dispose();
    _stallTimer?.cancel();
    _recoveryTimer?.cancel();
    _startTimer?.cancel();
    _sleepTimer?.cancel();
    _dropTimer?.cancel();
    _outputSize?.dispose();
    unawaited(_flushAppearance());
    _thumbnailTrimTimer?.cancel();
    _afterStart?.cancel();
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    _saveProgress();
    _countWatchTime(flush: true);
    unawaited(watchTime?.save());
    unawaited(channelPlayback?.save());
    unawaited(_relay?.close());
    unawaited(_bridge?.close());
    cast.dispose();
    account?.dispose();
    tvSignIn?.cancel();
    webSignIn?.cancel();
    downloads?.dispose();
    library?.dispose();
    channelVideos?.dispose();
    searchResults?.dispose();
    explore?.dispose();
    for (final (_, loader) in _recentExplore.values) {
      loader.dispose();
    }
    channelPosts?.dispose();
    youtubePlaylistVideos?.dispose();
    youtubeHistory?.dispose();
    related?.dispose();
    _http.close();
    if (!_shutDown) unawaited(player?.dispose());
    _tools?.dispose();
    unawaited(_notices.close());
    unawaited(_finishedDownloads.close());
    super.dispose();
  }
}

/// What 清除本地数据 can remove.
enum LocalData {
  history('观看历史和搜索记录'),
  progress('播放进度'),
  recommendations('“不感兴趣”记录'),
  cache('缓存（视频、缩略图、翻译）'),
  account('Google 账号登录'),
  keys('翻译服务的 API 密钥'),
  settings('所有设置（恢复默认）');

  const LocalData(this._label);
  final String _label;
  String get label => tr(_label);
}

/// Reads the libraries in [folder], libmpv at [mpv] and the system shader
/// compiler, so making the video output does not wait for the disk.
/// Returns the bytes read.
int Function() _readingPlayerFiles(String folder, String? mpv) => () => _readPlayerFiles(folder, mpv);

int _readPlayerFiles(String folder, String? mpv) {
  final files = <File>[
    for (final entry in Directory(folder).listSync())
      if (entry is File && entry.path.toLowerCase().endsWith('.dll')) entry,
    if (mpv != null && !mpv.toLowerCase().startsWith(folder.toLowerCase())) File(mpv),
    if (Platform.isWindows) File('${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32\\d3dcompiler_47.dll'),
  ];
  var total = 0;
  for (final file in files) {
    try {
      final handle = file.openSync();
      try {
        while (true) {
          final chunk = handle.readSync(1 << 20);
          if (chunk.isEmpty) break;
          total += chunk.length;
        }
      } finally {
        handle.closeSync();
      }
    } catch (_) {}
  }
  return total;
}

/// Whether [hwdec] asks for zero-copy DXVA2, whose interop the video output
/// only loads when it is made.
bool _zeroCopyDxva2(String hwdec) => hwdec.split(',').map((e) => e.trim()).contains('dxva2');
