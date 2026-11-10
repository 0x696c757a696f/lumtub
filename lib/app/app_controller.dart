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
import 'package:flutter/material.dart' show ThemeMode;
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../ai_filter.dart';
import '../app_directories.dart';
import '../app_updater.dart';
import '../app_log.dart';
import '../app_window.dart';
import '../app_preferences.dart';
import '../play_queue.dart';
import '../video_languages.dart';
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
import '../storyboard.dart';
import '../stream_resolver.dart';
import '../subtitle_files.dart';
import '../subtitle_cues.dart';
import '../subtitle_translation.dart';
import '../danmaku.dart';
import '../comment_danmaku.dart';
import '../language_guess.dart' show looksLike;
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

part 'explore_controller.dart';
part 'navigation_actions.dart';
part 'settings_actions.dart';
part 'picture_health.dart';
part 'chat_actions.dart';
part 'subtitle_actions.dart';
part 'smoke_check.dart';
part 'diagnostics.dart';

enum PageMode { home, explore, subscriptions, history, playlists, downloads, settings, channel, playlist, youtubePlaylist }

/// Application state and actions, kept separate from the widgets that show them.
class AppController extends ChangeNotifier with _ExploreState {
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

  /// Turns on X11 compatibility mode and starts Lumtub again in it.
  Future<void> switchToX11() async {
    final data = directories?.data;
    if (data == null) return;
    try {
      await AppWindow.x11Marker(data).writeAsString('');
    } catch (e) {
      _notice(tr('Could not switch: {0}', ['$e']));
      return;
    }
    await restart();
  }

  /// Saves everything still waiting to be written, then starts Lumtub again.
  Future<void> restart() async {
    await shutdown(install: false);
    await restartApp();
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
    if (on && !ok) return _notice(tr('Could not open picture in picture'));
    _update(() => pip = on);
    if (on) _noteWaylandTop();
  }

  /// Android began or ended picture in picture itself.
  void pipChangedBySystem(bool on) {
    AppWindow.pipChangedBySystem(on);
    if (on != pip) _update(() => pip = on);
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
    _notice(audioOnly ? tr('Audio only; the picture is not decoded') : tr('Picture back on'));
  }

