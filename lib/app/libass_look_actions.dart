part of 'app_controller.dart';

/// Subtitles drawn by libmpv look as the Flutter subtitle view draws them
/// in the same player: one set of settings, whoever draws. The letter size,
/// room below and outline follow the player's size; the second subtitle
/// gets its own font, color and opacity from a styled copy of its track.
/// Ends the key of a second subtitle copied only for the lines around now.
const _quickMark = '|quick';

extension LibassLookActions on AppController {
  /// The player showing subtitles was laid out at [view], where the Flutter
  /// view scales text by [textScale] and its padding by [paddingScale].
  void subtitleViewChanged(Size view, double textScale, double paddingScale) {
    final last = _subtitleView;
    if (last != null && (last.view.width - view.width).abs() < 2 && (last.view.height - view.height).abs() < 2 && last.textScale == textScale && last.paddingScale == paddingScale) return;
    _subtitleView = (view: view, textScale: textScale, paddingScale: paddingScale);
    _queueLibassLook();
  }

  /// [owner] shows the video with subtitles left out ([off]) or not.
  void subtitlesOffIn(Object owner, bool off) {
    final was = subtitlesOff;
    off ? _subtitlesOffIn.add(owner) : _subtitlesOffIn.remove(owner);
    if (was != subtitlesOff) _showLibassSubtitles();
  }

  /// Shows or hides what libmpv draws as [subtitlesOff] says, when it draws.
  void _showLibassSubtitles() {
    final platform = player?.platform;
    if (platform is! NativePlayer || !libassDraws) return;
    final value = subtitlesOff ? 'no' : 'yes';
    for (final name in ['sub-visibility', 'secondary-sub-visibility']) {
      unawaited(platform.setProperty(name, value).catchError((Object e) => logDebug(() => 'Could not set $name: $e')));
    }
  }

  /// Options were set from the settings alone: the look for the player's
  /// size goes back at once, and the copies are checked against them.
  void _optionsApplied(Player player) {
    _syncSubtitleCanvas();
    _libassSent = {};
    unawaited(_applyLibassLook());
    final platform = player.platform;
    // Android found no font for this video's script: the Flutter view draws.
    if (libassCantDraw && platform is NativePlayer) {
      for (final name in ['sub-visibility', 'secondary-sub-visibility']) {
        unawaited(platform.setProperty(name, 'no').catchError((Object e) => logDebug(() => 'Could not hide $name: $e')));
      }
    }
    if (subtitlesOff) _showLibassSubtitles();
    _restyleSubtitles(player);
  }

  /// The look for the player now: its laid-out size when known.
  LibassLook get _libassLook {
    final view = _subtitleView;
    if (view == null) return LibassLook.standard(position: settings.subtitlePosition, border: settings.subtitleBorder, byHeight: Platform.isAndroid || Platform.isIOS, caption: Device.captionScale);
    return LibassLook.of(view: view.view, aspect: _canvasAspect, textScale: view.textScale, paddingScale: view.paddingScale, position: settings.subtitlePosition, border: settings.subtitleBorder);
  }

  double get _videoAspect {
    final w = player?.state.width ?? 0, h = player?.state.height ?? 0;
    return w > 0 && h > 0 ? w / h : 16 / 9;
  }

  /// The shape libmpv draws subtitles in: the whole player where the
  /// picture is fitted into it with bars, so lines can run into the bars
  /// beside a portrait picture as in the Flutter view, else the picture.
  /// On iOS the player's layer fills a fitted player (not while picture in
  /// picture, where the frames carry the subtitles); elsewhere the drawing
  /// takes the player's shape while libmpv draws subtitles.
  double get _canvasAspect {
    final view = _subtitleView?.view;
    final whole = Platform.isIOS ? !_coverVideo && !IosVideoLayer.active.value : _outputSize?.canvasShaped ?? false;
    if (!whole || view == null || view.isEmpty) return _videoAspect;
    return view.width / view.height;
  }

  /// The drawing takes the player's shape while libmpv draws subtitles on
  /// a desktop.
  void _syncSubtitleCanvas() {
    final output = _outputSize;
    if (output != null) {
      output.canvas = !Platform.isIOS && libassDraws;
      pictureShapedByPlayer.value = output.canvasShaped;
    }
    _queueLibassLook();
  }

  /// Sends the look once resizing settles: a window dragged wider lays the
  /// player out every frame.
  void _queueLibassLook({bool again = false}) {
    if (again) _libassSent = {};
    _libassLookTimer?.cancel();
    if (!settings.libassSubtitles || player?.platform is! NativePlayer) return;
    _libassLookTimer = Timer(const Duration(milliseconds: 120), () => unawaited(_applyLibassLook()));
  }

