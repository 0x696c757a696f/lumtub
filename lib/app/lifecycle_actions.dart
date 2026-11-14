part of 'app_controller.dart';

/// Starting the app up, updating it and shutting it down.
extension LifecycleActions on AppController {
  /// Writes the watch history now, for when the app may be ended without
  /// [shutdown] (Android in the background).
  Future<void> flushHistory() => _history?.flush() ?? Future.value();

  /// Starts Lumtub up: once at a time, and not again once it is ready.
  Future<void> initialize() {
    if (ready || _disposed) return Future.value();
    return _initializing ??= _initializeOnce().whenComplete(() => _initializing = null);
  }

  Future<void> _initializeOnce() async {
    // Made by this attempt and not yet handed over; released if it fails.
    Player? madePlayer;
    StreamRelay? madeRelay;
    try {
      final directories = await AppDirectories.create();
      // yt-dlp, including the one libmpv starts, writes some temporary
      // files (format tests) to the working folder, which is the install
      // folder and read-only under Program Files.
      try {
        Directory.current = directories.cache;
      } catch (e) {
        logDebug(() => 'Could not change the working directory: $e');
      }
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
      final supportReminder = SupportReminder(File('${directories.config.path}${Platform.pathSeparator}support_reminder.json'));
      final (_, _, _, settings, preferences, _, _, _) = await (history.initialize(), notInterested.load(), libraryStore.load(), settingsStore.load(), preferencesStore.load(), channelPlayback.load(), watchTime.load(), supportReminder.load()).wait;
      this.supportReminder = supportReminder..used(DateTime.now());
      AppLog.level = preferences.logLevel;
      this.channelPlayback = channelPlayback;
      this.watchTime = watchTime;
      speechStore = SpeechSubtitleStore(Directory('${directories.data.path}${Platform.pathSeparator}speech'));
      // An earlier attempt that failed may have left one.
      homeFeed?.dispose();
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
      final player = madePlayer = Player(configuration: PlayerConfiguration(
        bufferSize: settings.cacheMemoryMb * 1024 * 1024,
        // With libass, libmpv draws the subtitles and the Flutter subtitle
        // view is turned off on the watch page. It is off by default: the
        // build that turned it on for everyone also brought dropped frames.
        libass: settings.libassSubtitles,
        // libmpv's own notes only with the debug level; it says a lot.
        logLevel: preferences.logLevel == LogLevel.debug ? MPVLogLevel.info : MPVLogLevel.warn,
      ));
      final ignoredOptions = await PlayerOptionApplicator.apply(player, settings);
      _optionsApplied(player);
      if (!Platform.isWindows && player.platform is NativePlayer) {
        try {
          manager.mpvVersion = await (player.platform as NativePlayer).getProperty('mpv-version');
        } catch (e) {
          logDebug(() => 'Could not read the mpv version: $e');
        }
      }
      _applied = settings;
      // Compiled shaders are kept between runs, so a video's first frame
      // does not wait for them again.
      final platform = player.platform;
      if (platform is NativePlayer) {
        if (Platform.isAndroid) {
          final fonts = await AndroidSubtitleFonts.prepare('${directories.cache.path}/subtitle-fonts');
          if (fonts != null) await platform.setProperty('sub-fonts-dir', fonts).catchError((Object e) => logDebug(() => 'Could not set the subtitle fonts: $e'));
        }
        final shaders = Directory('${directories.cache.path}${Platform.pathSeparator}shaders');
        try {
          shaders.createSync(recursive: true);
          await platform.setProperty('gpu-shader-cache-dir', shaders.path);
        } catch (e) {
          logDebug(() => 'Could not set up the shader cache folder: $e');
        }
      }
      _lightRendering = null;
      await _applyProxy(player);
      unawaited(_relay?.close());
      _relay = madeRelay = await _startRelay();
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
        await madeRelay?.close();
        _relay = null;
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
        VideoFactsLookup.instance.configure(_http, File('${directories.cache.path}${Platform.pathSeparator}video_facts.json'));
        unawaited(EmojiPictures.configure(File('${directories.cache.path}${Platform.pathSeparator}emoji_pictures.json')));
        unawaited(PortraitThumbnails.configure(File('${directories.cache.path}${Platform.pathSeparator}portrait_thumbnails.json')));
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
        madePlayer = null;
        madeRelay = null;
        // Android draws into a surface of its own size; media_kit has no
        // output size there.
        _outputSize = Platform.isAndroid ? null : VideoOutputSize((width, height) async => videoController?.setSize(width: width, height: height), onError: (e) => logWarn('Could not size the video output: $e'));
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
      // What this attempt made goes, so a retry starts clean.
      if (madePlayer case final made?) {
        try {
          await made.dispose();
        } catch (error) {
          logWarn('Could not release the player of a failed start: $error');
        }
      }
      if (madeRelay case final made?) {
        if (identical(_relay, made)) _relay = null;
        unawaited(made.close());
      }
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
    if (_initializing != null) return;
    _update(() {
      error = null;
      status = tr('Reinstall components…');
    });
    unawaited(initialize());
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
    await _history?.flush();
    await downloads?.shutdown();
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
}
