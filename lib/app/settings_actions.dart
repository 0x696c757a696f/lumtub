part of 'app_controller.dart';

/// Preferences, player settings, API keys, blocking, tools and local data, as the settings pages change them.
extension SettingsActions on AppController {
  Future<void> savePreferences(AppPreferences next) async {
    final service = next.translation != preferences.translation;
    final gpu = next.gpuPreference != preferences.gpuPreference;
    _update(() => preferences = next);
    if (next.logLevel != AppLog.level) {
      AppLog.level = next.logLevel;
      logInfo('Log level ${next.logLevel.name}');
      // libmpv's own notes follow at once, not after a restart.
      if (player?.platform case final NativePlayer native) unawaited(native.requestLogMessages(next.logLevel == LogLevel.debug ? MPVLogLevel.info : MPVLogLevel.warn));
    }
    if (service) _useTranslator();
    unawaited(_aiFilter?.setMode(next.aiFilter));
    if (gpu) await _writeGpuPreference(next.gpuPreference);
    try {
      await _preferencesStore?.save(next);
    } on FileSystemException {
      _notice(tr("Couldn't save settings. They still apply for this session."));
    }
  }

  /// The Windows runner picks the graphics card before the engine starts,
  /// from `config\gpu.txt`; without the file Windows decides.
  Future<void> _writeGpuPreference(String value) async {
    final config = directories?.config;
    if (config == null || !Platform.isWindows) return;
    final file = File('${config.path}${Platform.pathSeparator}gpu.txt');
    try {
      if (value == 'system') {
        if (await file.exists()) await file.delete();
      } else {
        await config.create(recursive: true);
        await file.writeAsString(value);
      }
      logInfo('Graphics card preference $value, used from the next start');
    } on FileSystemException catch (e) {
      logError('Could not save the graphics card preference', e);
    }
  }

  Future<void> _loadTranslationKeys() async {
    final saved = await _translationKeyFile?.read();
    if (saved == null) return;
    final loaded = {for (final MapEntry(:key, :value) in saved.entries) if (value is String && value.isNotEmpty) key: value};
    // The single key older versions kept belongs to the host it is sent to now.
    translationKeys = migrateKeyHosts(preferences.translation, loaded);
    _useTranslator();
    _update(() {});
    if (translationKeys.length != loaded.length || !translationKeys.keys.every(loaded.containsKey)) {
      try {
        await _translationKeyFile?.write(translationKeys);
      } catch (e) {
        logError('Could not save the translation key', e);
      }
    }
  }

  void _useTranslator() {
    translator = CachingTranslator(translatorFor(preferences.translation, translationKeys, _http, fallback: _google), _translationCache, preferences.translation.cacheScope);
    logInfo('Translating with ${preferences.translation.service.name}');
  }

  /// Saves the API key of [service]; an empty one removes it.
  Future<void> saveTranslationKey(TranslationService service, String key) => saveApiKey(service.name, key);