  Future<void> toggleSponsorBlock() async {
    await saveSettings(settings.copyWith(sponsorBlock: !settings.sponsorBlock));
    _notice(settings.sponsorBlock ? tr('SponsorBlock turned on') : tr('SponsorBlock turned off'));
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
    } catch (_) {}
  }

  /// The TV or Chromecast the video is cast to, if any.
  final cast = CastController();

  /// The keys kept from pairing with AirPlay receivers.
  final airPlayPairings = AirPlayPairings();

  /// What to cast of [playing] to [device]: the picture and sound streams
  /// joined by lumtub_core when YouTube has a better picture apart than
  /// together (up to 1080p), else one progressive mp4 with sound, from the
  /// yt-dlp extraction or from a Piped or Invidious server.
  Future<CastMedia> castMedia(Duration start, CastDevice device) async {
    final item = playing;
    if (item == null || item.isLive || _repository == null) throw CastException(tr('No stream can be cast (a single MP4 address with sound is needed)'));
    final title = details?.title.isNotEmpty == true ? details!.title : item.title;
    // What is shown now goes to the TV too: one subtitle, or two.
    final subtitles = await castSubtitleCues();
    if (subtitles.cues.isNotEmpty) logInfo('Cast: with ${subtitles.cues.length} subtitle lines');
    CastSource? source;
    Map<String, dynamic>? info;
    try {
      info = (await _repository!.streams.resolve(item.id, _format, formatSort: _formatSort)).info;
      source = castSourceFromYtDlp(info, settings: _playback);
    } catch (e) {
      logWarn('Cast: yt-dlp could not resolve: $e');
    }
    if (info != null) {
      final split = castSplitFromYtDlp(info, maxHeight: preferences.castMaxHeight);
      if (split != null && split.height > (source?.height ?? 0)) {
        try {
          return await _joinedCast(split, device, start, title, info, subtitles);
        } catch (e) {
          logWarn('Cast: could not join the ${split.height}p picture with its sound: $e');
        }
      }
    }
    for (final kind in RelayKind.values) {
      if (source != null) break;
      try {
        source = castSourceFromRelay(await (kind == RelayKind.piped ? _piped.fetch(item.id) : _invidious.fetch(item.id)), settings: _playback);
      } catch (e) {
        logWarn('Cast: $kind could not resolve: $e');
      }
    }
    if (source == null) throw CastException(tr('No stream can be cast (a single MP4 address with sound is needed)'));
    logInfo('Casting the ${source.height}p file with picture and sound together');
    CastSubtitles? lines;
    if (subtitles.cues.isNotEmpty) {
      try {
        lines = await CastSubtitleServer.instance.register(subtitles.cues, host: await _addressFacing(device), language: subtitles.language);
      } catch (e) {
        logWarn('Cast: could not serve the subtitles: $e');
      }
    }
    return CastMedia(url: source.url, title: title, mime: source.mime, start: start, subtitles: lines);
  }

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

  Future<CastMedia> _joinedCast(CastSplit split, CastDevice device, Duration start, String title, Map<String, dynamic> info, ({List<SubtitleCue> cues, String? language}) subtitles) async {
    final core = NativeCore.instance;
    final videoId = playing?.id;
    if (core == null || videoId == null) throw StateError('no lumtub_core');
    // The cast server fetches YouTube itself, directly or through the proxy.
    final port = core.castStart();
    if (port == 0) throw StateError('the cast server could not listen');
    final here = await _addressFacing(device);
    // Apple's players take a transport stream only as HLS; TVs take it whole.
    // A format chosen for the device wins; TS and HLS carry H.264 and AAC only.
    final kind = switch (preferences.castFormats[device.id]) {
      'ts' || 'hls' when !split.fitsTransportStream => 'mp4',
      final String chosen => chosen,
      null when device.protocol == CastProtocol.dlna && split.fitsTransportStream => device is DlnaDevice && device.apple ? 'hls' : 'ts',
      null when device.protocol == CastProtocol.airplay && split.fitsTransportStream => 'hls',
      null => 'mp4',
    };
    // HLS and MKV carry the lines inside the stream, timed from the start
    // of the video; there no other subtitle file goes with them.
    final inside = (kind == 'hls' || kind == 'mkv') && subtitles.cues.isNotEmpty;
    final agent = info['http_headers'] is Map ? (info['http_headers'] as Map)['User-Agent']?.toString() : null;
    final duration = info['duration'] is num ? Duration(milliseconds: ((info['duration'] as num) * 1000).round()) : null;
    Map<String, dynamic> target(String url, int size) => {'url': url, 'size': size, if (agent != null) 'userAgent': agent, if (proxy.url != null) 'proxy': proxy.url};
    var current = split;
    var renewing = false;
    Future<void> renew() async {
      renewing = true;
      try {
        _repository!.streams.forget(videoId);
        final fresh = (await _repository!.streams.resolve(videoId, _format, formatSort: _formatSort)).info;
        final next = current.renewedFrom(fresh);
        if (next == null) {
          logWarn('Cast: the new extraction lacks formats ${current.videoFormat}+${current.audioFormat}');
          return;
        }
        final taken = core.castRenew({current.video: next.video, current.audio: next.audio});
        logInfo('Cast: renewed the stream addresses ($taken streams)');
        current = next;
      } catch (e) {
        logWarn('Cast: could not renew the stream addresses: $e');
      } finally {
        renewing = false;
      }
    }

    _castWatch?.cancel();
    // The device may take a while to load; the watch ends once it was seen
    // casting this video and no longer is, or if it never started.
    var seen = false;
    var asked = false;
    _castWatch = Timer.periodic(const Duration(seconds: 5), (timer) {
      for (final line in (jsonDecode(core.castLog() ?? '[]') as List).cast<String>()) {
        asked |= line.contains(' asked ');
        logInfo(line);
      }
      if (!asked && timer.tick == 4) {
        logWarn('Cast: ${device.name} has not asked for the stream in 20 s');
        _notice(tr('The TV has not asked Lumtub for the video yet. If it does not start, a firewall on this computer may be blocking Lumtub; allow it on this network.'));
      }
      final casting = cast.active && cast.videoId == videoId;
      seen |= casting;
      if (!casting && (seen || timer.tick > 12)) {
        timer.cancel();
        if (identical(_castWatch, timer)) _castWatch = null;
        return;
      }
      final expires = current.expires;
      final soon = expires != null && expires.difference(DateTime.now()) < const Duration(minutes: 20);
      if (!renewing && (soon || core.castExpired())) unawaited(renew());
    });
    Future<CastMedia> from(Duration at, {bool again = false}) async {
      final split = current;
      final ask = jsonEncode({
        'video': target(split.video, split.videoSize),
        'audio': target(split.audio, split.audioSize),
        'startMs': at.inMilliseconds,
        'kind': kind,
        if (duration != null) 'durationMs': duration.inMilliseconds,
        if (inside)
          'subtitles': {
            'language': subtitles.language ?? '',
            'cues': [for (final cue in subtitles.cues) [cue.start.inMilliseconds, cue.end.inMilliseconds, cue.text]],
          },
      });
      final answer = jsonDecode(await _castRegister(ask)) as Map<String, dynamic>;
      // An address YouTube refuses at once is asked for anew, once.
      if (!again && answer['path'] is! String && '${answer['error']}'.contains(RegExp(r'answered 4(03|10)'))) {
        logWarn('Cast: YouTube refused the stream addresses (${answer['error']}); resolving again');
        final before = current;
        await renew();
        if (!identical(before, current)) return from(at, again: true);
      }
      final path = answer['path'];
      if (path is! String) throw StateError('${answer['error']}');
      final begins = Duration(milliseconds: (((answer['start'] as num?) ?? 0) * 1000).round());
      logInfo('Casting ${split.height}p${split.fps} ${split.codec} joined by lumtub_core from ${begins.inSeconds} s as ${const {'hls': 'HLS', 'ts': 'MPEG-TS', 'mkv': 'MKV'}[kind] ?? 'MP4'}${inside ? ' with ${subtitles.cues.length} subtitle lines inside' : ''}');
      // The device counts time from where this stream begins.
      CastSubtitles? lines;
      if (subtitles.cues.isNotEmpty && !(inside && device.protocol != CastProtocol.chromecast)) {
        try {
          lines = await CastSubtitleServer.instance.register(subtitles.cues, host: here, offset: begins, language: subtitles.language);
        } catch (e) {
          logWarn('Cast: could not serve the subtitles: $e');
        }
      }
      return CastMedia(url: 'http://$here:$port$path', title: title, mime: const {'hls': 'application/vnd.apple.mpegurl', 'ts': 'video/mpeg', 'mkv': 'video/x-matroska'}[kind] ?? 'video/mp4', offset: begins, duration: duration, restart: from, subtitles: lines);
    }

    return from(start);
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
    VideoItem.thumbnailFile = appearance.effectiveThumbnails.file;
    videoCardMinWidth = appearance.cardWidth;
    lowResourceMode = appearance.lowResource;
    videoLayout = appearance.layout;
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
  late Translator translator = CachingTranslator(_google, _translationCache, preferences.translation.cacheScope);
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

  late final _liveProbe = YoutubePlayerProbe(_http);
  DateTime? _historyLiveChecked;

  /// The history keeps a video as it was when it was watched, so a stream
  /// watched live would stay 直播中 after it ended. Streams marked live or
  /// upcoming there are asked again, at most every 10 minutes.
  Future<void> checkHistoryLive() async {
    final store = _history;
    final last = _historyLiveChecked;
    if (store == null || (last != null && DateTime.now().difference(last) < const Duration(minutes: 10))) return;
    final marked = [for (final item in store.items) if (item.isLive || item.isUpcoming) item].take(20).toList();
    if (marked.isEmpty) return;
    _historyLiveChecked = DateTime.now();
    final states = await mapLimited(marked, 4, (item) async {
      try {
        final bytes = await _liveProbe.fetch(item.id, 'videoDetails.videoId,videoDetails.isLive,videoDetails.isUpcoming', expect: 'videoDetails');
        // No videoDetails (a bot check or a removed video) says nothing.
        if (!utf8.decode(bytes, allowMalformed: true).contains('"videoDetails"')) return item.liveStatus;
        return await liveStateOf(bytes) ?? 'was_live';
      } catch (_) {
        return item.liveStatus;
      }
    });
    final changed = {for (final (i, item) in marked.indexed) if (states[i] != item.liveStatus) item.id: states[i]};
    if (changed.isEmpty || _disposed) return;
    logInfo('History: ${changed.length} of ${marked.length} streams marked live changed');
    await store.setLiveStatus(changed);
    _update(() {});
  }
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
    if (sign == null || !sign.signedIn || logs == null) return tr('Sign in with a TV code in Settings › YouTube account first');
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
      logWarn('Could not read the YouTube playlists: $e');
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
    _notice(value ? tr('Incognito mode is on: nothing you watch or search now will be remembered') : tr('Incognito mode is off'));
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
      AppLog.level = preferences.logLevel;
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
      addToPath(paths.executableDirectories);
      MediaKit.ensureInitialized(libmpv: paths.mpv.isEmpty ? null : paths.mpv);
      final player = Player(configuration: PlayerConfiguration(
        bufferSize: settings.cacheMemoryMb * 1024 * 1024,
        // With libass, libmpv draws the subtitles and the Flutter subtitle
        // view is turned off on the watch page. It is off by default: the
        // build that turned it on for everyone also brought dropped frames.
        libass: settings.libassSubtitles,
        // libmpv's own notes only with the debug level; it says a lot.
        logLevel: preferences.logLevel == LogLevel.debug ? MPVLogLevel.info : MPVLogLevel.warn,
      ));
      final ignoredOptions = await PlayerOptionApplicator.apply(player, settings);
      if (!Platform.isWindows && player.platform is NativePlayer) {
        try {
          manager.mpvVersion = await (player.platform as NativePlayer).getProperty('mpv-version');
        } catch (_) {}
      }
      _applied = settings;
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
        _videoLanguages = VideoLanguages(_http, file: File('${directories.cache.path}${Platform.pathSeparator}heard_languages.json'));
        ChannelAvatarLookup.instance.configure(_http, File('${directories.cache.path}${Platform.pathSeparator}channel_avatars.json'));
        // Answers kept before 0.2.12 went by titles, which took some Chinese
        // ones for Japanese and every Italian one for English.
        for (final old in ['video_languages.json', 'spoken_languages.json']) {
          unawaited(File('${directories.cache.path}${Platform.pathSeparator}$old').delete().then((_) {}, onError: (_) {}));
        }
        _aiFilter = AiFilter(
          _http,
          labelsFile: File('${directories.cache.path}${Platform.pathSeparator}ai_labels.json'),
          channelsFile: File('${directories.cache.path}${Platform.pathSeparator}ai_channels.json'),
        )..addListener(_passOn('AI filter'));
        unawaited(_aiFilter!.setMode(preferences.aiFilter));
        downloads = _downloadsFor(paths, directories)..addListener(_passOn('downloads'));
        final library = this.library = LibraryController(libraryStore, client: _http)
          ..repository = _repository
          ..addListener(_passOn('library'));
        account = AccountController(
          clientFile: File('${directories.data.path}${Platform.pathSeparator}google-client.json'),
          credentials: SecureJsonFile(File('${directories.data.path}${Platform.pathSeparator}google-account.bin'), SecretProtector.forThisSystem()),
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
        status = ignoredOptions.isEmpty ? tr('Ready · Decoding method will be verified during playback') : tr('Ready · Ignored unsupported settings: {0}', [ignoredOptions.join(', ')]);
        error = null;
      });
      if (mode == PageMode.explore) _loadExplore();
      if (mode == PageMode.home) unawaited(refreshHomeFeed());
      unawaited(checkHistoryLive());
      if (mode == PageMode.subscriptions && preferences.feedAutoRefresh) {
        unawaited(library?.refreshFeed(interval: Duration(minutes: preferences.feedRefreshMinutes)));
      }
      final updater = AppUpdater(client: _http, directory: Directory('${directories.cache.path}${Platform.pathSeparator}updates'), download: manager.downloadVerified)..addListener(_passOn('updater'));
      appUpdater = updater;
      // Housekeeping waits until the first page has loaded and drawn, so
      // update checks and folder scans do not compete with it.
      unawaited(_warmUp(player));
      _afterStart = Timer(const Duration(seconds: 8), () {
        if (_disposed) return;
        if (preferences.autoCheckUpdates) unawaited(manager.checkUpdates());
        if (preferences.autoCheckUpdates || preferences.autoUpdateApp) updater.start(download: () => preferences.autoUpdateApp);
        (blockListUpdates = BlockListUpdates(client: _http, data: directories.data, cache: directories.cache)).start(wanted: () => preferences.updateBlockLists);
        unawaited(_refreshCacheSize());
        unawaited(_trimThumbnails());
      });
      unawaited(downloads?.load());
      unawaited(account?.load());
      _translationCache = TranslationCache(file: File('${directories.cache.path}${Platform.pathSeparator}translations.json'));
      _useTranslator();
      _translationKeyFile = SecureJsonFile(File('${directories.data.path}${Platform.pathSeparator}translation-keys.bin'), SecretProtector.forThisSystem());
      unawaited(_loadTranslationKeys());
      airPlayPairings.file = SecureJsonFile(File('${directories.data.path}${Platform.pathSeparator}airplay-pairings.bin'), SecretProtector.forThisSystem());
      logInfo('Components ready · libmpv ${manager.libmpv.current?.label ?? 'bundled'} · yt-dlp ${manager.ytDlpVersion ?? '?'} · ${paths.mpv}');
    } catch (e) {
      _update(() {
        error = e.toString();
        status = tr('Initialization failed');
        logError('Initialization failed', e);
      });
    }
    if (SmokeCheck.requested) unawaited(Platform.environment['LUMTUB_SHOWCASE']?.isNotEmpty == true ? runShowcase() : runSmokeCheck());
  }

  /// Checks for a new Lumtub now and downloads it, for the settings page.
  Future<void> checkAppUpdate() async => appUpdater?.check(download: AppUpdater.canInstall);

  /// Closes Lumtub, installs the downloaded update and starts it again.
  Future<void> restartToUpdate() async {
    final updater = appUpdater;
    if (updater == null || updater.ready == null) return;
    // Android's installer asks first, then replaces the running app itself.
    if (Platform.isAndroid) {
      await updater.install();
      return;
    }
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
      logWarn('Could not measure cache size: $error');
    }
  }

  Future<void> _trimThumbnails() async {
    final directory = thumbnailDirectory;
    if (_disposed || directory == null || playing != null) return;
    try {
      final freed = await trimThumbnails(directory, thumbnailCapBytes(settings.cacheLimitGb));
      if (freed > 0) {
        logDebug(() => 'Thumbnail cache over its limit, freed ${formatBytes(freed)}');
        final manager = _cacheManager;
        if (manager != null) {
          final left = await manager.size(settings);
          _update(() => cacheBytes = left);
        }
      }
    } catch (e) {
      logWarn('Could not trim the thumbnail cache: $e');
    }
  }

  void retryInitialize() {
    _update(() {
      error = null;
      status = tr('Reinstall components…');
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
      )..streams.members = () => webSignIn;

  DownloadManager _downloadsFor(ToolPaths paths, AppDirectories directories) => DownloadManager(
        file: File('${directories.data.path}${Platform.pathSeparator}downloads.json'),
        ytDlpPath: paths.ytDlp,
        onFinished: (task) {
          if (!_disposed) _finishedDownloads.add(task);
        },
        defaultDirectory: DownloadManager.defaultDirectoryFor(Platform.environment, '${directories.data.path}${Platform.pathSeparator}downloads'),
        environment: () => _repository!.processEnvironment,
        // lumtub_core joins the streams, so no ffmpeg is needed.
        join: NativeCore.canJoin
            ? (request) {
                final json = request.toJson();
                return Isolate.run(() => NativeCore.join(json));
              }
            : null,
        cover: _coverBytes,
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
    final bytes = await _coverBytes(item.id);
    if (bytes == null) throw StateError(tr('This video has no cover image'));
    final file = File(_downloadPath(item, '.jpg'));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// The largest JPEG cover of video [id], or null when it has none.
  Future<List<int>?> _coverBytes(String id) async {
    for (final name in const ['maxresdefault', 'sddefault', 'hqdefault']) {
      final http.Response response;
      try {
        response = await _http.get(Uri.https('i.ytimg.com', '/vi/$id/$name.jpg')).timeout(const Duration(seconds: 20));
      } catch (_) {
        throw StateError(tr("Couldn't download the cover; check the network or proxy"));
      }
      // YouTube answers a missing size with a small placeholder or 404.
      if (response.statusCode != 200 || response.bodyBytes.length < 2000) continue;
      return response.bodyBytes;
    }
    return null;
  }

  /// The subtitles [item] offers, with the one translated into 第一字幕语言
  /// when the video has none in it.
  Future<List<SubtitleOption>> subtitleOptionsFor(VideoItem item) async {
    final known = playing?.id == item.id ? details : null;
    final repository = _repository;
    final offered = known?.subtitles ?? (repository == null ? const <SubtitleOption>[] : (await repository.details(item.id)).subtitles);
    final target = settings.subtitleLanguage.translation;
    final translation = hasOwnSubtitle(offered, target) ? null : translationOf(offered, target, language: known?.language);
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
    if (manager == null || item.isLive || item.isUpcoming) return _notice(tr('Live streams cannot be downloaded'));
    _notice(manager.add(item, quality, selection: selection) == null ? tr('Already in the download list') : tr('Added to downloads'));
  }

  /// The streams [videoId] can be downloaded as, from the extraction the
  /// player shares (one yt-dlp run per video).
  Future<DownloadFormats> downloadFormats(String videoId) async {
    final repository = _repository;
    if (repository == null) throw StateError(tr('Components are not ready yet'));
    final info = (await repository.streams.resolve(videoId, _format, formatSort: _formatSort)).info;
    // Automatic picks follow the playback order, so a download is in a codec
    // this PC decodes well; the quality strategy takes the best picture.
    final preference = settings.strategy == PlaybackStrategy.quality ? const <VideoCodec>[] : FormatPolicy.codecOrder(settings);
    final formats = await DownloadFormats.parseInBackground(info, preference: preference);
    // lumtub_core joins the streams, and takes AAC, Opus and Dolby sound.
    if (downloads?.join != null && formats.audio.any((a) => a.joins)) {
      return DownloadFormats(formats.video, [for (final a in formats.audio) if (a.joins) a], preference: formats.preference);
    }
    return formats;
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
      roots: settings.certificateRoots,
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
      await play(VideoItem(id: asUrl, title: tr('YouTube video · {0}', [asUrl]), channel: 'YouTube', url: 'https://www.youtube.com/watch?v=$asUrl'));
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

  /// Plays [item]; [from] is the list it was picked from and becomes the queue.
  /// Opens [item] on the watch page; [at] is where to start, else where
  /// it was left off. [keepMini] plays it in the mini player when that is
  /// where the last video was (the queue moving on by itself).
  Future<void> play(VideoItem item, {List<VideoItem>? from, PlayingList? list, Duration? at, bool keepMini = false, bool retryingStart = false}) async {
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
      if (list != null) {
        playingList = list;
        queue = List.unmodifiable(list.ordered);
      } else if (from != null) {
        playingList = null;
        queue = List.unmodifiable(from);
      }
      // A stream being waited for keeps saying so until it plays.
      if (!retryingStart) {
        playbackError = null;
        _waitingForStart = false;
      }
      details = null;
      loadingDetails = true;
      replayChat = const [];
      chatTicker = const [];
      loadingReplayChat = false;
      replayChatError = null;
      availableHeights = const [];
      availableFrameRates = const {};
      related?.dispose();
      related = null;
      _segments = const [];
      _skipped.clear();
      dislikes = null;
    });
    _syncDanmaku();
    _subtitlesSerial = serial;
    _subtitlesReady = Completer<void>();
    unawaited(_loadDetails(item, serial));
    if (settings.returnDislike) unawaited(_loadDislikes(item, serial));
    if (settings.sponsorBlock) unawaited(_loadSegments(item, serial));
    // Another video asked for meanwhile takes over its history and queue.
    // Held until a translated subtitle shown by itself is ready, so the
    // first lines are not missed; other subtitles load as it plays.
    final hold = preferences.autoPlay && settings.subtitleMode != SubtitleMode.off && !item.isLive;
    if (await _open(item, serial, start: start, play: preferences.autoPlay && !hold) && serial == _playSerial) {
      if (hold) unawaited(_playOnceSubtitlesReady(serial));
      await _applyChannelPlayback(item, player);
      if (preferences.recordHistory && !incognito) await _history?.record(item);
      if (start != null && at == null) _notice(tr('Resume from {0}', [_clock(start)]));
      final next = upNext.firstOrNull;
      if (next != null) prefetch(next);
      // Marked live while it opened, when the list did not know.
      final opened = playing?.id == item.id ? playing! : item;
      if (opened.isLive) {
        _startCurrentChat(opened, serial);
      } else if (item.liveStatus == 'was_live') {
        unawaited(_loadReplayChat(item, serial));
      }
    }
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
      if (settings.sponsorNotice) _notice(tr('Skipped {0}', [sponsorCategories[segment.category] ?? tr('Segments')]));
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
    // Android's executable is the system's app_process, in a folder apps may not list.
    final bytes = Platform.isAndroid || Platform.isIOS ? 0 : await Isolate.run(_readingPlayerFiles(folder, mpv));
    logDebug(() => 'Read ${bytes >> 20} MB of player files in ${read.elapsedMilliseconds} ms');
    final directories = this.directories;
    if (directories != null) {
      try {
        final shaders = Directory('${directories.cache.path}${Platform.pathSeparator}shaders').listSync().whereType<File>().length;
        logDebug(() => 'Shader cache holds $shaders shaders');
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
    unawaited(controller.platform.future.then((_) => logDebug(() => 'Video output made in ${made.elapsedMilliseconds} ms'), onError: (Object error) => logError('Video output failed', error)));
  }

  /// The play whose first open already tried a quick start.
  int? _quickSerial;

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
        logWarn('The download of ${item.id} is ${localCodec!.label}, a codec the playback rules disable; playing online instead');
        _notice(tr('The downloaded file is {0}, which the playback rules disable; streaming instead', [localCodec.label]));
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
          final streams = _repository!.streams;
          // Android asks the core first: yt-dlp runs in Python there, which
          // costs a phone seconds of work, so it only steps in when the core
          // has no answer, and for live and members-only videos.
          if (Platform.isAndroid) {
            if (!item.isLive && !item.membersOnly) {
              try {
                video = await streams.quick(item.id, format, FormatPolicy.settingsJson(_playback));
              } catch (e) {
                logWarn('Quick start of ${item.id} failed: $e');
              }
            }
            if (video == null && streams.ytDlpPath.isEmpty) {
              throw StateError(item.isLive || item.membersOnly ? 'Live streams and members-only videos need yt-dlp, which could not be started' : 'YouTube gave no streams this version can play');
            }
          }
          var pending = video != null ? Future.value(video) : streams.resolve(item.id, format, formatSort: formatSort, membersOnly: item.membersOnly, live: item.isLive);
          // The first open of a video also asks YouTube directly; whichever
          // answers first starts it. A reopen after a failure waits for yt-dlp.
          if (video == null && !Platform.isAndroid && _quickSerial != serial && !item.isLive && !item.membersOnly && !streams.resolved(item.id, format)) {
            _quickSerial = serial;
            final full = pending;
            pending = Future.any([
              full,
              streams.quick(item.id, format, FormatPolicy.settingsJson(_playback)).then((quick) {
                if (quick == null) return full;
                streams.unhurried(item.id);
                return quick;
              }),
            ]);
          }
          video = await pending;
        } catch (e) {
          _recentErrors.add('$e');
          final failure = PlaybackFailure.classify(['$e']);
          if (!failure.retryable) {
            // libmpv's ytdl_hook would ask YouTube again and fail the same way.
            if (_serversMayHelp(failure.kind)) return await _fallBack(item, serial, failure, start: start, play: play);
            if (serial == _playSerial) _fail(item, failure);
            return false;
          }
          // libmpv cannot start yt-dlp on Android.
          if (Platform.isAndroid) {
            if (serial == _playSerial) _fail(item, failure);
            return false;
          }
          logError('Prefetching ${item.id} failed, letting libmpv resolve it', e);
        }
        if (serial != _playSerial) return false;
      }
      // A list may not know a video is live; yt-dlp does.
      if (!item.isLive && video?.info['live_status'] == 'is_live') {
        item = item.withLiveStatus('is_live');
        if (playing?.id == item.id) _update(() => playing = item);
      }
      final live = item.isLive;
      // A live stream starts at its live edge, not at a remembered spot.
      if (live) start = null;
      // Through the relay, which reaches YouTube as libmpv would: directly
      // or through the proxy, a SOCKS one too.
      // A video whose stream broke through it is reopened without it.
      final relay = _unrelayed != item.id ? _relay : null;
      final agent = video?.userAgent;
      // Subtitles are added by the app (see _autoSubtitles), so they do not
      // need ytdl_hook: through it libmpv reads the streams itself, slowly
      // once its cache is full, and YouTube cuts those connections.
      final direct = video != null && video.format == format && !live
          ? video.directAddress(relay: relay == null ? null : (url, size) => relay.register(url, size: size, userAgent: agent, proxy: proxy.url))
          : null;
      _relayed = direct != null && relay != null ? item.id : null;
      _openedDirect = direct != null ? item.id : null;
      final split = live && video != null && relay != null && _liveSplitOff != item.id ? _liveSplitAddress(video, relay) : null;
      _liveSplit = split != null ? item.id : null;
      final platform = player.platform;
      if (platform is NativePlayer) {
        // A live stream plays from one HLS stream with picture and sound
        // together up to 1080p: a picture and a sound stream apart can
        // drift out of sync, so they are taken only above it.
        await platform.setProperty('ytdl-format', live ? FormatPolicy.liveExpression(_playback, format) : format);
        await platform.setProperty('ytdl-raw-options', PlayerOptionApplicator.ytdlRawOptions(settings, infoJson: direct == null ? video?.file.path : null, proxy: proxy.ytDlpValue(settings.proxyMode), formatSort: _formatSort));
        if (direct != null && agent != null) await platform.setProperty('user-agent', agent);
        // The relay asks YouTube in chunks and reads each reply to its end
        // itself; libmpv asking it in small pieces would only cut those
        // chunks short.
        await platform.setProperty('curl-max-request-size', _relayed == item.id ? '64MiB' : PlayerOptionApplicator.curlRequestSize);
      }
      _tracking = null;
      if (secondarySubtitle != null) {
        secondarySubtitle = null;
        if (platform is NativePlayer) unawaited(SecondarySubtitle.off(platform).catchError((_) {}));
      }
      _lastPosition = start ?? Duration.zero;
      _resumePoint.start(_lastPosition);
      _openedResolved = video == null ? null : item.id;
      _openedOrigin = video?.origin;
      if (video != null) {
        _update(() {
          availableHeights = video!.heightsFor(settings);
          availableFrameRates = video.frameRatesFor(settings);
        });
      }
      await _forgetCrop(player);
      await player.open(Media(direct ?? split ?? item.url, start: start), play: play);
      if (serial == _playSerial) _tracking = item;
      _mpvLogLines = 0;
      _lastDrops = 0;
      _dropStreak = 0;
      _openedAt = DateTime.now();
      _openIssued = item.id;
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

  /// The live stream opened as its picture and sound above 1080p, joined
  /// fragment by fragment in the relay (see [LiveSplit]).
  String? _liveSplit;
  /// The live stream whose split picture and sound failed soon after
  /// opening twice, so it plays from HLS instead, up to 1080p.
  String? _liveSplitOff;
  /// The live stream whose split picture and sound failed soon after
  /// opening once: it gets one more try before HLS.
  String? _liveSplitBroke;

  /// An mpv address playing [video]'s live picture above 1080p with its
  /// sound through [relay], or null when there is none within the cap.
  String? _liveSplitAddress(ResolvedVideo video, StreamRelay relay) {
    final split = LiveSplit.pick(video.info, _playback);
    if (split == null) return null;
    final pair = '${video.info['id']}-${DateTime.now().microsecondsSinceEpoch}';
    final proxy = this.proxy.url;
    final picture = relay.registerLive(split.videoUrl, pair: pair, userAgent: split.userAgent, proxy: proxy);
    final sound = relay.registerLive(split.audioUrl, pair: pair, userAgent: split.userAgent, proxy: proxy);
    if (picture == null || sound == null) return null;
    logInfo('Live ${video.info['id']} plays ${split.label} through the relay');
    return NativeCore.instance?.edl([picture, sound]);
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
      if (platform is NativePlayer) unawaited(SecondarySubtitle.off(platform).catchError((_) {}));
    }
    _lastPosition = start ?? Duration.zero;
    _resumePoint.start(_lastPosition);
    _openedLocal = item.id;
    await _forgetCrop(player);
    await player.open(Media(local.file.path, start: start), play: play);
    if (serial == _playSerial) _tracking = item;
    _mpvLogLines = 0;
    _lastDrops = 0;
    _dropStreak = 0;
    _openedAt = DateTime.now();
    _openIssued = item.id;
    _decoderPending = true;
    _update(() {});
    unawaited(_addLocalSubtitles(local, serial));
    return true;
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
      await _forgetCrop(player);
      await player.open(Media(address, start: start), play: play);
      if (serial == _playSerial) _tracking = item;
      _mpvLogLines = 0;
      _lastDrops = 0;
      _dropStreak = 0;
      _openedAt = DateTime.now();
      _openIssued = item.id;
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
    if (_youtubeRefused == null) logWarn('YouTube would not play ${item.id} (${failure.kind.name}); trying Piped and Invidious');
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
      _update(() {
        availableHeights = video.heightsFor(settings);
        availableFrameRates = const {};
      });
      logInfo('Playing ${item.id} from $name ${video.server}, took ${watch.elapsedMilliseconds} ms');
      return address;
    } catch (e) {
      logWarn('$e; not using $name');
      return null;
    }
  }

  /// Shows why [item] cannot play and acts on the cause.
  void _fail(VideoItem item, PlaybackFailure failure) {
    _recoveryTimer?.cancel();
    _recovery.cancelPending();
    logError('Playback failed ${item.id} (${failure.kind.name}): ${failure.detail}');
    if (failure.kind == FailureKind.noFormat) failure = PlaybackFailure(failure.kind, failure.detail, disabled: FormatPolicy.disabledNames(settings));
    if (failure.kind == FailureKind.membersOnly) failure = PlaybackFailure(failure.kind, failure.detail, signedIn: webSignIn?.signedIn == true);
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
    logWarn('${item.id} has not started, opening it again in ${delay.inSeconds} s');
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
    logWarn('Playback interrupted, reconnecting ${item.id} at ${_clock(position)}: $message');
    if (_relayed == item.id) {
      _unrelayed = item.id;
      logWarn('Playing ${item.id} without the local chunked relay');
    }
    // A split live stream that broke at once twice is played from HLS; one
    // that played a while, or broke once, gets new addresses and stays
    // split.
    if (_liveSplit == item.id && DateTime.now().difference(_openedAt) < const Duration(minutes: 1)) {
      if (_liveSplitBroke == item.id) {
        _liveSplitOff = item.id;
        logWarn('Playing live ${item.id} from HLS, up to 1080p');
      } else {
        _liveSplitBroke = item.id;
      }
    }
    _notice(tr('Connection lost, reconnecting from {0}…', [_clock(position)]));
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

  bool _remakingOutput = false;
  final _outputRemade = <DateTime>[];

  /// The graphics device went away (a driver reset, say), so libmpv's
  /// hardware-decoded frames no longer reach the picture, which flickers or
  /// freezes. The video output is made again, on a new Direct3D device, and
  /// the video reopened where it was. When that happens again soon after,
  /// hardware decoding stays off until Lumtub restarts.
  Future<void> _remakeVideoOutput(Player player, String reason) async {
    final old = videoController;
    if (_remakingOutput || _disposed || old == null || this.player != player) return;
    _remakingOutput = true;
    final item = _tracking ?? playing;
    final position = _lastPosition;
    final now = DateTime.now();
    _outputRemade.removeWhere((at) => now.difference(at) > const Duration(minutes: 10));
    if (_outputRemade.length >= 3) {
      if (_outputRemade.length == 3) {
        _outputRemade.add(now);
        logError('The graphics device keeps getting lost; leaving the video output as it is', reason);
        _notice(tr('The graphics driver keeps resetting; please restart Lumtub'));
      }
      return;
    }
    final again = _outputRemade.isNotEmpty;
    logWarn('The graphics device was lost ($reason); making the video output again${again ? ' and decoding in software' : ''}');
    _recovering = true;
    try {
      await player.pause();
      await old.release();
      if (_disposed || this.player != player) return;
      videoController = null;
      _ensureVideo(player);
      _outputRemade.add(now);
      _update(() {});
      _notice(again ? tr('The graphics driver reset again; decoding in software until Lumtub restarts') : tr('The graphics driver reset; the picture was made again'));
      await videoController?.platform.future;
      // Making the output sets hwdec from the settings again.
      final platform = player.platform;
      if (again && platform is NativePlayer) await platform.setProperty('hwdec', 'no');
      if (item != null && !_disposed && playing?.id == item.id) await _open(item, _playSerial, start: position > Duration.zero ? position : null);
    } catch (e) {
      logError('Could not make the video output again', e);
    } finally {
      _recovering = false;
      _remakingOutput = false;
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

  final _cues = <String, List<SubtitleCue>>{};

  /// The chapter titles of [chapterTranslationOf] translated, one for
  /// each chapter, once asked for; untouched ones stay as they are.
  List<String>? chapterTranslation;
  String? chapterTranslationOf;
  bool translatingChapters = false;
  /// Bumped when [chapterTranslation] or [translatingChapters] changes,
  /// for the chapter menu, which does not rebuild with everything else.
  final chaptersChanged = ValueNotifier<int>(0);

  static const subtitleWait = Duration(seconds: 10);

  /// The video opened is held until its translated subtitle is ready.
  bool waitingForSubtitles = false;

  Future<void> retryPlayback() async {
    final item = playing;
    if (item != null) await play(item);
  }

  bool _subtitlesFollowing = false;

  void _listenTo(Player player) {
    void videoSize(_) {
      _outputSize?.video = Size((player.state.width ?? 0).toDouble(), (player.state.height ?? 0).toDouble());
      if ((player.state.width ?? 0) > 0) _refitCrop(player);
    }
    final platform = player.platform;
    if (platform is NativePlayer) {
      // The subtitles shown are followed as mpv reports them, as it can
      // change either by itself; the panel and the list read them here.
      // media_kit waits for these listeners before it reads the next mpv
      // event, so they only schedule the work: awaiting the player here
      // would stall playback (and deadlock on the player's lock).
      unawaited(platform.observeProperty('sid', (_) async => _followSubtitles(player)).catchError((Object e) => logWarn('Could not follow the subtitle: $e')));
      unawaited(platform.observeProperty('secondary-sid', (value) async {
        secondaryTrackId = value.isEmpty || value == 'false' ? 'no' : value;
        _followSubtitles(player);
      }).catchError((Object e) => logWarn('Could not follow the second subtitle: $e')));
    }
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
        if (_segments.isNotEmpty && settings.sponsorBlock) _skipSegments(position);
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
        // A live stream through the relay ends only when its fragments
        // stopped coming.
        if (_tracking != null && (_liveSplit == _tracking!.id || PlaybackRecovery.endedEarly(_lastPosition, player.state.duration))) {
          unawaited(_recover(tr('Video ended unexpectedly at {0}', [_clock(_lastPosition)])));
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
          logWarn('Subtitles failed to load, video keeps playing: $message');
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
        final lost = log.prefix == 'curl' && text.startsWith('transfer failed');
        if (lost) _streamLostIn = _playSerial;
        // Data cut off mid-frame, after curl lost a stream, leaves the
        // decoder failing on every frame over a still picture.
        if (log.prefix == 'vd' && text.startsWith('Error while decoding frame')) {
          final now = DateTime.now();
          _decodeErrors
            ..add(now)
            ..removeWhere((at) => now.difference(at) > const Duration(seconds: 10));
        }
        // Opened again at once rather than after the picture watch notices.
        if ((lost || _decodeErrors.length >= 3) && player.state.playing && DateTime.now().difference(_lastBrokenReopen) > const Duration(seconds: 30)) {
          _lastBrokenReopen = DateTime.now();
          _decodeErrors.clear();
          unawaited(_recover(lost ? 'libmpv gave up on a stream' : 'The video data broke and frames stopped decoding'));
        }
        if (PlaybackRecovery.graphicsLost(text)) unawaited(_remakeVideoOutput(player, text));
        // The same line for every frame says nothing new.
        if (text == _lastMpvLine) return;
        _lastMpvLine = text;
        if (_mpvLogLines >= (AppLog.level == LogLevel.debug ? 2000 : 200)) return;
        _mpvLogLines++;
        final line = 'mpv [${log.prefix}] ${log.level}: $text';
        switch (log.level) {
          case 'fatal' || 'error':
            logError(line);
          case 'warn':
            logWarn(line);
          default:
            logDebug(() => line);
        }
      }),
      // A stream that stops delivering data leaves mpv buffering forever.
      player.stream.buffering.listen((buffering) {
        _stallTimer?.cancel();
        if (!buffering || _tracking == null) return;
        _stallTimer = Timer(PlaybackRecovery.stallTimeout, () {
          if (player.state.buffering && player.state.playing) unawaited(_recover('No buffering progress for over ${PlaybackRecovery.stallTimeout.inSeconds} seconds'));
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
        logWarn('Piped or Invidious address did not play ($message); ${limited != null ? 'trying the next server' : 'connecting to YouTube directly'}');
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
        logWarn('Prefetched address did not play ($message; $_openedOrigin); libmpv resolves ${item.id} again');
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
      _notice(tr('Sleep timer: current video finished'));
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
    _notice(tr('Will play after the current video'));
  }

  /// 加入播放队列: [item] goes to the end of [playQueue].
  void queueLast(VideoItem item) {
    final added = playQueue.addLast(item);
    _update(() {});
    _notice(added ? tr('Added to the play queue') : tr('The play queue already has this video'));
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
        logWarn('Could not refresh the picture after restoring: $e');
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
      _notice(tr('Sleep timer: playback paused'));
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
    await seek(target);
  }

  /// Seeks the playing video to [target]. The split live stream holds only
  /// the fragments fetched so far, and a seek outside them would leave the
  /// decoder without a keyframe, broken until the next: forward then goes
  /// to the newest moment, backward stays where it is.
  Future<void> seek(Duration target) async {
    final player = this.player;
    if (player == null) return;
    if (_liveSplit != null && _liveSplit == playing?.id && !await _splitHolds(player, target)) {
      if (target > player.state.position) return goLive();
      _notice(tr('This live stream cannot go back further at this quality'));
      return;
    }
    await player.seek(target);
  }

  /// Whether libmpv's cache holds [target] of the split live stream.
  Future<bool> _splitHolds(Player player, Duration target) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return false;
    try {
      final cache = jsonDecode(await platform.getProperty('demuxer-cache-state'));
      final ranges = cache is Map ? cache['seekable-ranges'] : null;
      final at = target.inMilliseconds / 1000;
      return ranges is List && ranges.any((r) => r is Map && r['start'] is num && r['end'] is num && at >= (r['start'] as num) && at <= (r['end'] as num) - 1);
    } catch (_) {
      return false;
    }
  }

  /// How far behind its live edge a live stream may play before the
  /// player offers to jump back to it. A split stream above 1080p starts
  /// about 20 s behind on purpose (see relay_live.rs BEHIND).
  static const liveBehind = Duration(seconds: 30);

  /// Jumps a live stream to its newest moment, at normal speed, playing.
  /// The last seconds are left alone: libmpv at the very end of a live
  /// playlist waits for segments that do not exist yet.
  Future<void> goLive() async {
    final player = this.player;
    if (player == null) return;
    // The split stream cannot seek; it is opened again at the newest fragment.
    if (_liveSplit != null && _liveSplit == playing?.id) return reloadVideo();
    final duration = player.state.duration;
    if (duration > Duration.zero) {
      final target = duration - const Duration(seconds: 3);
      await player.seek(target < Duration.zero ? Duration.zero : target);
    }
    if (player.state.rate != 1) await player.setRate(1);
    if (!player.state.playing) await player.play();
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
    if (saved?.rate case final kept? when kept != settings.defaultSpeed) _notice(tr('This channel plays at its last speed, {0}x', [rateText(kept)]));
    final volume = saved?.volume?.toDouble() ?? _sessionVolume;
    if (volume != null && volume != player.state.volume) await player.setVolume(volume.clamp(0.0, settings.volumeMax.toDouble()).toDouble());
    if (this.player == player && playing?.id == item.id) _playbackChannel = key;
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
    if (item == null) throw TranslationException(tr('No video is playing'));
    if (_summaries[item.id] case final done?) return done;
    final ai = aiServiceFor(preferences.translation, translationKeys, _http);
    if (ai == null) throw TranslationException(tr('Set up the AI interface and key under Translation & AI first'));
    final subtitles = details?.subtitles ?? const <SubtitleOption>[];
    final option = originalSubtitle(subtitles, language: details?.language) ?? subtitles.firstOrNull;
    final title = details?.title.isNotEmpty == true ? details!.title : item.title;
    final String summary;
    if (option == null) {
      // No subtitles, not even YouTube's automatic ones: the description
      // and chapters are all there is to go on.
      final description = details?.description ?? '';
      final chapters = [for (final c in details?.chapters ?? const <Chapter>[]) (start: c.start, title: c.title)];
      if (!canSummarizeDescription(description, chapters)) throw TranslationException(tr('This video has no subtitles and its description is too short to summarize'));
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

  /// The video's brightness, within [pictureLimit], as 画面与音画同步调节 keeps it.
  int get brightness => settings.picture['brightness'] ?? 0;
  Timer? _brightnessSave;

  /// Brightens or darkens the video by [delta] and returns the new value;
  /// saved, and shown to the rest of the app, once the changes pause, not
  /// at every wheel notch or slide step.
  Future<int> changeBrightness(int delta) async {
    final value = (brightness + delta).clamp(-pictureLimit('brightness'), pictureLimit('brightness'));
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
        if (asDefault) _notice(tr('VP9 and AV1 are both disabled, and H.264 stops at 1080p'));
      } else if (!usable.any((codec) => FormatPolicy.hardware(next, codec))) {
        _notice(tr('This PC cannot decode VP9 or AV1 in hardware, so 1440p and 4K are decoded on the CPU and use a lot of it'));
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

  /// The codec and height the playback test plays at, while it runs.
  PlayerSettings? _benchmark;

  String get _format => FormatPolicy.expression(_playback);

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
          final resolved = await _repository!.streams.resolve(item.id, _format, formatSort: _formatSort, membersOnly: item.membersOnly);
          loaded = resolved.details;
          if (serial == _playSerial) {
            _update(() {
              availableHeights = resolved.heightsFor(settings);
              availableFrameRates = resolved.frameRatesFor(settings);
            });
            final lost = resolved.lostToDisabled(settings, _playback.maxHeight);
            if (lost != null) {
              _notice(tr("This video's {0}p is only in {1}, which is disabled; playing {2}p", [lost.height, lost.codecs.map((c) => c.label).join(' / '), lost.playing]));
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
          _subtitlesSettled(serial);
          unawaited(_showSpeech(speech, serial));
        } else {
          unawaited(_autoSubtitles(item, loaded, serial).whenComplete(() => _subtitlesSettled(serial)));
        }
      } else {
        _subtitlesSettled(serial);
      }
    } catch (_) {
      // The page still shows what the list already knew about the video.
      _subtitlesSettled(serial);
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

  /// Whether playlist [id] is shown and played last to first.
  bool isReversed(String id) => preferences.reversedPlaylists.contains(id);

  /// Shows and plays playlist [id] last to first, or in its own order; the
  /// playlist playing now follows at once.
  Future<void> setReversed(String id, bool reversed) async {
    final ids = [for (final other in preferences.reversedPlaylists) if (other != id) other, if (reversed) id];
    final list = playingList;
    if (list != null && list.id == id && list.reversed != reversed) {
      _update(() {
        playingList = list.withReversed(reversed);
        queue = List.unmodifiable(playingList!.ordered);
      });
    }
    await savePreferences(preferences.copyWith(reversedPlaylists: ids));
  }

  /// Plays playlist [id] from [start], or from its first video in the
  /// order chosen for it.
  Future<void> playList(String id, String title, List<VideoItem> items, {VideoItem? start}) {
    final list = PlayingList(id: id, title: title, items: List.unmodifiable(items), reversed: isReversed(id));
    return play(start ?? list.ordered.first, list: list);
  }

  /// Reads the rest of the open YouTube playlist, so it can be shown last
  /// to first.
  void loadWholeYoutubePlaylist() {
    final loader = youtubePlaylistVideos;
    if (loader == null || _loadingWhole == loader) return;
    _loadingWhole = loader;
    void more() {
      if (!identical(loader, youtubePlaylistVideos) || !loader.hasMore || loader.error != null || loader.items.length >= 5000) {
        loader.removeListener(more);
        if (identical(_loadingWhole, loader)) _loadingWhole = null;
        return;
      }
      if (!loader.loading) scheduleMicrotask(loader.loadMore);
    }
    loader.addListener(more);
    more();
  }

  VideoListLoader? _loadingWhole;

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
  /// to the system. Coming back to the video opens it again where it was left.
  void _unload() {
    final player = this.player;
    if (player == null) return;
    unawaited(player.stop().then((_) => releaseMemory()));
  }

  /// Hands memory freed by closed videos back to the system.
  void releaseMemory() {
    final before = ProcessInfo.currentRss;
    releaseFreedMemory();
    logDebug(() => 'Released idle memory: ${before >> 20} MB → ${ProcessInfo.currentRss >> 20} MB');
  }

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

  /// Videos of [items] that pass the privacy and content filters. The
  /// subscriptions feed is filtered only when [AppPreferences.filterSubscriptions].
  List<VideoItem> visible(List<VideoItem> items, {bool subscriptions = false, bool search = false}) {
    final prefs = preferences;
    // Pages filter their lists on every rebuild, and a feed runs to a
    // thousand items: the answer is kept while the list and the preferences
    // stay. Hiding watched videos also follows which videos are finished.
    final ai = _aiFilter;
    final key = (prefs, subscriptions, search, search ? _query : null, prefs.hideWatched ? (library?.store, library?.store.finishedVersion) : null, ai?.version);
    if (_visible[items] case (final known, final kept) when known == key) return kept;
    var kept = _filter(items, prefs, subscriptions: subscriptions, search: search);
    // Subscribed channels are the viewer's own choice.
    if (ai != null && ai.mode != AiFilterMode.off && !subscriptions) {
      bool followed(VideoItem item) => item.channelId != null && (library?.isFollowing(item.channelId!) ?? false);
      kept = [for (final item in kept) if (followed(item) || !ai.hides(item)) item];
      ai.check(kept.where((item) => !followed(item)));
    }
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

  /// Saves everything and releases the player before the window closes;
  /// dispose() alone does not run when Windows ends the process.
  Future<void> shutdown({bool install = true}) async {
    if (_shutDown) return;
    _shutDown = true;
    // Android installs only when asked: its installer shows a dialog.
    if (install && !Platform.isAndroid) await appUpdater?.install();
    _saveProgress();
    _countWatchTime(flush: true);
    await (watchTime?.save() ?? Future.value(), channelPlayback?.save() ?? Future.value()).wait;
    await library?.flush();
    await downloads?.flush();
    await _translationCache.save();
    await _flushAppearance();
    if (_brightnessSave?.isActive ?? false) {
      _brightnessSave!.cancel();
      await _settingsStore?.save(settings);
    }
    for (final subscription in _playerSubscriptions) {
      await subscription.cancel();
    }
    _playerSubscriptions.clear();
    _stallTimer?.cancel();
    _recoveryTimer?.cancel();
    await player?.pause();
    // The video output goes while the engine still runs: left to the
    // engine's own teardown, unregistering its texture crashed Flutter.
    try {
      await videoController?.release().timeout(const Duration(seconds: 3));
    } catch (e) {
      logWarn('The video output was not released before exit: $e');
    }
    videoController = null;
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
    } catch (_) {}
  }
  return total;
}

/// Whether [hwdec] asks for zero-copy DXVA2, whose interop the video output
/// only loads when it is made.
bool _zeroCopyDxva2(String hwdec) => hwdec.split(',').map((e) => e.trim()).contains('dxva2');
