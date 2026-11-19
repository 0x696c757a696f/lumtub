part of 'app_controller.dart';

/// 学外语: 每句说完暂停, 模糊翻译 and stepping line by line, on the lines
/// the subtitle list shows.
extension LearningActions on AppController {
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
    }).catchError((Object e) => logWarn('Could not read the subtitle lines to pause after: $e')));
  }

  /// Called with each position: pauses as a line ends while 每句说完暂停 is on.
  void _pauseAtLineEnd(Player player, Duration position) {
    if (!settings.pauseEachLine || playing?.isLive == true) {
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
}