  /// Saves the API key kept under [name] (a [TranslationService.name], or
  /// [aiKeyName] and [speechKeyName], which are kept per host); an empty one
  /// removes it.
  Future<void> saveApiKey(String name, String key) async {
    if (name.isEmpty) return;
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
      _notice(tr('The key could not be saved; it works until Lumtub closes.'));
    }
  }

  /// The models the chosen AI endpoint lists.
  Future<List<String>> listAiModels() {
    final config = preferences.translation;
    return AiTranslator.listModels(_http, config.effectiveAiBaseUrl, aiKeyFor(config, translationKeys));
  }

  /// A one-line answer from the AI interface, to check it works whichever
  /// service translates.
  Future<String> testAi() async {
    final ai = aiServiceFor(preferences.translation, translationKeys, _http);
    if (ai == null) throw TranslationException(tr('Fill in the AI interface address, model and key first'));
    final answer = await ai.complete('Answer in one short sentence.', 'Say hello and name the model you are.');
    return answer.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  }

  /// A short sentence put through the chosen service, to check it works.
  Future<String> testTranslation() => (translator is CachingTranslator ? (translator as CachingTranslator).inner : translator).translate('Subtitles and comments can be translated here.', preferences.translateTarget);

  void blockChannel(ChannelRef channel) {
    if (preferences.isBlocked(channel.id)) return;
    unawaited(savePreferences(preferences.copyWith(blockedChannels: [...preferences.blockedChannels, channel])));
    _notice(tr('Blocked "{0}". You can unblock it in Settings › Privacy', [channel.name.isEmpty ? channel.id : channel.name]));
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
    _notice(recommend ? tr('{0} can be recommended again', [name]) : tr("{0} won't be recommended any more; search and follows are unaffected", [name]));
  }

  void unblockChannel(String id) =>
      unawaited(savePreferences(preferences.copyWith(blockedChannels: preferences.blockedChannels.where((c) => c.id != id).toList())));

  void clearProgress() {
    library?.clearProgress();
    _notice(tr('Playback progress cleared.'));
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
    _notice(tr('Default settings restored.'));
  }

  Future<void> saveAppearance(AppearanceSettings next) async {
    AppController._applyAppearanceGlobals(next);
    if (next.systemAccent && windowsAccent == null) unawaited(refreshWindowsAccent());
    _update(() => appearance = next);
    // The text size slider saves at every step; only the last one is written.
    _appearanceSaveTimer?.cancel();
    _appearanceSaveTimer = Timer(const Duration(milliseconds: 500), () => unawaited(_writeAppearance()));
  }

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
      _notice(tr("Couldn't save appearance settings. They still apply for this session."));
    }
  }

  /// Goes back to the libmpv shipped with Lumtub from the next launch on.
  Future<void> rollBackLibmpv() async {
    await _tools?.libmpv.rollBack();
    _update(() {});
    _notice(tr('Reverted to the built-in libmpv. Restart Lumtub to apply.'));
  }

  Future<void> rollBackYtDlp() async {
    await _tools?.rollBackYtDlp();
    _update(() {});
    _notice(tr('Reverted to the previous yt-dlp. Restart Lumtub to apply.'));
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
    // What libmpv has: a slider preview changes [settings] only.
    final oldSettings = _applied ?? settings;
    final requiresNextVideo = next.hwdec != oldSettings.hwdec ||
        next.interpolation != oldSettings.interpolation ||
        next.d3d11vaZeroCopy != oldSettings.d3d11vaZeroCopy ||
        next.directRendering != oldSettings.directRendering;
    // Lighter scaling set for a busy GPU is not in the settings, so then
    // every option is set again.
    final ignoredOptions = await PlayerOptionApplicator.apply(player, next, previous: _lightRendering == null ? oldSettings : null);
    _applied = next;
    _lightRendering = null;
    if (this.player case final playing?) _refitCrop(playing);
    await store.save(next);
    _update(() => settings = next);
    if (next.skipSilence != oldSettings.skipSilence || next.audioFilter != oldSettings.audioFilter) unawaited(_syncSilenceSkipping(player));
    // The video playing skips by the new SponsorBlock choice too.
    if (next.sponsorBlock != oldSettings.sponsorBlock || !setEquals(next.sponsorCategories, oldSettings.sponsorCategories)) {
      _update(() => _segments = const []);
      final item = playing;
      if (next.sponsorBlock && item != null) unawaited(_loadSegments(item, _playSerial));
    }
    if (next.proxyMode != oldSettings.proxyMode ||
        next.proxyAddress != oldSettings.proxyAddress ||
        next.dnsServer != oldSettings.dnsServer ||
        next.dnsCustomUrl != oldSettings.dnsCustomUrl ||
        next.certificateRoots != oldSettings.certificateRoots ||
        next.postQuantum != oldSettings.postQuantum) {
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
          ? tr('Player settings saved{0}', [
              _zeroCopyDxva2(next.hwdec) != _zeroCopyDxva2(oldSettings.hwdec) && videoController != null
                  ? tr('; zero-copy DXVA2 takes effect after restarting Lumtub.')
                  : requiresNextVideo
                      ? tr('; decoding and frame interpolation changes take effect on the next video.')
                      : tr('.')
            ])
          : tr('Saved; not supported by this libmpv: {0}.', [ignoredOptions.join(', ')]);
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

  Future<void> openStore(String url) async {
    try {
      await Process.start('explorer.exe', [url]);
    } catch (_) {
      _notice(tr("Couldn't open the Microsoft Store link."));
    }
  }

  /// Moves the managed cache under [selectedFolder]. [confirmMigrate] asks
  /// whether existing cache folders should move with it.
  Future<void> changeCacheLocation(String selectedFolder, Future<bool?> Function(String targetPath) confirmMigrate) async {
    final manager = _cacheManager;
    if (directories == null || manager == null) return;
    final target = Directory('$selectedFolder${Platform.pathSeparator}LumtubCache');
    final next = settings.copyWith(cachePath: target.path);
    if (manager.nested(settings, next)) {
      _notice(tr("The new cache location can't be inside the current cache folders."));
      return;
    }
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
      _notice(tr("Cache location saved. yt-dlp's cache will use the new location on the next search."));
    } on FileSystemException catch (error) {
      _notice(tr('New cache location unavailable, still using the original: {0}', [error.message]));
    }
  }

  /// Clears the cache folders with no download starting meanwhile; while
  /// one runs, the folders it uses are kept.
  Future<({int freed, int skipped, bool keptForDownloads})> _clearCacheFolders(CacheManager manager) async {
    Future<({int freed, int skipped, bool keptForDownloads})> clear() async {
      final busy = downloads?.working ?? false;
      final (:freed, :skipped) = await manager.clear(settings, keep: busy ? CacheManager.downloadFolders : const {});
      return (freed: freed, skipped: skipped, keptForDownloads: busy);
    }

    return downloads?.holding(clear) ?? clear();
  }

  Future<void> clearCache() async {
    final manager = _cacheManager;
    if (manager == null) return;
    if (!ensureNotPlaying(tr("The cache can't be cleared during playback. Go back to the list first."))) return;
    try {
      await _translationCache.clear();
      final (:freed, :skipped, :keptForDownloads) = await _clearCacheFolders(manager);
      final left = await manager.size(settings);
      _update(() => cacheBytes = left);
      _notice(keptForDownloads
          ? tr("Cleared {0} of cache; yt-dlp's cache was kept while downloads are running.", [formatBytes(freed)])
          : skipped == 0
              ? tr('Cleared {0} of cache.', [formatBytes(freed)])
              : tr('Cleared {0} of cache; {1} files in use were left for next time.', [formatBytes(freed), skipped]));
    } on FileSystemException catch (error) {
      logError('Could not clear the cache', error);
      _notice(tr('Could not clear the cache: {0}', [error.message]));
    }
  }

  /// 清除本地数据: removes the chosen [kinds] from this computer. Favourites,
  /// playlists and followed channels are never touched here.
  Future<void> clearLocalData(Set<LocalData> kinds) async {
    if (kinds.contains(LocalData.cache) && !ensureNotPlaying(tr("The cache can't be cleared during playback. Go back to the list first."))) return;
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
            await _translationCache.clear();
            final manager = _cacheManager;
            if (manager != null) {
              await _clearCacheFolders(manager);
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
    _notice(tr('The chosen local data was cleared'));
  }
}
