part of 'app_controller.dart';

/// 精学: one stretch of a video studied in four steps (StudyStep), from
/// the subtitle list's lines. Ordinary watching is left as it was.
/// Whether 精学 may start for [controller]; set by the learning pack, which
/// owns the license. Unset, it always may.
bool Function(AppController controller)? studyUnlocked;

extension StudyActions on AppController {
  /// Whether 精学 may start now.
  bool get studyAllowed => studyUnlocked?.call(this) ?? true;

  StudyRun? get study => _studyRun;

  StudyStore? get studyStore => _studyStore;

  /// Where the playing video's study stopped, while it is not studied now.
  ({Duration unitStart, StudyStep step, DateTime at})? get studyResume {
    final item = playing;
    if (_studyRun != null || item == null || item.isLive) return null;
    return _studyStore?.of(item.id);
  }

  Future<StudyStore> _studyStoreReady() async {
    if (_studyStore case final store?) return store;
    final config = directories?.config ?? Directory.systemTemp;
    final store = StudyStore(File('${config.path}${Platform.pathSeparator}study.json'));
    await store.load();
    return _studyStore ??= store;
  }

  void _studyChanged() {
    if (!_disposed) studyChanged.value++;
  }

  /// Pauses after each line now: while reading, always; in the other steps
  /// never; outside a study as 每句说完暂停 says.
  bool get _pauseLinesNow {
    final run = _studyRun;
    if (run == null || run.done || run.rating) return settings.pauseEachLine;
    return run.step == StudyStep.read;
  }

  /// A new video: the study of the last one stops, and where this one's
  /// stopped is read.
  void _studyVideoChanged() {
    final run = _studyRun;
    if (run != null && run.videoId != playing?.id) {
      // The new video plays at its own speed.
      _studyRateBefore = null;
      _studyChannel = null;
      unawaited(stopStudy());
    }
    unawaited(_studyStoreReady().then((_) => _studyChanged()));
  }

  /// Starts studying the playing video, at the unit the position is in, or
  /// where it stopped last time with [resume]; from the first unit with
  /// [fromStart].
  Future<void> startStudy({bool resume = false, bool fromStart = false}) async {
    final player = this.player;
    final item = playing;
    if (player == null || item == null) return;
    if (item.isLive) {
      _notice(tr('Study mode works on videos, not live streams'));
      return;
    }
    if (!studyAllowed) {
      _notice(tr('Study mode is part of the learning pack'));
      return;
    }
    final store = await _studyStoreReady();
    var lines = learningLines;
    // Lines asked for just now come a moment later.
    for (var i = 0; lines.isEmpty && i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      lines = learningLines;
    }
    if (!identical(player, this.player) || playing?.id != item.id) return;
    if (lines.isEmpty) {
      _notice(tr('Turn on a subtitle first'));
      return;
    }
    final units = studyUnits(lines, breaks: [for (final c in details?.chapters ?? const <Chapter>[]) c.start], target: store.unitLength);
    final saved = resume ? store.of(item.id) : null;
    final from = fromStart ? Duration.zero : saved?.unitStart ?? player.state.position;
    final run = StudyRun(videoId: item.id, lines: lines, units: units, unit: unitAt(units, from));
    _studyRun = run;
    if (loopA != null || loopB != null) await clearLoop();
    logInfo('Study of ${item.id}: ${units.length} units, from unit ${run.unit + 1}');
    await _enterStudyStep(saved?.step ?? StudyStep.blind);
  }

  /// Leaves the study; where it stopped is kept.
  Future<void> stopStudy() async {
    if (_studyRun == null) return;
    _studyRun = null;
    _studyHide(false);
    await _studySlow(false);
    _studyChanged();
  }

  /// Forgets where the playing video's study stopped.
  Future<void> forgetStudyResume() async {
    final item = playing;
    final store = _studyStore;
    if (item == null || store == null) return;
    store.forget(item.id);
    _studyChanged();
    await store.save();
  }

  Future<void> _enterStudyStep(StudyStep step, {bool play = true}) async {
    final run = _studyRun;
    final player = this.player;
    if (run == null || player == null) return;
    run.enter(step);
    _studyHide(step == StudyStep.blind || step == StudyStep.relisten);
    await _studySlow(step == StudyStep.shadow);
    _studyChanged();
    _studySave();
    if (step == StudyStep.shadow) {
      if (play) await _playChunk();
      return;
    }
    final at = lineStart(run.lines[run.current.first]);
    _linePause.reset();
    await seek(at);
    run.seeked(to: at);
    if (play && !player.state.playing) await player.play();
  }

  void _studySave() {
    final run = _studyRun;
    final store = _studyStore;
    if (run == null || store == null || incognito) return;
    if (run.done && run.lastUnit) {
      store.forget(run.videoId);
    } else if (run.done) {
      store.remember(run.videoId, run.units[run.unit + 1].start, StudyStep.blind);
    } else {
      store.remember(run.videoId, run.current.start, run.step);
    }
    unawaited(store.save());
  }

  /// Hides the subtitles for 盲听 and 复听, or shows them again.
  void _studyHide(bool hide) {
    if (studyHidesSubtitles == hide) return;
    _update(() => studyHidesSubtitles = hide);
    subtitlesOffIn(_studyOwner, hide);
  }

  /// 跟读 plays slower; leaving it, the speed before comes back. A speed
  /// set here is not remembered for the channel.
  Future<void> _studySlow(bool slow) async {
    final player = this.player;
    if (player == null) return;
    if (slow) {
      if (_studyRateBefore == null) {
        _studyRateBefore = player.state.rate;
        _studyChannel = _playbackChannel;
        _playbackChannel = null;
      }
      final rate = _studyStore?.slowRate ?? 0.85;
      if (player.state.rate != rate) await player.setRate(rate);
      return;
    }
    final before = _studyRateBefore;
    if (before == null) return;
    _studyRateBefore = null;
    if (player.state.rate != before) await player.setRate(before);
    _playbackChannel ??= _studyChannel;
    _studyChannel = null;
  }

