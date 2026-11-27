part of 'app_controller.dart';

/// Whether the switch to the computer's voice was told this run.
bool _edgeFallbackTold = false;

/// Whether hovering a subtitle line paused playback.
bool _hoverPaused = false;

/// Plays on a moment after the pointer leaves the line, so moving across
/// the gaps between its words does not stop and start the video.
Timer? _hoverResume;

/// 学外语: 每句说完暂停, 模糊翻译 and stepping line by line, on the lines
/// the subtitle list shows.
extension LearningActions on AppController {
  /// Whether the language-learning features are on (Settings ›
  /// Learning). Off, none of them shows, and the dictionaries, word
  /// cutting, license checks and updates do not run.
  bool get learningOn => preferences.learningMode;

  /// The mouse came onto ([over]) or left a subtitle line one can look
  /// words up in: playback pauses meanwhile, and plays on only when it
  /// was this that paused it.
  void hoverSubtitle(bool over) {
    final player = this.player;
    if (player == null || !learning.hoverPause || !learningOn) return;
    _hoverResume?.cancel();
    if (over) {
      if (_hoverPaused || !player.state.playing) return;
      _hoverPaused = true;
      unawaited(player.pause());
    } else if (_hoverPaused) {
      _hoverResume = Timer(const Duration(milliseconds: 350), () {
        if (!_hoverPaused || this.player != player) return;
        _hoverPaused = false;
        unawaited(player.play());
      });
    }
  }

  /// Whether hovering had paused playback, handing the resuming over to
  /// the caller (a word card opened from the line resumes when it closes).
  bool takeHoverPause() {
    _hoverResume?.cancel();
    final paused = _hoverPaused;
    _hoverPaused = false;
    return paused;
  }

  Future<void> setLearningMode(bool on) async {
    if (on == learningOn) return;
    await savePreferences(preferences.copyWith(learningMode: on));
    if (on) {
      final folders = directories;
      if (folders != null) unawaited(learning.start(folders));
    } else {
      learning.sleep();
      if (mode == PageMode.learning) navigate(PageMode.home);
    }
    logInfo('Learning mode ${on ? 'on' : 'off'}');
  }

  /// The lines playback pauses after and steps through: the subtitle
  /// list's rows, so a sentence split over several lines pauses once, at
  /// its end. Read again when the subtitles shown change.
  List<SubtitleCue> get learningLines {
    _refreshLearningLines();
    return _learningLines;
  }

  String get _learningKey {
    String source(String id) => _subtitleCopies[id]?.source ?? id;
    return [playing?.id, source(_mainTrackId), source(secondaryTrackId), secondarySubtitle?.label, _cueGeneration, preferences.subtitleListMode.name].join('|');
  }

  void _refreshLearningLines() {
    final key = _learningKey;
    // Lines not there yet (still being fetched) are asked for again now
    // and then.
    final retry = _learningLines.isEmpty && DateTime.now().difference(_learningLinesAsked) > const Duration(seconds: 5);
    if (key == _learningLinesKey && !retry) return;
    if (key != _learningLinesKey) {
      _learningLines = const [];
      _linePause.reset();
    }
    _learningLinesKey = key;
    _learningLinesAsked = DateTime.now();
    unawaited(listedSubtitleCues().then((rows) {
      if (_learningLinesKey != key) return;
      _learningLines = [for (final row in rows) row.cue];
      _rememberDifficulty(key);
    }).catchError((Object e) => logWarn('Could not read the subtitle lines to pause after: $e')));
  }

  /// Works out, a moment after the lines are read, how much of the video
  /// the learner knows, for its card in every list; the learning drawer
  /// reads the same counted result.
  void _rememberDifficulty(String key) {
    final id = playing?.id;
    final book = learning.book;
    if (id == null || book == null || !learningOn || !learning.unlocked || _learningLines.isEmpty || (playing?.isLive ?? false)) return;
    unawaited(Future<void>.delayed(const Duration(seconds: 4), () async {
      if (_learningLinesKey != key || playing?.id != id) return;
      final words = await videoWordsOf(learning, knownWordsOf(book), id, [for (final l in _learningLines) l.text]);
      if (words != null && words.words >= 20) videoDifficulty.remember(id, words.known);
      // The words being learnt that this video says, for "heard in N videos".
      final known = knownWordsOf(book);
      final heard = <String>{};
      for (final line in _learningLines) {
        for (final t in learning.wordsOf(line.text) ?? const <WordToken>[]) {
          if (t.isWord && known.learning(t)) heard.add(KnownWords.tokenKey(t));
        }
      }
      videoDifficulty.saw(id, heard);
    }).catchError((Object e) => logWarn('Could not work out the video difficulty: $e')));
  }

