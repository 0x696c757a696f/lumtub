import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color, PaintingBinding, Size;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../ai_filter.dart';
import '../android_subtitle_fonts.dart';
import '../app_directories.dart';
import '../app_updater.dart';
import '../app_log.dart';
import '../app_window.dart';
import '../app_preferences.dart';
import '../libass_layout.dart';
import '../play_queue.dart';
import '../video_facts_lookup.dart';
import '../video_languages.dart';
import '../playback_failure.dart';
import '../skip_silence.dart';
import '../playback_recovery.dart';
import '../library_store.dart';
import '../secure_store.dart';
import '../dearrow.dart';
import '../emoji_pictures.dart';
import '../downloads/download_formats.dart';
import '../downloads/core_recorder.dart';
import '../downloads/download_manager.dart';
import '../downloads/download_models.dart';
import '../downloads/download_selection.dart';
import '../return_dislike.dart';
import '../sponsor_block.dart';
import '../appearance_settings.dart';
import '../cache_manager.dart';
import '../decoder_status.dart';
import '../live_split.dart';
import '../native_core.dart';
import '../encrypted_dns.dart';
import '../native_http.dart';
import '../live_chat.dart';
import '../models.dart';
import '../network_proxy.dart';
import '../socks_bridge.dart';
import '../cast/cast_subtitles.dart';
import '../cast/cast_controller.dart';
import '../channel_avatar_lookup.dart';
import '../channel_playback.dart';
import '../channel_sort.dart';
import '../speech_subtitles.dart';
import '../video_summary.dart';
import '../watch_time.dart';
import '../cast/airplay.dart';
import '../cast/cast_device.dart';
import '../cast/cast_stream.dart';
import '../cast/dlna.dart';
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
import '../thumbnail_trim.dart';
import '../tool_manager.dart';
import '../format_policy.dart';
import '../memory_trim.dart';
import '../video_codec.dart';
import '../community_posts.dart';
import '../block_list_updates.dart';
import '../blocked_groups.dart';
import '../explore_filters.dart';
import '../explore_topics.dart';
import '../faith_topics.dart';
import '../feed_quality.dart';
import '../portrait_thumbnails.dart';
import '../storyboard.dart';
import '../stream_resolver.dart';
import '../subtitle_files.dart';
import '../subtitle_cues.dart';
import '../subtitle_translation.dart';
import '../danmaku.dart';
import '../comment_danmaku.dart';
import '../language_guess.dart' show readsAs;
import '../translation.dart';
import '../translation_cache.dart';
import '../translation_services.dart';
import 'posts_loader.dart';
import '../video_output_size.dart';
import '../video_repository.dart';
import '../system_env.dart';
import '../windows_video_info.dart';
import 'account_controller.dart';
import 'home_feed.dart';
import 'back_stack.dart';
import 'library_controller.dart';
import '../playing_list.dart';
import '../youtube_player_probe.dart';
import 'video_list_loader.dart';
import '../l10n/l10n.dart';
import '../friendly_error.dart';
import '../support_reminder.dart';
import '../channel_handle.dart';

part 'explore_controller.dart';
part 'navigation_actions.dart';
part 'settings_actions.dart';
part 'picture_health.dart';
part 'chat_actions.dart';
part 'subtitle_actions.dart';
part 'smoke_check.dart';
part 'diagnostics.dart';
part 'playback_open.dart';
part 'playback_events.dart';
part 'playback_controls.dart';
part 'skip_silence_actions.dart';
part 'queue_actions.dart';
part 'video_details.dart';
part 'cast_actions.dart';
part 'download_actions.dart';
part 'network_actions.dart';
part 'search_actions.dart';
part 'lifecycle_actions.dart';
part 'account_actions.dart';
part 'window_actions.dart';

enum PageMode { home, explore, subscriptions, history, playlists, downloads, settings, channel, playlist, youtubePlaylist }

/// Application state and actions, kept separate from the widgets that show them.
class AppController extends ChangeNotifier with _ExploreState {
  HistoryStore? _history;
  AppDirectories? directories;

  /// Now and then asks whether to support Lumtub; null until started.
  SupportReminder? supportReminder;
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
  String currentCodec = tr('No video played yet');
  String currentHwdec = tr('Not verified yet');
  WindowsVideoInfo windowsVideoInfo = const WindowsVideoInfo();
  PlayerSettings settings = const PlayerSettings();
  VideoItem? playing;
  PageMode mode = PageMode.home;
  bool ready = false;
  bool checking = false;
  /// Lumtub's own updates; null until the components are ready.
  AppUpdater? appUpdater;