  /// Sends libmpv the subtitle options that changed for the player's size,
  /// then remakes the copies whose wrapping or outline it changed.
  Future<void> _applyLibassLook() async {
    final player = this.player;
    final platform = player?.platform;
    if (player == null || platform is! NativePlayer || !settings.libassSubtitles) return;
    final look = _libassLook;
    final options = PlayerOptionApplicator.libassOptions(settings, look)
      // Placed with the main subtitle's lines below.
      ..remove('secondary-sub-pos');
    // Above the player's controls while they show.
    options['sub-pos'] = '${(100 - _subtitleLift).clamp(0, 100)}';
    // The font that draws this video's script on Android and iOS, or the
    // subtitle language's forms on a desktop, at its own size.
    if (_drawnFamily case final family?) {
      options['sub-font'] = family;
      options['sub-font-size'] = look.fontSize(family).toStringAsFixed(1);
    }
    if (_secondScaleMissing) {
      options.remove('secondary-sub-scale');
    } else if (_subtitleCopies[secondaryTrackId]?.second ?? false) {
      options['secondary-sub-scale'] = (look.em / secondEm).toStringAsFixed(3);
    }
    for (final MapEntry(:key, :value) in options.entries) {
      if (_libassSent[key] == value) continue;
      try {
        await platform.setProperty(key, value);
        _libassSent[key] = value;
      } catch (e) {
        logDebug(() => 'Could not set $key: $e');
      }
    }
    if (!identical(player, this.player)) return;
    _placeSecondary(player, _mainSubtitle);
    _restyleSubtitles(player);
  }

  /// The room a line has, in letters: copies are wrapped to it.
  int _roomEms(double scale) => LibassLayout.roomEms(em: _libassLook.em, scale: scale, aspect: _canvasAspect).floor();

  /// What the copy of the main subtitle depends on: where it wraps.
  String get _mainCopyKey => 'main|${_roomEms(settings.subtitleScale)}|${linuxScriptFamilies.keys.join('+')}';

  /// What the styled copy of a second subtitle depends on.
  String get _secondCopyKey => _secondCopyKeyFor(secondBlurred);

  /// [_secondCopyKey] for the copy blurred by 模糊翻译 or the plain one.
  String _secondCopyKeyFor(bool blurred) {
    final look = _libassLook;
    return [
      'second',
      if (blurred) 'blurred',
      // The downloaded script fonts its stretches name (Linux).
      linuxScriptFamilies.keys.join('+'),
      _roomEms(settings.secondaryScale),
      settings.secondaryFont,
      settings.secondaryScale,
      settings.secondaryColor,
      settings.secondaryOpacity,
      settings.subtitleBold,
      settings.subtitleBackground,
      // The main subtitle's lines it holds, invisible, and their size.
      _mainSource,
      settings.subtitleScale,
      _mainFont,
      _roomEms(settings.subtitleScale),
      _videoAspect.toStringAsFixed(2),
      // The outline is in the copy's letters, which follow the player's size.
      (look.em > 0 ? look.border / look.em * 100 : 0).round(),
      // Its letters' size where libmpv cannot scale it.
      if (_secondScaleMissing) (_secondCopyScale * 100).round(),
    ].join('|');
  }

  /// How much bigger than [secondEm] the copy's letters are drawn without
  /// secondary-sub-scale: mpv older than 0.42 scales an ASS second
  /// subtitle by the main one's sub-scale instead.
  double get _secondCopyScale => _secondScaleMissing ? _libassLook.em / secondEm / max(settings.subtitleScale, 0.01) : 1;

  /// Asks [player]'s libmpv once whether it has secondary-sub-scale.
  Future<void> _askSecondScale(Player player, NativePlayer platform) async {
    if (identical(_secondScaleAsked, player)) return;
    final missing = (await platform.getProperty('secondary-sub-scale')).isEmpty;
    _secondScaleAsked = player;
    if (missing != _secondScaleMissing) logInfo(missing ? 'libmpv has no secondary-sub-scale: the second subtitle carries its own size' : 'libmpv has secondary-sub-scale');
    _secondScaleMissing = missing;
  }

  /// The track the main subtitle shows the lines of, or 'no'.
  String get _mainSource => _subtitleCopies[_mainTrackId]?.source ?? _mainTrackId;