  /// Called with each position: pauses as a line ends while 每句说完暂停 is on.
  void _pauseAtLineEnd(Player player, Duration position) {
    _studyTick(player, position);
    if (!_pauseLinesNow || (playing?.isLive ?? false)) {
      _linePause.reset();
      return;
    }
    // A line looping plays again rather than stopping.
    if (!player.state.playing || loopB != null) {
      _linePause.reset();
      return;
    }
    if (_linePause.observe(learningLines, position, rate: player.state.rate)) {
      logDebug(() => 'Paused at the end of a subtitle line at $position');
      unawaited(player.pause());
    }
  }

  /// Turns 每句说完暂停 on or off; true when it is on now.
  Future<bool> togglePauseEachLine() async {
    final on = !settings.pauseEachLine;
    await saveSettings(settings.copyWith(pauseEachLine: on));
    return on;
  }

  /// Plays the line before (-1), this one again (0) or the next (1), from
  /// its start. Without lines to read (a format other than WebVTT or SRT),
  /// libmpv steps by the main subtitle. False when there is nothing to go to.
  Future<bool> stepLine(int skip) async {
    final player = this.player;
    if (player == null) return false;
    final lines = learningLines;
    final index = lineToStep(lines, player.state.position, skip);
    if (index != null) {
      _linePause.reset();
      // A loop going on moves to that line.
      if (loopB != null) {
        await _loopLine(lines[index]);
        if (!player.state.playing) await player.play();
        return true;
      }
      await seek(lineStart(lines[index]));
      if (!player.state.playing) await player.play();
      return true;
    }
    final platform = player.platform;
    if (lines.isNotEmpty || platform is! NativePlayer || player.state.track.subtitle.id == 'no') return false;
    try {
      await platform.command(['sub-seek', '$skip']);
      if (!player.state.playing) await player.play();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 单句循环: plays the line now over and over, as an A-B loop; another
  /// press, or any A-B loop already on, stops it. True when a line loops
  /// now, false when the loop stopped, null when there is no line.
  Future<bool?> toggleLineLoop() async {
    final player = this.player;
    if (player == null) return null;
    if (loopA != null || loopB != null) {
      await clearLoop();
      return false;
    }
    final lines = learningLines;
    final index = lineToStep(lines, player.state.position, 0);
    if (index == null) return null;
    await _loopLine(lines[index]);
    if (!player.state.playing) await player.play();
    return true;
  }

  /// Reads [text] in [language] aloud in the voice the learning pack's
  /// settings name. [problem] is null when it plays, else what went wrong;
  /// [note] says, once a run, that Edge's voices failed and the computer's
  /// voice read it instead.
  Future<({String? problem, String? note})> sayAloud(String text, String language) async {
    language = WordVoice.variantOf(language, [player?.state.track.subtitle.language, secondarySubtitle?.language]);
    final voice = learning.voice;
    if (voice == null) return (problem: tr('Not ready yet'), note: null);
    final service = learning.voiceService;
    File? file;
    Object? failure;
    String? note;
    try {
      file = await voice.read(text, language, service, translationKeys);
    } catch (e) {
      failure = e;
      logWarn('Could not read "$text" ($language) aloud with ${service.name}: $e');
    }
    // Edge's voices refused or out of reach: Lumtub's server when it has a
    // key, else the computer's own voice, said once.
    if (file == null && service == VoiceService.edge) {
      final edgeFailure = failure;
      // A language Edge has no voice for goes straight to the computer's.
      final unsupported = edgeFailure is VoiceException && edgeFailure.noVoice;
      if (!unsupported) {
        try {
          file = await voice.read(text, language, VoiceService.lumtub, translationKeys, server: learning.speechServer);
          failure = null;
        } catch (e) {
          logInfo('Lumtub\'s server did not read "$text" either: $e');
        }
      }
      if (file == null) {
        try {
          file = await voice.read(text, language, VoiceService.system, translationKeys);
          failure = null;
          if (!unsupported && !_edgeFallbackTold) {
            _edgeFallbackTold = true;
            final why = edgeFailure is VoiceException ? edgeFailure.detail : '$edgeFailure';
            note = tr("Edge's online voices can't be reached right now ({0}), so this computer's voice read it.", [why]);
          }
        } catch (e) {
          failure = e;
          logWarn('Could not read "$text" ($language) aloud with the system voice either: $e');
        }
      }
    }
    if (file == null) {
      final e = failure;
      if (e is VoiceException && e.noVoice && (service == VoiceService.system || service == VoiceService.edge)) {
        return (problem: tr('This computer has no voice for this language. Add one in the system settings, or pick an online voice in the learning pack settings.'), note: null);
      }
      if (e is VoiceException && e.noVoice) return (problem: tr('This voice service has no voice for this language'), note: null);
      return (problem: tr('Could not read it aloud: {0}', [e is VoiceException ? e.detail : '$e']), note: null);
    }
    try {
      final size = await file.length();
      if (size < 100) {
        await file.delete();
        logWarn('Reading "$text" ($language) aloud gave an empty sound ($size bytes)');
        return (problem: tr('Could not read it aloud: {0}', [tr('the voice gave no sound')]), note: null);
      }
      final player = this.player;
      if (player != null && player.state.playing) await player.pause();
      final sound = _shadowPlayer ??= Player();
      await sound.setVolume((player?.state.volume ?? 100).clamp(30, 100).toDouble());
      // Told when mpv cannot play it, rather than staying silent.
      final failed = Completer<String>();
      final watch = sound.stream.error.listen((message) {
        if (!failed.isCompleted) failed.complete(message);
      });
      final String problem;
      try {
        await sound.open(Media(file.uri.toString()));
        problem = await failed.future.timeout(const Duration(milliseconds: 800), onTimeout: () => '');
      } finally {
        await watch.cancel();
      }
      logInfo('Read "$text" ($language) aloud: $size bytes${problem.isEmpty ? '' : ', mpv: $problem'}');
      if (problem.isNotEmpty) {
        await file.delete();
        return (problem: tr('Could not read it aloud: {0}', [problem]), note: null);
      }
      return (problem: null, note: note);
    } catch (e) {
      logWarn('Could not play the sound for "$text" ($language): $e');
      return (problem: tr('Could not read it aloud: {0}', ['$e']), note: null);
    }
  }

  /// Plays the sound file [file] (a vocabulary word's line) on its own,
  /// pausing the video. False when it could not.
  Future<bool> playSoundFile(File file) async {
    try {
      if (!await file.exists()) return false;
      final player = this.player;
      if (player != null && player.state.playing) await player.pause();
      final sound = _shadowPlayer ??= Player();
      await sound.setVolume(player?.state.volume ?? 100);
      await sound.open(Media(file.uri.toString()));
      return true;
    } catch (e) {
      logWarn('Could not play ${file.path}: $e');
      return false;
    }
  }

  /// The last of [lines] (in order of start) said around [at], within
  /// [slack]: found by its start, then it or the line before it, as lines
  /// overlap at most their neighbour.
  static SubtitleCue? _lineAround(List<SubtitleCue> lines, Duration at, Duration slack) {
    final last = cueIndexAt(lines, at + slack);
    for (var i = last; i >= 0 && i >= last - 1; i--) {
      if (at <= lines[i].end + slack) return lines[i];
    }
    return null;
  }

  /// Stops waiting for a line played once to end: playback moved on.
  void _cancelLineOnce() {
    final once = _lineOnce;
    _lineOnce = null;
    if (once != null) unawaited(once.cancel());
  }

  /// Plays the line said at [at] once and pauses as it ends: 听原句 on a
  /// word card. False when no line is there.
  Future<bool> playLineOnce(Duration at) async {
    final player = this.player;
    if (player == null) return false;
    const slack = Duration(milliseconds: 300);
    final line = _lineAround(learningLines, at, slack);
    if (line == null) return false;
    await _lineOnce?.cancel();
    await seek(lineStart(line));
    if (this.player != player) return false;
    late final StreamSubscription<Duration> once;
    // Positions from before the seek landed say nothing about this line.
    var inLine = false;
    final from = lineStart(line) - const Duration(seconds: 1);
    once = _lineOnce = player.stream.position.listen((position) {
      if (!inLine) {
        if (position < from || position >= line.end) return;
        inLine = true;
      }
      if (position < line.end) return;
      if (identical(_lineOnce, once)) _lineOnce = null;
      unawaited(once.cancel());
      // Moved well past the line by other means: nothing to stop.
      if (position <= line.end + const Duration(seconds: 2)) unawaited(player.pause());
    });
    await player.play();
    return true;
  }

  Future<void> _loopLine(SubtitleCue line) async {
    _update(() {
      loopA = lineStart(line);
      loopB = line.end;
    });
    await _applyLoop();
    await seek(loopA!);
  }

  /// Whether the second subtitle is blurred now: 模糊翻译 is on, it has not
  /// been asked to show, and there is one.
  bool get secondBlurred => settings.blurSecondary && !translationShown.value && secondaryTrackId != 'no';

  /// The pointer is over the second subtitle, or left it.
  void hoverTranslation(bool over) {
    if (_reveal.hover(over)) _revealChanged();
  }

  /// A tap or key shows the blurred second subtitle until the next line,
  /// or hides it again.
  void toggleTranslation() {
    final lines = player?.state.subtitle ?? const <String>[];
    if (_reveal.toggle(lines.length > 1 ? lines[1] : '')) _revealChanged();
  }

  /// Turns 模糊翻译 on or off.
  Future<void> setBlurSecondary(bool on) async {
    if (_reveal.reset()) translationShown.value = false;
    await saveSettings(settings.copyWith(blurSecondary: on));
  }

  void _secondLineChanged(List<String> lines) {
    if (_reveal.lineChanged(lines.length > 1 ? lines[1] : '')) _revealChanged();
  }

  void _forgetReveal() {
    if (_reveal.reset()) _revealChanged();
  }

  void _revealChanged() {
    translationShown.value = _reveal.shown;
    // libmpv shows the second subtitle's blurred or plain copy.
    if (settings.blurSecondary && libassDraws && player != null) _restyleSubtitles(player!);
  }

  /// Whether there is a take to compare with the original line.
  bool get hasShadowTake => _shadowing?.last != null;

  /// How many lines have a take.
  int get shadowTakeCount => _shadowing?.takes.length ?? 0;

  /// Whether [line] has a take, for the subtitle list.
  bool hasTakeOf(SubtitleCue line) => _shadowing?.takes.containsKey(line.start) ?? false;

  /// 跟读录音: starts recording the person saying the line now, with the
  /// video paused; pressed again, stops and plays the line, then the take.
  /// While those play, stops them.
  Future<void> toggleShadowing() async {
    switch (shadowStage.value) {
      case ShadowStage.recording:
        return _stopShadowing();
      case ShadowStage.original || ShadowStage.mine:
        return _stopComparing();
      case ShadowStage.idle:
        break;
    }
    final player = this.player;
    if (player == null) return;
    final lines = learningLines;
    final index = lineToStep(lines, player.state.position, 0);
    if (index == null) {
      _notice(tr('Turn on a subtitle first'));
      return;
    }
    if (player.state.playing) await player.pause();
    final folder = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}Lumtub shadowing');
    final shadowing = _shadowing ??= Shadowing(folder, microphone: CoreMicrophone(mixWithOthers: settings.mixWithOthers));
    try {
      await shadowing.start(onTooLong: () => unawaited(_stopShadowing()));
    } on ShadowException catch (e) {
      logWarn('Could not record: $e');
      _notice(e.denied ? tr("Lumtub can't use the microphone. Allow it in the system settings.") : tr('Could not start recording: {0}', [e.detail]));
      return;
    }
    _shadowLine = lines[index];
    shadowStage.value = ShadowStage.recording;
  }

  Future<void> _stopShadowing() async {
    if (shadowStage.value != ShadowStage.recording) return;
    final line = _shadowLine;
    ShadowTake? take;
    try {
      if (line != null) take = await _shadowing?.stop(line);
    } catch (e) {
      logWarn('Could not save the recording: $e');
    }
    shadowStage.value = ShadowStage.idle;
    // libmpv opens its audio output again in the session iOS has back.
    final platform = player?.platform;
    if (Platform.isIOS && platform is NativePlayer) {
      await platform.command(['ao-reload']).catchError((Object e) => logDebug(() => 'Could not reopen the audio output: $e'));
    }
    if (take == null) {
      _notice(tr('Nothing was recorded. Check the microphone.'));
      return;
    }
    shadowTakes.value++;
    // The line was just played, so the video's cache still holds it.
    if (take.original == null) unawaited(_keepOriginal(take));
    await compareShadowing();
  }

  /// Plays [line] (the line recorded last when null), then its take.
  Future<void> compareShadowing([SubtitleCue? line]) async {
    final player = this.player;
    final take = line == null ? _shadowing?.last : _shadowing?.takes[line.start];
    if (player == null || take == null || shadowStage.value == ShadowStage.recording) return;
    line = take.line;
    final serial = ++_shadowSerial;
    bool current() => serial == _shadowSerial && identical(player, this.player);
    if (shadowStage.value != ShadowStage.idle) await _shadowPlayer?.stop();
    shadowStage.value = ShadowStage.original;
    try {
      _linePause.reset();
      await seek(lineStart(line));
      await player.play();
      final end = LinePause.pauseAt(line, rate: player.state.rate);
      final deadline = DateTime.now().add((line.end - line.start) * (2 / player.state.rate.clamp(0.25, 4.0)) + const Duration(seconds: 3));
      while (current() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        if (player.state.position >= end || !player.state.playing && player.state.position > line.start) break;
      }
      if (!current()) return;
      if (player.state.playing) await player.pause();
      shadowStage.value = ShadowStage.mine;
      final mine = _shadowPlayer ??= Player();
      await mine.setVolume(player.state.volume);
      await mine.open(Media(take.file.uri.toString()));
      await mine.stream.completed.firstWhere((done) => done).timeout(take.length + const Duration(seconds: 2), onTimeout: () => true);
    } catch (e) {
      logWarn('Could not play the recording back: $e');
    } finally {
      if (serial == _shadowSerial) shadowStage.value = ShadowStage.idle;
    }
  }

  /// Reads the line [take] is of out of the video's cache, as the video
  /// says it, for saving the two together. libmpv writes the cached
  /// packets around the line to a file (from the keyframe before it, so
  /// only its end is exact) and a second, silent libmpv decodes their
  /// sound to WAV as fast as it can; the core keeps the end that is the
  /// line. False when the cache no longer holds it.
  Future<bool> _keepOriginal(ShadowTake take) async {
    final shadowing = _shadowing;
    if (shadowing == null) return false;
    final line = take.line;
    final sound = shadowing.fileFor(line, 'line', 'wav');
    final seconds = await _cutLine(line, shadowing.folder, shadowing.fileFor(line, 'video', 'mkv'), sound);
    if (seconds == null) return false;
    take.original = sound;
    take.originalSeconds = seconds;
    return true;
  }

  /// Decodes [line]'s sound out of the video's cache into the WAV file
  /// [sound]: libmpv writes the cached packets around it to [packets]
  /// (from the keyframe before it, so only the end is exact) and a
  /// second, silent libmpv decodes them as fast as it can. The seconds
  /// at the file's end that are the line, or null when the cache no
  /// longer holds it.
  Future<double?> _cutLine(SubtitleCue line, Directory folder, File packets, File sound, {int? sampleRate}) async {
    final player = this.player;
    final platform = player?.platform;
    if (player == null || platform is! NativePlayer || (playing?.isLive ?? false)) return null;
    final from = line.start - const Duration(milliseconds: 150);
    final start = (from < Duration.zero ? 0 : from.inMilliseconds) / 1000;
    final end = (line.end + const Duration(milliseconds: 250)).inMilliseconds / 1000;
    Player? decoder;
    try {
      final cache = jsonDecode(await platform.getProperty('demuxer-cache-state'));
      final ranges = cache is Map ? cache['seekable-ranges'] : null;
      final held = ranges is List && ranges.any((r) => r is Map && r['start'] is num && r['end'] is num && (r['start'] as num) <= start && (r['end'] as num) >= end);
      if (!held) {
        logDebug(() => 'The line at ${line.start} is no longer in the cache');
        return null;
      }
      await folder.create(recursive: true);
      await platform.command(['dump-cache', '$start', '$end', packets.path]);
      if (!await packets.exists() || await packets.length() == 0) return null;
      decoder = Player(configuration: const PlayerConfiguration(title: 'Lumtub line'));
      final silent = decoder.platform;
      if (silent is! NativePlayer) return null;
      for (final (name, value) in [
        ('vid', 'no'),
        ('sid', 'no'),
        ('ao', 'pcm'),
        ('ao-pcm-file', sound.path),
        ('ao-pcm-waveheader', 'yes'),
        ('audio-format', 's16'),
        ('audio-channels', 'mono'),
        if (sampleRate != null) ('audio-samplerate', '$sampleRate'),
        ('untimed', 'yes'),
        ('volume', '100'),
      ]) {
        await silent.setProperty(name, value);
      }
      await decoder.open(Media(packets.uri.toString()));
      await decoder.stream.completed.firstWhere((done) => done).timeout(const Duration(seconds: 20));
      await decoder.dispose();
      decoder = null;
      if (!await sound.exists() || await sound.length() <= 44) return null;
      return end - start;
    } catch (e) {
      logWarn('Could not read the line out of the cache: $e');
      return null;
    } finally {
      await decoder?.dispose();
      if (await packets.exists()) await packets.delete().catchError((Object _) => packets);
    }
  }

  /// Keeps the line said at [at] as the sound of the vocabulary word
  /// [key], for Anki. Nothing when the cache no longer holds it.
  Future<void> keepWordSound(String key, Duration at) async {
    final book = learning.book;
    if (book == null) return;
    const slack = Duration(milliseconds: 300);
    final line = _lineAround(learningLines, at, slack);
    if (line == null) return;
    final sound = book.soundOf(key);
    final whole = File('${sound.path}.part');
    final seconds = await _cutLine(line, sound.parent, File('${sound.path}.mkv'), whole, sampleRate: 22050);
    if (seconds == null) return;
    try {
      await whole.writeAsBytes(wavTail(await whole.readAsBytes(), seconds), flush: true);
      await whole.rename(sound.path);
      logDebug(() => 'Kept the line of $key for Anki');
    } catch (e) {
      logWarn('Could not keep the line of $key: $e');
      if (await whole.exists()) await whole.delete().catchError((Object _) => whole);
    }
  }

  /// Saves takes as one WAV file where the person picks ([ShadowExport]);
  /// false when they cancelled or there is nothing to save.
  Future<bool> saveShadowTake(ShadowExport what) async {
    final shadowing = _shadowing;
    final last = shadowing?.last;
    if (shadowing == null || last == null) return false;
    final takes = what == ShadowExport.all ? shadowing.inOrder : [last];
    final at = last.line.start.inSeconds;
    final id = playing?.id ?? 'video';
    final name = switch (what) {
      ShadowExport.mine => 'lumtub-shadowing-$id-${at ~/ 60}m${(at % 60).toString().padLeft(2, '0')}s.wav',
      ShadowExport.withLine => 'lumtub-shadowing-$id-${at ~/ 60}m${(at % 60).toString().padLeft(2, '0')}s-with-line.wav',
      ShadowExport.all => 'lumtub-shadowing-$id-${takes.length}-lines.wav',
    };
    try {
      final Uint8List bytes;
      if (what == ShadowExport.mine) {
        bytes = await last.file.readAsBytes();
      } else {
        for (final take in takes) {
          if (take.original == null) await _keepOriginal(take);
        }
        if (takes.any((take) => take.original == null)) {
          _notice(what == ShadowExport.withLine ? tr('The line is no longer buffered. Play it once more, then save.') : tr('Some lines are no longer buffered, so only your recording is saved for them.'));
          if (what == ShadowExport.withLine) return false;
        }
        final out = shadowing.fileFor(last.line, 'export', 'wav').path;
        final parts = [for (final take in takes) take.part];
        final joined = await Isolate.run(() => NativeCore.micJoin(parts, out));
        if (joined.error != null) throw StateError(joined.error!);
        bytes = await File(out).readAsBytes();
        await File(out).delete();
      }
      if (!await saveFileAs(name, bytes, mime: 'audio/wav', label: 'WAV', extension: 'wav')) return false;
      _notice(tr('Recording saved'));
      return true;
    } catch (e) {
      logWarn('Could not save the recording: $e');
      _notice(tr('Export failed: {0}', [friendlyFileError(e)]));
      return false;
    }
  }

  Future<void> _stopComparing() async {
    _shadowSerial++;
    shadowStage.value = ShadowStage.idle;
    await _shadowPlayer?.stop();
    final player = this.player;
    if (player != null && player.state.playing) await player.pause();
  }

  /// A new video or closing: the take and the microphone go.
  Future<void> _forgetShadowing() async {
    _shadowSerial++;
    final shadowing = _shadowing, mine = _shadowPlayer;
    _shadowing = null;
    _shadowPlayer = null;
    _shadowLine = null;
    if (!_disposed) {
      shadowStage.value = ShadowStage.idle;
      shadowTakes.value++;
    }
    try {
      await shadowing?.dispose();
      await mine?.dispose();
    } catch (e) {
      logDebug(() => 'Could not let go of the recording: $e');
    }
  }
}
