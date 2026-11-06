part of 'app_controller.dart';

/// Subtitles, the subtitle list, chapter translation and speech recognition on the watch page.
extension SubtitleActions on AppController {
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
      logDebug(() => 'Showing ${second.language} (${second.kind.name}) as the second subtitle again');
      await setSecondarySubtitle(second);
    }
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
      logWarn('Could not reload the finished subtitle translation: $e');
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
      logWarn('Could not read the selected subtitle: $e');
    }
  }

  /// [option] as a local file, fetched with retries; see [SubtitleFiles].
  Future<String> _subtitleFile(SubtitleOption option) async {
    try {
      return await _subtitleFiles.pathFor(option);
    } catch (e) {
      logWarn('Could not fetch subtitles ${option.language}: $e');
      rethrow;
    }
  }

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
    // A second subtitle mpv shows that no option names is read as a track.
    final secondTrack = second != null || secondaryTrackId == 'no' ? null : player.state.tracks.subtitle.where((t) => t.id == secondaryTrackId).firstOrNull;
    Future<List<SubtitleCue>> secondCues() => second != null ? _optionCues(second) : secondTrack != null ? _trackCues(platform, secondTrack) : Future.value(const []);
    final hasSecond = second != null || secondTrack != null;
    final mode = preferences.subtitleListMode;
    // A translation on its own, as the first subtitle or as the second
    // with the first one off, is listed with the lines it was made from,
    // which stand first: on top, or alone with 只看第二字幕.
    Future<List<PairedCue>?> withOriginal(List<SubtitleCue> translation, SubtitleOption? original) async {
      if (original == null || mode == SubtitleListMode.first) return null;
      final from = await _optionCues(original);
      if (from.isEmpty) return null;
      return switch (mode) {
        SubtitleListMode.secondOver => pairSubtitleCues(translation, from),
        SubtitleListMode.second => pairSubtitleCues(from, const []),
        _ => pairSubtitleCues(from, translation),
      };
    }

    if (off && hasSecond) {
      final cues = await secondCues();
      return await withOriginal(cues, second == null ? null : _originalOf(second)) ?? pairSubtitleCues(cues, const []);
    }
    if (off) return const [];
    if (hasSecond && mode == SubtitleListMode.second) return pairSubtitleCues(await secondCues(), const []);
    final main = await _trackCues(platform, track);
    if (!hasSecond) {
      final listed = await withOriginal(main, listedOriginalOf(track));
      if (listed != null) return listed;
    }
    if (!hasSecond || mode == SubtitleListMode.first) return pairSubtitleCues(main, const []);
    return pairSubtitleCues(main, await secondCues());
  }

  /// [chapterTranslation] when it is the playing video's.
  List<String>? get translatedChapters => playing != null && chapterTranslationOf == playing!.id ? chapterTranslation : null;

  /// Translates the playing video's chapter titles into the language set
  /// for translations. Nothing is sent until asked.
  Future<void> translateChapters() async {
    final id = playing?.id;
    final chapters = details?.chapters ?? const [];
    if (id == null || chapters.isEmpty || translatingChapters) return;
    final language = preferences.translateTarget;
    _update(() => translatingChapters = true);
    chaptersChanged.value++;
    try {
      final titles = [for (final c in chapters) c.title.replaceAll('\n', ' ')];
      final lines = (await translateForeignLines(translator, titles.join('\n'), language, (line) => looksLike(line, language))).split('\n');
      if (playing?.id != id) return;
      _update(() {
        chapterTranslation = lines.length == titles.length ? lines : titles;
        chapterTranslationOf = id;
      });
    } on TranslationException catch (e) {
      _notice(e.message);
    } catch (e) {
      logWarn('Could not translate the chapters: $e');
      _notice(tr('Translation failed. Check your network or proxy.'));
    } finally {
      _update(() => translatingChapters = false);
      chaptersChanged.value++;
    }
  }

  /// The subtitle [track] was translated from, when it is a translation:
  /// the video's original-language one.
  SubtitleOption? listedOriginalOf(SubtitleTrack track) {
    final subtitles = details?.subtitles ?? const <SubtitleOption>[];
    final option = subtitles.where((o) => o.label == track.title).firstOrNull;
    return option == null ? null : _originalOf(option);
  }

  SubtitleOption? _originalOf(SubtitleOption option) {
    if (option.kind != SubtitleKind.translated) return null;
    return originalSubtitle(details?.subtitles ?? const [], language: details?.language);
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
      logWarn('Could not read the subtitle lines: $e');
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
      _notice(tr("Couldn't load these subtitles"));
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
    for (var i = 0; i < 6 && _openedDirect != item.id && !shown(player.state.track.subtitle); i++) {
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
    final original = originalSubtitle(details.subtitles, language: details.language);
    var spoken = settings.subtitleOriginal ? original : null;
    final wanted = settings.secondarySubtitleLanguage;
    final target = settings.secondaryTarget;
    final manualOnly = settings.subtitleMode == SubtitleMode.manual;
    // The second subtitle in the first one's language: the first one shows
    // the language the video is spoken in instead, and when that is the
    // same language too, it shows alone, as the first subtitle.
    var alike = wanted == PlayerSettings.originalSubtitle ? settings.subtitleOriginal : !settings.subtitleOriginal && target?.code == first.code;
    if (alike && target != null && wanted != PlayerSettings.originalSubtitle && original != null && !speaks(original.language, target)) {
      spoken = original;
      alike = false;
    }
    final mainPlanned = alike
        ? (wanted == PlayerSettings.originalSubtitle ? original : subtitleIn(details.subtitles, target!, language: details.language))
        : spoken ?? subtitleIn(details.subtitles, first, language: details.language);
    final secondPlanned = alike ? null : wanted == PlayerSettings.originalSubtitle ? original : target == null ? null : subtitleIn(details.subtitles, target, language: details.language);
    // Playback waits only for a subtitle to be translated; one the video
    // has in the language wanted loads while it plays.
    final translating = (mainPlanned?.kind == SubtitleKind.translated && !manualOnly) || secondPlanned?.kind == SubtitleKind.translated;
    if (!translating) _subtitlesSettled(serial);
    if (alike) {
      final only = mainPlanned;
      if (only != null && only.label != mainTitle && !(manualOnly && only.kind != SubtitleKind.uploaded)) {
        logDebug(() => 'Showing ${only.language} (${only.kind.name}) as the only subtitle');
        await showSubtitle(only);
      }
      return;
    }
    // 有人工字幕时开启 takes an uploaded subtitle only, as mpv's own pick
    // through ytdl_hook did.
    final manual = settings.subtitleMode == SubtitleMode.manual;
    final mainWanted = settings.subtitleMode == SubtitleMode.always || mainTitle != null || (manual && _openedDirect == item.id);
    if (mainWanted && (mainTitle == null || (spoken != null ? spoken.label != mainTitle && !sameLanguage(spoken.language, mainLanguage) : !speaks(mainLanguage, first)))) {
      final option = spoken ?? subtitleIn(details.subtitles, first, language: details.language);
      if (option != null && option.label != mainTitle && !(manual && mainTitle == null && option.kind != SubtitleKind.uploaded)) {
        logDebug(() => 'Showing ${option.language} (${option.kind.name}) as the main subtitle');
        await showSubtitle(option);
        if (serial != _playSerial || this.player != player) return;
        mainTitle = option.label;
        mainLanguage = option.language;
      }
    }
    final SubtitleOption? option;
    if (wanted == PlayerSettings.originalSubtitle) {
      option = originalSubtitle(details.subtitles, language: details.language);
      if (option == null || sameLanguage(option.language, mainLanguage)) return;
    } else {
      // A translation is of the first subtitle, so the two line up.
      final main = details.subtitles.where((o) => o.label == mainTitle).firstOrNull;
      option = target == null ? null : subtitleIn(details.subtitles, target, from: main, language: details.language);
      if (option == null || speaks(mainLanguage, target!)) {
        if (wanted.isNotEmpty) logWarn('No second subtitle in $wanted beside $mainLanguage');
        return;
      }
    }
    if (option.label == mainTitle || secondarySubtitle != null) return;
    final second = option;
    logDebug(() => 'Showing ${second.language} (${second.kind.name}) as the second subtitle');
    await setSecondarySubtitle(second);
  }

  void _subtitlesSettled(int serial) {
    if (serial == _subtitlesSerial && !_subtitlesReady.isCompleted) _subtitlesReady.complete();
  }

  /// Starts the video of [serial], opened paused, once its subtitles are
  /// ready or after [subtitleWait], unless it was played or another video
  /// opened meanwhile.
  Future<void> _playOnceSubtitlesReady(int serial) async {
    final player = this.player;
    if (player == null) return;
    var started = player.state.playing;
    final watch = player.stream.playing.listen((playing) => started = started || playing);
    final ready = _subtitlesReady;
    try {
      if (!ready.isCompleted) {
        logInfo('Waiting for the subtitle translation before playing');
        _update(() => waitingForSubtitles = true);
      }
      await ready.future.timeout(AppController.subtitleWait, onTimeout: () => logWarn('Subtitle translation not ready after ${AppController.subtitleWait.inSeconds} s; playing without it'));
    } finally {
      await watch.cancel();
      if (waitingForSubtitles) _update(() => waitingForSubtitles = false);
    }
    if (serial != _playSerial || this.player != player || started) return;
    await player.play();
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
    if (player != null) await PlayerOptionApplicator.apply(player, next, previous: _applied ?? settings);
    _applied = next;
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
      if (!await SecondarySubtitle.set(player, option, file: file)) throw StateError('Subtitles not loaded');
      _update(() => secondarySubtitle = option);
    } catch (e) {
      logError('Could not set secondary subtitles ${option?.language}', e);
      _notice(tr("Couldn't load these subtitles"));
    } finally {
      if (identical(secondaryLoading, option)) _update(() => secondaryLoading = null);
    }
  }

  /// Reads the subtitles mpv shows after the current mpv event is handled.
  void _followSubtitles(Player player) {
    if (_subtitlesFollowing) return;
    _subtitlesFollowing = true;
    unawaited(Future(() async {
      _subtitlesFollowing = false;
      if (!identical(player, this.player)) return;
      if (secondaryTrackId == 'no') {
        if (secondarySubtitle != null && secondaryLoading == null) _update(() => secondarySubtitle = null);
      } else {
        final title = player.state.tracks.subtitle.where((t) => t.id == secondaryTrackId).firstOrNull?.title;
        if (secondarySubtitle != null && secondarySubtitle!.label != title) secondarySubtitle = null;
      }
      await syncMainSubtitle();
      _update(() {});
    }));
  }

  /// Whether 语音识别 has its address, model and key.
  bool get canRecognizeSpeech => speechReady(preferences.translation, translationKeys);

  Future<SubtitleOption?> _speechOptionFor(String videoId, VideoDetails details) async {
    if (AppController.hasOwnSubtitles(details)) return null;
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
    if (item == null || details == null || repository == null || paths == null || store == null) throw TranslationException(tr('No video is playing'));
    if (speechJob.value != null) throw TranslationException(tr('Another video is being recognized, please wait'));
    final config = preferences.translation;
    if (!canRecognizeSpeech) throw TranslationException(tr('Set up the speech recognition service and key under Translation & AI first'));
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
      stage(tr('Downloading audio…'));
      List<SpeechPart> parts;
      try {
        parts = await fetch();
      } on SpeechNeedsFfmpeg {
        if (!withFfmpeg) {
          keepAudio = true;
          rethrow;
        }
        stage(tr('Installing ffmpeg…'));
        if (!await installFfmpeg()) throw TranslationException(tr('ffmpeg was not installed, so the audio cannot be split'));
        stage(tr('Downloading audio…'));
        parts = await fetch();
      }
      final hint = details.language?.split('-').first.toLowerCase();
      final answers = List<({Duration offset, Map<String, dynamic> answer})?>.filled(parts.length, null);
      var done = 0;
      var next = 0;
      stage(tr('Recognizing speech…'), 0, parts.length);
      // Two parts at a time: twice as fast without the burst a free tier
      // answers with 429.
      Future<void> worker() async {
        while (next < parts.length) {
          final i = next++;
          answers[i] = (offset: parts[i].offset, answer: await recognizer.transcribe(parts[i].file, language: hint));
          stage(tr('Recognizing speech…'), ++done, parts.length);
        }
      }

      await Future.wait([for (var i = 0; i < min(2, parts.length); i++) worker()]);
      final heard = [for (final a in answers) a!];
      final vtt = await speechVtt(heard);
      if (!vtt.contains('-->')) throw TranslationException(tr('No speech was recognized'));
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
      throw TranslationException(tr('Speech recognition failed: {0}', [e]));
    } finally {
      speechJob.value = null;
      try {
        if (!keepAudio && await folder.exists()) await folder.delete(recursive: true);
      } catch (_) {}
    }
  }
}