  /// Daily download of the signed block lists; set once ready.
  BlockListUpdates? blockListUpdates;
  String status = tr('Preparing the Windows native player…');
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
  ChannelSort channelSort = ChannelSort.latest;
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
    if (!AppWindow.setTopmost(!pinned || pip)) return _notice(tr('Could not keep the window on top'));
    _update(() => pinned = !pinned);
    if (pinned) _noteWaylandTop();
  }

  bool _waylandNoted = false;

  /// Wayland desktops decide themselves which window is on top and where
  /// it goes; said once per run.
  void _noteWaylandTop() {
    if (_waylandNoted || !AppWindow.onWayland || AppWindow.keepsAboveOnWayland) return;
    _waylandNoted = true;
    if (!_disposed) _waylandTopNotes.add(null);
  }

  final _waylandTopNotes = StreamController<void>.broadcast();

  /// Said when a window should stay on top on a Wayland desktop that does
  /// not allow it; the page offers [switchToX11].
  Stream<void> get waylandTopNotes => _waylandTopNotes.stream;

  /// Whether the watch page shows [playing].
  bool get onWatchPage => playing != null && !mini;

  /// Whether leaving the watch page now keeps the video in the mini player.
  bool get _keepsPlaying =>
      playing != null && (mini || (preferences.miniPlayer && player != null && playbackError == null));

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

  /// Videos like the one playing, found by searching for its title.
  VideoListLoader? related;

  /// The list the current video was opened from, shown as the play queue.
  List<VideoItem> queue = const [];
  /// The playlist the playing video was opened from, for the watch page's
  /// playlist panel; null when it came from anywhere else.
  PlayingList? playingList;
  /// Videos lined up by hand; they play before [upNext].
  final playQueue = PlayQueue();
  VideoDetails? details;
  bool loadingDetails = false;
  List<LiveChatMessage> replayChat = const [];
  /// Recent Super Chats of the live chat, newest first, with when each
  /// leaves the strip over the chat.
  List<(LiveChatMessage, DateTime)> chatTicker = const [];

  /// Fires when a live chat gains messages, which happens several times a
  /// second: only the chat panel listens, not the whole app.
  final chatMessages = ValueNotifier(0);
  bool loadingReplayChat = false;
  String? replayChatError;
  StreamSubscription<LiveChatMessage>? _currentChat;
  Timer? _currentChatFlushTimer;
  final _currentChatPending = <LiveChatMessage>[];
  final _currentChatIds = <String>{};
  /// The audio language chosen for one video in the player ('' for its
  /// original sound), which lasts until another video plays.
  (String, String)? _audioPick;
  /// The audio languages the playing video offers; empty when it has one.
  List<AudioLanguage> availableAudioLanguages = const [];
  /// Heights the playing video offers, highest first; empty until known.
  List<int> availableHeights = const [];
  /// The most frames a second of [availableHeights], where above 30.
  Map<int, int> availableFrameRates = const {};
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

  /// Drops the last video's padding crop before another opens: kept, it
  /// cuts the new picture to the old one's size, which for a larger video
  /// shows one corner of it enlarged until the crop is fitted again.
  static Future<void> _forgetCrop(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty('video-crop', '');
    } catch (e) {
      logDebug(() => 'Could not reset the video crop: $e');
    }
  }

  /// The TV or Chromecast the video is cast to, if any.
  final cast = CastController();

  /// The keys kept from pairing with AirPlay receivers.
  final airPlayPairings = AirPlayPairings();

  /// This PC's address on the network [device] is on.
  static Future<String> _addressFacing(CastDevice device) async {
    final socket = await Socket.connect(device.host, device.port, timeout: const Duration(seconds: 4));
    final here = socket.address.address;
    socket.destroy();
    return here;
  }

  Timer? _castWatch;

  /// [split] joined by lumtub_core's cast server from [start]: an MPEG
  /// transport stream for a DLNA renderer, a fragmented MP4 for a
  /// Chromecast. Seeking starts it again from the new position. While it
  /// is cast, the server's log is copied into the app's, and the stream
  /// addresses are renewed before YouTube lets them expire or once it has
  /// refused one.
  /// Registers a cast stream away from the UI isolate. A static function so
  /// the closure sent to the isolate captures nothing but [ask]; one made
  /// inside [_joinedCast] would carry its timer along, which cannot be sent.
  static Future<String> _castRegister(String ask) => Isolate.run(() => NativeCore.instance?.castRegister(ask) ?? '{"error":"no lumtub_core"}');

  /// The Piped servers, for 设置 › Piped 服务器.
  PipedStreams get piped => _piped;
  /// The Invidious instances, for 设置 › Invidious 实例.
  InvidiousStreams get invidious => _invidious;
  /// Serves YouTube streams to libmpv in pieces YouTube does not throttle.
  StreamRelay? _relay;

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
    VideoItem.thumbnailFile = appearance.effectiveThumbnails.file;
    videoCardMinWidth = appearance.cardWidth;
    compactCards = appearance.compact;
    lowResourceMode = appearance.lowResource;
    videoLayout = appearance.layout;
  }

  int _playSerial = 0;
  final _silence = SilenceSkipper();
  String? _query;
  final _playerSubscriptions = <StreamSubscription<Object?>>[];
  double _volumeBeforeMute = 100;
  bool _libmpvConfirmed = false;
  /// The video whose position is being recorded; null while switching, so
  /// positions of the previous file are not credited to the next.
  VideoItem? _tracking;
  DateTime _lastProgressSave = DateTime(0);
  List<SkipSegment> _segments = const [];

  /// The settings libmpv was last given.
  PlayerSettings? _applied;
  final _skipped = <SkipSegment>{};
  final _http = appHttpClient();
  /// Sprite sheets of the progress bar's preview frames.
  late final storyboardSheets = StoryboardSheets(_http);
  late final _google = GoogleTranslator(_http);
  /// Translations already made, kept for a week in the cache folder.
  TranslationCache _translationCache = TranslationCache();
  /// Behind 翻译 buttons and translated subtitles: the service 翻译服务
  /// names; called only when something is to be translated.
  late Translator translator = CachingTranslator(_google, _translationCache, preferences.translation.cacheScope, batch: true);
  /// The translation services' API keys, by [TranslationService.name],
  /// kept encrypted with DPAPI apart from the settings.
  Map<String, String> translationKeys = const {};
  SecureJsonFile? _translationKeyFile;
  /// The subtitle shown above the main one (双语字幕), if any.
  SubtitleOption? secondarySubtitle;
  /// mpv's `secondary-sid` as it last said: 'no' when no second subtitle
  /// shows. It can show one this controller did not choose, such as one
  /// mpv brought back by itself.
  String secondaryTrackId = 'no';

  /// Whether a second subtitle shows.
  bool get secondaryOn => secondarySubtitle != null || secondaryTrackId != 'no';
  /// The second subtitle being fetched or translated, shown as loading in
  /// the 字幕 panel rather than as 关闭.
  SubtitleOption? secondaryLoading;
  /// The video 第二字幕语言 was applied to, so a secondary subtitle turned
  /// off stays off.
  String? _secondaryAutoFor;
  /// Settles once the subtitles shown by themselves for the video of
  /// [_subtitlesSerial] are on, or are known not to need a translation.
  Completer<void> _subtitlesReady = Completer<void>()..complete();
  int _subtitlesSerial = 0;
  bool _decoderPending = false;
  int _mpvLogLines = 0;
  String? _lastMpvLine;
  /// yt-dlp and libmpv error lines for the video being opened, which name
  /// the cause libmpv's own error message usually leaves out.
  final _recentErrors = <String>[];

  /// No prefetching until then, after YouTube answered 429.
  DateTime _rateLimitedUntil = DateTime(0);
  bool _updateCheckedForChallenge = false;
  /// The spoken language of explore's videos, for its language filter.
  VideoLanguages? _videoLanguages;
  AiFilter? _aiFilter;

  int _lastDrops = 0;

  /// When the current video was opened. Its first seconds are left out of
  /// the dropped-frame checks: the first picture of a run compiles the
  /// shaders and drops frames that later ones do not.
  DateTime _openedAt = DateTime(2000);
  /// The video libmpv was last told to open; its file loads after.
  String? _openIssued;
  /// Ten-second windows in a row that dropped a tenth of the frames or more.
  int _dropStreak = 0;
  /// The quality automatic playback is lowered to for this run after
  /// frames kept dropping; 0 while it is not.
  int _droppedCap = 0;

  /// The height playback was lowered to after dropped frames, 0 for none.
  int get droppedCap => _droppedCap;
  DateTime _lastDropLog = DateTime(0);
  DateTime _lastFrameLog = DateTime(0);
  Timer? _dropTimer;
  Timer? _thumbnailTrimTimer;
  final _recovery = PlaybackRecovery();
  /// Holds back resolving the next video until this one plays steadily.
  final _settled = SettledPlayback();
  /// The last position actually played, which survives a failed stream.
  Duration _lastPosition = Duration.zero;
  final _resumePoint = ResumePoint();
  String? _relayed;
  /// The video opened from its stream addresses rather than through
  /// ytdl_hook, which then adds no subtitle tracks of its own.
  String? _openedDirect;
  String? _unrelayed;
  Timer? _stallTimer;
  Timer? _recoveryTimer;
  Timer? _startTimer;
  int _startAttempts = 0;
  bool _recovering = false;
  bool _shutDown = false;
  /// The start-up under way, so a retry joins it instead of running twice.
  Future<void>? _initializing;
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

  /// When each video of [history] was last played, by id.
  Map<String, DateTime> get watchedTimes => _history?.watched ?? const {};

  late final _liveProbe = YoutubePlayerProbe(_http);
  DateTime? _historyLiveChecked;
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

  /// What asked for the page to be rebuilt since the frame log last
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

  bool _tvWasSignedIn = false;

  int _webSignIns = 0;

  bool _tvPlaylistsRead = false;

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
    _notice(value ? tr('Incognito mode is on: nothing you watch or search now will be remembered') : tr('Incognito mode is off'));
    logInfo(value ? 'Incognito on' : 'Incognito off');
  }

  /// The proxy everything currently goes through.
  NetworkProxy proxy = NetworkProxy.direct;
  DateTime _proxyRead = DateTime(0);

  SocksBridge? _bridge;
  String? _bridgeFor;

  /// `host:port` of the HTTP proxy libmpv and dart:io use: the proxy itself,
  /// or the local bridge to a SOCKS one. A SOCKS proxy whose bridge could
  /// not start gets a dead port, so requests fail instead of going direct.
  String? proxyEndpoint;

  /// The explore page's 类型 and 视角 lists for [section]. The rest of the
  /// explore page is in explore_controller.dart.
  static List<WordFilter> formatsOf(ExploreSection section) => section.isFaith ? FaithFormat.values : ContentFormat.values;
  static List<WordFilter> viewsOf(ExploreSection section) => section.isFaith ? FaithView.values : ContentView.values;

  /// 为你推荐 in a zone: title words and channels like the history's
  /// first, then more viewed.
  static double exploreScore(TasteProfile taste, VideoItem item) {
    final views = item.viewCount ?? item.watching ?? 0;
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

  DanmakuOverlay? _danmaku;
  String? _danmakuFor;
  /// The timed comments flown on a video without a chat, and its id.
  List<LiveChatMessage> _commentDanmaku = const [];
  String? _commentDanmakuFor;

  static String _clock(Duration d) {
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:$seconds' : '${d.inMinutes}:$seconds';
  }

  /// The subtitles shown in this video, by label, so a reopened video can
  /// show them again.
  final _shownOptions = <String, SubtitleOption>{};
  /// The main subtitle's title when the subtitle key last turned it off.
  String? _subtitleBeforeOff;

  /// The play whose first open already tried a quick start.
  int? _quickSerial;

  /// The live stream opened as its picture and sound above 1080p, joined
  /// fragment by fragment in the relay (see [LiveSplit]).
  String? _liveSplit;
  /// The live stream whose split picture and sound failed soon after
  /// opening twice, so it plays from HLS instead, up to 1080p.
  String? _liveSplitOff;
  /// The live stream whose split picture and sound failed soon after
  /// opening once: it gets one more try before HLS.
  String? _liveSplitBroke;

  /// Whether Piped or Invidious may play what YouTube would not. Not for
  /// what the video itself is (private, upcoming, no allowed format) or for
  /// a network that is down.
  static bool _serversMayHelp(FailureKind kind) =>
      const {FailureKind.rateLimited, FailureKind.botCheck, FailureKind.challenge, FailureKind.forbidden, FailureKind.unknown}.contains(kind);

  /// [_serversMayHelp] for [kind], and the user allows falling back to
  /// Piped and Invidious when YouTube refuses.
  bool _mayFallBack(FailureKind kind) => settings.relayFallback && _serversMayHelp(kind);

  bool _remakingOutput = false;
  final _outputRemade = <DateTime>[];

  late final _subtitleFiles = SubtitleFiles(
    _http,
    Directory('${Directory.systemTemp.path}${Platform.pathSeparator}Lumtub subtitles'),
    () => translator,
    byTranslator: () => preferences.subtitlesByService && preferences.translation.service != TranslationService.google,
    position: () => player?.state.position ?? Duration.zero,
    onUpdated: _subtitleFileUpdated,
  );

  final _cues = <String, List<SubtitleCue>>{};

  /// The chapter titles of [chapterTranslationOf] translated, one for
  /// each chapter, once asked for; untouched ones stay as they are.
  List<String>? chapterTranslation;
  String? chapterTranslationOf;
  bool translatingChapters = false;
  /// Bumped when [chapterTranslation] or [translatingChapters] changes,
  /// for the chapter menu, which does not rebuild with everything else.
  final chaptersChanged = ValueNotifier<int>(0);

  /// The most a video opened paused waits for its translated subtitles. It
  /// plays as soon as they are loaded in the player; this only guards a
  /// translation service that never answers. The first stretch took 9 to
  /// 30 s in the user's logs; the play button starts it sooner.
  static const subtitleWait = Duration(seconds: 60);

  /// The video opened is held until its translated subtitle is ready.
  bool waitingForSubtitles = false;

  bool _subtitlesFollowing = false;
  /// How far, in percent of the picture's height, subtitles drawn by mpv
  /// are raised while the player's controls cover the bottom.
  int _subtitleLift = 0;
  /// The main subtitle mpv shows now, for placing the second one.
  List<String> _mainSubtitle = const [];
  /// The family libmpv draws subtitles in on Android, picked by their text.
  String? _subtitleFamily;
  /// On Android: libmpv met subtitles no one font can draw, so Flutter's
  /// subtitle view draws this video's instead.
  bool libassCantDraw = false;

  /// Whether libmpv draws the subtitles now, not Flutter's view.
  bool get libassDraws => settings.libassSubtitles && !libassCantDraw;

  bool _backgroundAudioOnly = false;
  bool _windowHidden = false;
  bool? _efficient;

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

  bool get hasNext => playQueue.isNotEmpty || upNext.isNotEmpty || relatedItems.isNotEmpty;

  /// Videos played before the current one, the latest last.
  final _played = <VideoItem>[];

  bool get hasPrevious => _played.isNotEmpty || previousInQueue != null;

  /// How far behind its live edge a live stream may play before the
  /// player offers to jump back to it. A split stream above 1080p starts
  /// about 20 s behind on purpose (see relay_live.rs BEHIND).
  static const liveBehind = Duration(seconds: 30);

  /// A-B 循环: where the loop starts, then where it ends; mpv plays the
  /// part between them again and again.
  Duration? loopA;
  Duration? loopB;

  /// AI 总结 already made this session, by video id.
  final _summaries = <String, String>{};

  /// Whether [details] has subtitles other than 语音识别's.
  static bool hasOwnSubtitles(VideoDetails? details) => details?.subtitles.any((s) => s.kind != SubtitleKind.speech) ?? false;

  /// The video's brightness, within [pictureLimit], as 画面与音画同步调节 keeps it.
  int get brightness => settings.picture['brightness'] ?? 0;
  Timer? _brightnessSave;

  /// The audio outputs libmpv reports, "auto" first.
  List<AudioDevice> get audioDevices => player?.state.audioDevices ?? const [];

  /// The codec and height the playback test plays at, while it runs.
  PlayerSettings? _benchmark;

  String get _format => _formatFor(playing?.id);

  /// The yt-dlp format expression for the video [id]: the audio language
  /// chosen for it, else the one the settings ask for.
  String _formatFor(String? id) => FormatPolicy.expression(_playback, audioLanguage: _audioLanguageFor(id));

  /// The audio language for the video [id], empty for its original sound.
  String _audioLanguageFor(String? id) => FormatPolicy.dubLanguage(settings, pick: id != null && _audioPick?.$1 == id ? _audioPick!.$2 : null);

  String? get _formatSort => FormatPolicy.formatSort(_playback);

  /// [settings] as playback picks streams with them: automatic quality is
  /// capped at the tallest display.
  PlayerSettings get _playback {
    if (_benchmark case final fixed?) return fixed;
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

  VideoListLoader? _loadingWhole;

  /// Searches the open channel's videos for [query]; an empty query lists
  /// the uploads again.
  /// What a search inside the channel covers: null for YouTube's own
  /// channel search, else one tab whose titles are filtered.
  ChannelTab? channelSearchTab;

  SearchSort searchSort = SearchSort.relevance;
  SearchUploadDate searchDate = SearchUploadDate.any;
  SearchDuration searchDuration = SearchDuration.any;

  /// 为你推荐 on the home page.
  HomeFeed? homeFeed;
  late final relatedVideos = YoutubeRelated(_http);

  /// The video being watched, to learn from once it is left.
  VideoItem? _watching;

  /// Words typed before, newest first, and YouTube's suggestions.
  SearchHistory? searchHistory;
  late final searchSuggestions = SearchSuggestions(_http);

  final _visible = Expando<(Object, List<VideoItem>)>();

  Timer? _appearanceSaveTimer;

  ToolManager? get tools => _tools;


  /// Whether a crop check for a changed picture size is already scheduled.
  bool _cropFitting = false;

  DateTime _lastPictureFix = DateTime(2000);

  /// The open in which libmpv's curl gave up on a stream.
  int? _streamLostIn;

  /// When the decoder last failed on a frame, over the last 10 s.
  final _decodeErrors = <DateTime>[];

  /// When a lost stream or broken video data last opened the video again.
  DateTime _lastBrokenReopen = DateTime(2000);

  /// The open in which the decoder was restarted for a stalled picture.
  int? _pictureRestartedIn;

  /// The video output's timings for each frame since the last call: libmpv's
  /// render, the ANGLE draw and Flutter's read, as count/average/max.
  /// Why scaling was switched to the cheap kind: the GPU could not keep
  /// up (until the settings change), or the PC runs on battery (until it
  /// is plugged in); null while it is not.
  String? _lightRendering;

  static const _videoChannel = MethodChannel('com.alexmercerind/media_kit_video');

  DateTime _lastMemoryLog = DateTime(0);

  bool ensureNotPlaying(String message) {
    if (playing == null) return true;
    _notice(message);
    return false;
  }

  /// A summary for bug reports; it names no account, video or file
  /// contents, only versions and settings.
  String diagnostics() {
    final tools = _tools;
    return [
      'Lumtub $appVersion',
      'Windows ${Platform.operatingSystemVersion}',
      tr('CPU cores {0}', [Platform.numberOfProcessors]),
      'GPU ${windowsVideoInfo.gpuNames.isEmpty ? 'Unknown' : windowsVideoInfo.gpuNames.join(' / ')}',
      tools?.libmpvLabel ?? 'libmpv',
      'yt-dlp ${tools?.ytDlpVersion ?? 'Not installed'}',
      'Deno ${tools?.denoVersion ?? 'Not installed'}',
      tr('Hardware decoding setting {0} · current {1} · {2}', [settings.hwdec, currentCodec, currentHwdec]),
      tr('Quality cap {0} · Strategy {1} · Disabled codecs {2} · Audio {3}', [settings.maxHeight == 0 ? tr('Auto') : '${settings.maxHeight}p', settings.strategy.label, FormatPolicy.disabledNames(settings).isEmpty ? tr('None') : FormatPolicy.disabledNames(settings), settings.audioQuality.label]),
      tr('Cache {0} · {1} s · {2} MB', [settings.cacheMode, settings.cacheSeconds, settings.cacheMemoryMb]),
      tr('Data folder {0}', [directories?.root.path ?? tr('Unknown')]),
    ].join('\n');
  }

  @override
  void dispose() {
    _disposed = true;
    _stopCurrentChat();
    _danmaku?.stop();
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
    blockListUpdates?.stop();
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
    homeFeed?.dispose();
    appUpdater?.dispose();
    _aiFilter?.dispose();
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
    unawaited(_waylandTopNotes.close());
    unawaited(_finishedDownloads.close());
    super.dispose();
  }
}

/// What 清除本地数据 can remove.
enum LocalData {
  history('Watch history and searches'),
  progress('Playback progress'),
  recommendations('“Not interested” marks'),
  cache('Cache (video, thumbnails, translations)'),
  account('Google account sign-in'),
  keys('Translation service API keys'),
  settings('All settings (back to defaults)');

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
    if (mpv != null && mpv.isNotEmpty && !mpv.toLowerCase().startsWith(folder.toLowerCase())) File(mpv),
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
    } catch (e) {
      logDebug(() => 'Could not read a library file to warm the disk cache: $e');
    }
  }
  return total;
}

/// Whether [hwdec] asks for zero-copy DXVA2, whose interop the video output
/// only loads when it is made.
bool _zeroCopyDxva2(String hwdec) => hwdec.split(',').map((e) => e.trim()).contains('dxva2');