  /// The font libmpv draws the main subtitle in.
  String get _mainFont => _drawnFamily ?? (settings.subtitleFont.isEmpty ? 'sans-serif' : PlayerSettings.fontForThisSystem(settings.subtitleFont));

  /// The family libmpv draws the main subtitle in, where the settings alone
  /// do not say it: on Android and iOS the one that draws this video's
  /// script; on a desktop the default font in the character forms of the
  /// subtitle's language (Japanese kanji as Japanese writes them).
  String? get _drawnFamily {
    if (Platform.isAndroid || Platform.isIOS) return _subtitleFamily;
    if (settings.subtitleFont.isEmpty) return null;
    return PlayerSettings.fontForThisSystem(settings.subtitleFont, language: player?.state.track.subtitle.language ?? '');
  }

  /// Whether the subtitle track [id] is Lumtub's copy of another, which
  /// track lists leave out.
  bool isSubtitleCopy(String id) => _subtitleCopies.containsKey(id);

  /// A new video: its tracks are numbered afresh, and copying still going
  /// on for the last one stops.
  void _forgetSubtitleCopies() {
    _subtitleCopies.clear();
    _copySerial++;
  }

  /// While libmpv draws subtitles, shows each one as Lumtub's copy of its
  /// track where mpv alone would draw it unlike the Flutter view:
  ///  * the second subtitle as an ASS file in its own font, color and
  ///    opacity (mpv styles both subtitles alike otherwise);
  ///  * either one with its lines broken where the Flutter view breaks
  ///    them: libass breaks only at spaces, so Chinese or Japanese without
  ///    spaces would run off both edges.
  /// With libmpv not drawing, the tracks themselves show again.
  ///
  /// [moved] is a track replaced by a new one (more of a translation): a
  /// copy of it is made again from the new one and swapped in, so the
  /// plain track never shows in between.
  void _restyleSubtitles(Player player, {({String old, String now})? moved}) {
    if (player.platform is! NativePlayer) return;
    if (moved == null && !_restyleNeeded) return;
    // One at a time: each starts from what the one before put on screen.
    final serial = _copySerial;
    _restyling = _restyling.then((_) => _restyleNow(player, serial, moved)).catchError((Object e) => logWarn('Could not copy the subtitles: $e'));
  }

  /// Whether either subtitle may need a copy made, swapped or taken away.
  bool get _restyleNeeded {
    final main = _mainTrackId;
    bool wrong(String shown, bool second) {
      if (shown == 'no' || shown == 'auto' || shown.isEmpty) return false;
      final copy = _subtitleCopies[shown];
      if (!libassDraws) return copy != null;
      if (copy == null) return second || !_plainFits.contains('$shown|$_mainCopyKey');
      return copy.second != second || copy.key != (second ? _secondCopyKey : _mainCopyKey);
    }

    // 模糊翻译 keeps the second subtitle's plain and blurred copies both.
    return wrong(main, false) || wrong(secondaryTrackId, true) || _subtitleCopies.length > (settings.blurSecondary ? 3 : 2);
  }

  Future<void> _restyleNow(Player player, int serial, ({String old, String now})? moved) async {
    final platform = player.platform;
    bool current() => identical(player, this.player) && serial == _copySerial;
    if (platform is! NativePlayer || !current()) return;
    await _askSecondScale(player, platform);
    if (!current()) return;
    // The second one first: it is hidden until its copy is on, while the
    // main one shows meanwhile, only with its lines not yet broken.
    var quick = false;
    for (final second in [true, false]) {
      final shown = await platform.getProperty(second ? 'secondary-sid' : 'sid');
      if (!current()) return;
      if (shown.isEmpty || shown == 'no' || shown == 'false') continue;
      final copy = _subtitleCopies[shown];
      var source = copy?.source ?? shown;
      if (moved != null && source == moved.old) source = moved.now;
      final wanted = libassDraws ? await _copyFor(platform, source, second: second, current: current) : source;
      if (second && (_subtitleCopies[wanted]?.key.endsWith(_quickMark) ?? false)) quick = true;
      if (!current()) return;
      if (wanted != shown) {
        await platform.setProperty(second ? 'secondary-sid' : 'sid', wanted);
        // mpv may have shown the track in the other place too.
        if (second && await platform.getProperty('sid') == wanted) await platform.setProperty('sid', source);
        if (!second) await syncMainSubtitle();
      }
      // Hidden while its copy was made (the secondary-sid listener); shown
      // now in its own style, or as it is where no copy could be made.
      if (second) await platform.setProperty('secondary-sub-visibility', libassDraws && !subtitlesOff ? 'yes' : 'no');
    }
    // The second subtitle went on with the lines around now only: the
    // whole track follows (the restyle sees the quick copy's key).
    if (quick && current()) _restyleSubtitles(player);
    // Copies neither subtitle shows any more: a growing translation would
    // pile them up in mpv's track list.
    final main = await platform.getProperty('sid'), secondShown = await platform.getProperty('secondary-sid');
    // 模糊翻译: the second subtitle's other copy, blurred or plain, is kept
    // ready, so showing or blurring it swaps tracks at once.
    String? other;
    final secondSource = _subtitleCopies[secondShown]?.source;
    if (!quick && libassDraws && settings.blurSecondary && secondSource != null && current()) {
      other = await _copyFor(platform, secondSource, second: true, current: current, blurred: !secondBlurred);
    }
    for (final id in [..._subtitleCopies.keys]) {
      if (id == main || id == secondShown || id == other || !current()) continue;
      final gone = _subtitleCopies.remove(id);
      try {
        await platform.command(['sub-remove', id]);
        if (gone != null) await File(gone.file).delete();
      } catch (e) {
        logDebug(() => 'Could not remove the old subtitle copy $id: $e');
      }
    }
  }