  /// Called with each position: moves the study on as a step's stretch
  /// ends.
  void _studyTick(Player player, Duration position) {
    final run = _studyRun;
    if (run == null) return;
    if (playing?.id != run.videoId) {
      _studyVideoChanged();
      return;
    }
    if (!player.state.playing) return;
    switch (run.observe(position, rate: player.state.rate)) {
      case StudyEvent.blindDone:
        unawaited(_enterStudyStep(StudyStep.read));
      case StudyEvent.readDone:
        unawaited(player.pause().then((_) => _enterStudyStep(StudyStep.shadow)));
      case StudyEvent.chunkDone:
        unawaited(player.pause());
      case StudyEvent.relistenDone:
        run.rating = true;
        unawaited(player.pause());
        _studyChanged();
      case null:
        break;
    }
  }

  /// 跟读: plays the part of the line shadowed now, from its start to the
  /// line's end.
  Future<void> _playChunk() async {
    final run = _studyRun;
    final player = this.player;
    final line = run?.shadowLine;
    if (run == null || player == null || line == null) return;
    final chunks = run.chunks;
    if (chunks.isEmpty) return;
    final at = chunkStart(run.lines[line], chunks[run.chunk.clamp(0, chunks.length - 1)]);
    _linePause.reset();
    await seek(at);
    run.seeked(to: at);
    if (!player.state.playing) await player.play();
  }

  /// 再听: the step's stretch again, or the line now while reading.
  Future<void> studyReplay() async {
    final run = _studyRun;
    if (run == null) return;
    switch (run.step) {
      case StudyStep.read:
        await stepLine(0);
      case StudyStep.shadow:
        await _playChunk();
      case StudyStep.blind || StudyStep.relisten:
        await _enterStudyStep(run.step);
    }
  }

  /// 盲听: shows the subtitles, for a stretch too hard to follow.
  void studyReveal() {
    final run = _studyRun;
    if (run == null || run.step != StudyStep.blind) return;
    run.revealed = true;
    _studyHide(false);
    _studyChanged();
  }

  /// Goes on to the next step; after the last, the unit is done unrated.
  Future<void> studySkip() async {
    final run = _studyRun;
    if (run == null) return;
    final next = run.step.index + 1;
    if (next < StudyStep.values.length) return _enterStudyStep(StudyStep.values[next]);
    await studyRate(null);
  }

  /// Goes to [step] of the unit now.
  Future<void> studyGoTo(StudyStep step) => _enterStudyStep(step);

  /// Marks the line now hard, or not.
  void studyToggleHard() {
    final run = _studyRun;
    final player = this.player;
    if (run == null || player == null) return;
    run.toggleHard(player.state.position);
    _studyChanged();
  }

  /// 跟读: a longer part of the line, up to the whole of it.
  Future<void> studyLonger() async {
    final run = _studyRun;
    if (run == null || run.step != StudyStep.shadow) return;
    if (run.chunk < run.chunks.length - 1) run.chunk++;
    _studyChanged();
    await _playChunk();
  }

  /// 跟读: the next hard line; after the last, 复听.
  Future<void> studyNextLine() async {
    final run = _studyRun;
    if (run == null || run.step != StudyStep.shadow) return;
    if (run.shadowAt + 1 >= run.shadowLines.length) return _enterStudyStep(StudyStep.relisten);
    run.shadowAt++;
    run.chunk = 0;
    _studyChanged();
    await _playChunk();
  }

  /// 复听: how much of the unit was understood, 30, 70 or 90 percent, or
  /// null when skipped. The unit is done.
  Future<void> studyRate(int? percent) async {
    final run = _studyRun;
    if (run == null) return;
    run.rating = false;
    run.done = true;
    run.rated = percent;
    if (percent != null) {
      run.ratings[run.unit] = percent;
      logInfo('Study of ${run.videoId}: unit ${run.unit + 1} understood about $percent%');
    }
    _studyHide(false);
    await _studySlow(false);
    _studySave();
    _studyChanged();
  }

  /// The next unit, from its first step.
  Future<void> studyNextUnit() async {
    final run = _studyRun;
    if (run == null || run.lastUnit) return;
    run.enterUnit(run.unit + 1);
    await _enterStudyStep(StudyStep.blind);
  }

  /// The length of a unit (60 to 180 s); a study going on is cut anew and
  /// starts the unit the position is in.
  Future<void> setStudyUnitLength(Duration length) async {
    final store = await _studyStoreReady();
    store.unitLength = length;
    unawaited(store.save());
    final run = _studyRun;
    final player = this.player;
    if (run == null || player == null) {
      _studyChanged();
      return;
    }
    final units = studyUnits(run.lines, breaks: [for (final c in details?.chapters ?? const <Chapter>[]) c.start], target: length);
    final at = run.current.start;
    _studyRun = StudyRun(videoId: run.videoId, lines: run.lines, units: units, unit: unitAt(units, at))
      ..replays.addAll(run.replays)
      ..marked.addAll(run.marked);
    await _enterStudyStep(StudyStep.blind, play: player.state.playing);
  }

  /// The speed 跟读 plays at.
  Future<void> setStudySlowRate(double rate) async {
    final store = await _studyStoreReady();
    store.slowRate = rate;
    unawaited(store.save());
    final player = this.player;
    if (_studyRun?.step == StudyStep.shadow && _studyRateBefore != null && player != null) await player.setRate(rate);
    _studyChanged();
  }
}
