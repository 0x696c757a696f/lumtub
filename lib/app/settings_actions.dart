part of 'app_controller.dart';

/// Preferences, player settings, API keys, blocking, tools and local data, as the settings pages change them.
extension SettingsActions on AppController {
  Future<void> savePreferences(AppPreferences next) async {
    final service = next.translation != preferences.translation;
    _update(() => preferences = next);
    if (next.logLevel != AppLog.level) {
      AppLog.level = next.logLevel;
      logInfo('Log level ${next.logLevel.name}');
    }
    if (service) _useTranslator();
    unawaited(_aiFilter?.setMode(next.aiFilter));
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
      _notice(tr('外观设置未能保存，本次运行仍然生效。'));
    }
  }

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
    // What libmpv has: a slider preview changes [settings] only.
    final oldSettings = _applied ?? settings;
    final requiresNextVideo = next.hwdec != oldSettings.hwdec ||
        next.interpolation != oldSettings.interpolation ||
        next.hwdecCodecs != oldSettings.hwdecCodecs ||
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
        next.certificateRoots != oldSettings.certificateRoots) {
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
                      ? tr('；解码和帧插值的改动在下一段视频生效。')
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
}