  /// The track to show for [source]: its copy, made now if need be, or the
  /// track itself where it needs none or none can be made.
  /// [blurred] asks for the second subtitle's copy blurred or not, made
  /// whole at once, rather than as it shows now.
  Future<String> _copyFor(NativePlayer platform, String source, {required bool second, required bool Function() current, bool? blurred}) async {
    final blur = second && (blurred ?? secondBlurred);
    var key = second ? _secondCopyKeyFor(blur) : _mainCopyKey;
    final tracks = await mpvSubtitleTracks(platform);
    final made = _subtitleCopies.entries.where((e) => e.value.source == source && e.value.key == key && tracks.containsKey(e.key)).firstOrNull;
    if (made != null) return made.key;
    final track = tracks[source];
    if (track == null || !second && _plainFits.contains('$source|$key')) return source;
    var cues = await _trackCues(platform, track);
    if (cues.isEmpty || !current()) return source;
    // The second subtitle is hidden until its copy is on. A long track is
    // first copied for the lines around now, which takes a moment where
    // laying out all of them took a second or more on a phone; the whole
    // copy replaces it right after.
    bool near(SubtitleCue c) => c.end >= _quickFrom && c.start <= _quickFrom + const Duration(seconds: 90);
    final hasQuick = _subtitleCopies.values.any((c) => c.source == source && c.key == '$key$_quickMark');
    if (second && blurred == null && cues.length > 60 && !hasQuick) {
      _quickFrom = (player?.state.position ?? Duration.zero) - const Duration(seconds: 5);
      cues = cues.where(near).toList();
      key = '$key$_quickMark';
      if (cues.isEmpty) return source;
    }
    final look = _libassLook;
    final String text;
    if (second) {
      final room = _roomEms(settings.secondaryScale);
      final font = Platform.isAndroid || Platform.isIOS
          ? _trackFamily(cues.take(40).map((c) => c.text).join('\n'), track.language ?? '')
          // In the character forms of the second subtitle's own language.
          : settings.secondaryFont.isEmpty
              ? null
              : PlayerSettings.fontForThisSystem(settings.secondaryFont, language: track.language ?? '');
      final mainTrack = tracks[_mainSource];
      var mainCues = mainTrack == null ? const <SubtitleCue>[] : await _trackCues(platform, mainTrack);
      if (key.endsWith(_quickMark)) mainCues = mainCues.where(near).toList();
      if (!current()) return source;
      final main = (cues: mainCues, font: _mainFont, room: _roomEms(settings.subtitleScale).toDouble(), wrapFont: settings.subtitleFont);
      final secondLanguage = track.language ?? '', mainLanguage = mainTrack?.language ?? '';
      text = secondAss(cues, settings,
          outline: look.em > 0 ? look.border / look.em : 0,
          room: room.toDouble(),
          font: font,
          main: main,
          aspect: _videoAspect,
          scale: _secondCopyScale,
          blurred: blur,
          runs: Platform.isAndroid || Platform.isIOS
              ? (text, {required bool second}) => _runsAgainst(text, second ? font : _mainFont, second ? secondLanguage : mainLanguage)
              : Platform.isLinux
                  ? (text, {required bool second}) => _mixedRuns(text, second ? secondLanguage : mainLanguage)
                  : null);
    } else {
      final room = _roomEms(settings.subtitleScale).toDouble();
      final language = track.language ?? '';
      final wrapped = <String>[];
      // Lines mixing scripts, in stretches each in its font (Android and
      // iOS, where libass has no fallback); null for the rest.
      final mixed = <List<({String text, String? family})>?>[];
      for (final (i, c) in cues.indexed) {
        // A batch at a time, so a long track does not hold up the frames.
        if (i > 0 && i % 100 == 0) {
          await Future<void>(() {});
          if (!current()) return source;
        }
        final w = LibassLayout.wrap(c.text, room, font: settings.subtitleFont, bold: settings.subtitleBold);
        wrapped.add(w);
        mixed.add(_mixedRuns(w, language));
      }
      // Nothing runs past the edges and no line mixes scripts: the track
      // shows as it is.
      if (Iterable<int>.generate(cues.length).every((i) => wrapped[i] == cues[i].text && mixed[i] == null)) {
        _plainFits.add('$source|$key');
        return source;
      }
      // Blank lines would end an SRT cue.
      text = toSrt([
        for (final (i, c) in cues.indexed)
          (
            start: c.start,
            end: c.end,
            text: (mixed[i]?.map((r) => r.family == null ? r.text : '<font face="${r.family}">${r.text}</font>').join() ?? wrapped[i]).replaceAll(RegExp(r'\n\s*\n'), '\n'),
          ),
      ]);
    }
    final folder = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}Lumtub subtitles');
    await folder.create(recursive: true);
    final file = File('${folder.path}${Platform.pathSeparator}copy-${playing?.id ?? 'video'}-${_copyFiles++}.${second ? 'ass' : 'srt'}');
    await file.writeAsString(text);
    if (!current()) {
      await file.delete();
      return source;
    }
    await platform.command(['sub-add', file.path, 'auto', track.title ?? '', track.language ?? '']);
    final list = jsonDecode(await platform.getProperty('track-list'));
    final added = list is List ? list.whereType<Map<Object?, Object?>>().where((t) => t['type'] == 'sub' && t['external-filename'] == file.path).lastOrNull : null;
    if (added == null) return source;
    final id = '${added['id']}';
    _subtitleCopies[id] = (source: source, key: key, second: second, file: file.path);
    if (!current()) return source;
    logInfo(second ? 'Second subtitle drawn in its own style (track $source as $id)' : 'Subtitle lines broken for libmpv (track $source as $id)');
    // Its size (secondary-sub-scale) is sent with the player's look, which
    // may have gone out before this copy was there.
    if (second) _queueLibassLook();
    return id;
  }

  /// [text]'s stretches in their fonts when it mixes scripts no one font
  /// draws, on Android and iOS; null where libass draws it as it is. On
  /// Linux, the stretches in scripts whose fonts were downloaded name
  /// them (the rest null), as fontconfig does not know those fonts.
  List<({String text, String? family})>? _mixedRuns(String text, String language) {
    if (Platform.isLinux) {
      if (linuxScriptFamilies.isEmpty) return null;
      final stretches = AndroidSubtitleFonts.stretches(text, linuxScriptFamilies);
      return stretches.any((r) => r.family != null) ? stretches : null;
    }
    if (!(Platform.isAndroid || Platform.isIOS) || AndroidSubtitleFonts.familyFor(text, language: language) != null) return null;
    final runs = AndroidSubtitleFonts.runs(text, language: language);
    return runs != null && runs.length > 1 ? runs : null;
  }

  /// [text]'s stretches when any is drawn in another family than [font],
  /// the one its style already names; null when [font] draws it all.
  List<({String text, String family})>? _runsAgainst(String text, String? font, String language) {
    final runs = AndroidSubtitleFonts.runs(text, language: language);
    if (runs == null || runs.every((r) => r.family == font)) return null;
    return runs;
  }

  /// The family a whole track is drawn in by its style: the one that draws
  /// all of [sample], or else the one that draws most of it.
  String? _trackFamily(String sample, String language) {
    final whole = AndroidSubtitleFonts.familyFor(sample, language: language);
    if (whole != null) return whole;
    final counts = <String, int>{};
    for (final line in sample.split('\n')) {
      for (final run in AndroidSubtitleFonts.runs(line, language: language) ?? const <({String text, String family})>[]) {
        counts[run.family] = (counts[run.family] ?? 0) + run.text.length;
      }
    }
    return counts.entries.fold<MapEntry<String, int>?>(null, (best, e) => best == null || e.value > best.value ? e : best)?.key;
  }
}
