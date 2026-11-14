part of 'app_controller.dart';

/// Subtitles drawn by libmpv look as the Flutter subtitle view draws them
/// in the same player: one set of settings, whoever draws. The letter size,
/// room below and outline follow the player's size; the second subtitle
/// gets its own font, color and opacity from a styled copy of its track.
extension LibassLookActions on AppController {
  /// The player showing subtitles was laid out at [view], where the Flutter
  /// view scales text by [textScale] and its padding by [paddingScale].
  void subtitleViewChanged(Size view, double textScale, double paddingScale) {
    final last = _subtitleView;
    if (last != null && (last.view.width - view.width).abs() < 2 && (last.view.height - view.height).abs() < 2 && last.textScale == textScale && last.paddingScale == paddingScale) return;
    _subtitleView = (view: view, textScale: textScale, paddingScale: paddingScale);
    _queueLibassLook();
  }

  /// Options were set from the settings alone: the player's size and the
  /// second subtitle's style are put back.
  void _optionsApplied(Player player) {
    _queueLibassLook(again: true);
    unawaited(Future(() => _styleSecond(player)));
  }

  /// The look for the player now: its laid-out size when known.
  LibassLook get _libassLook {
    final w = player?.state.width ?? 0, h = player?.state.height ?? 0;
    final aspect = w > 0 && h > 0 ? w / h : 16 / 9;
    final view = _subtitleView;
    if (view == null) return LibassLook.standard(position: settings.subtitlePosition, border: settings.subtitleBorder, byHeight: Platform.isAndroid, caption: Device.captionScale);
    return LibassLook.of(view: view.view, aspect: aspect, textScale: view.textScale, paddingScale: view.paddingScale, position: settings.subtitlePosition, border: settings.subtitleBorder);
  }

  /// Sends the look once resizing settles: a window dragged wider lays the
  /// player out every frame.
  void _queueLibassLook({bool again = false}) {
    if (again) _libassSent = {};
    _libassLookTimer?.cancel();
    if (!settings.libassSubtitles || player?.platform is! NativePlayer) return;
    _libassLookTimer = Timer(const Duration(milliseconds: 120), () => unawaited(_applyLibassLook()));
  }

  /// Sends libmpv the subtitle options that changed for the player's size.
  Future<void> _applyLibassLook() async {
    final player = this.player;
    final platform = player?.platform;
    if (player == null || platform is! NativePlayer || !settings.libassSubtitles) return;
    final look = _libassLook;
    final options = PlayerOptionApplicator.libassOptions(settings, look)
      // Placed with the controls and the main subtitle's lines below.
      ..remove('sub-pos')
      ..remove('secondary-sub-pos');
    // On Android the font that draws this video's script, at its own size.
    if (_subtitleFamily case final family?) {
      options['sub-font'] = family;
      options['sub-font-size'] = look.fontSize(family).toStringAsFixed(1);
    }
    if (_styledSeconds.containsKey(secondaryTrackId)) options['secondary-sub-scale'] = (look.em / secondEm).toStringAsFixed(3);
    for (final MapEntry(:key, :value) in options.entries) {
      if (_libassSent[key] == value) continue;
      try {
        await platform.setProperty(key, value);
        _libassSent[key] = value;
      } catch (e) {
        logDebug(() => 'Could not set $key: $e');
      }
    }
    if (identical(player, this.player)) _placeSecondary(player, _mainSubtitle);
  }

  /// What the styled copy of a second subtitle depends on.
  String get _secondStyleKey => [
        settings.secondaryFont,
        settings.secondaryScale,
        settings.secondaryColor,
        settings.secondaryOpacity,
        settings.subtitleBold,
        settings.subtitleBackground,
        settings.subtitleBorder,
      ].join('|');

  /// Whether the subtitle track [id] is a styled copy of another, which
  /// track lists leave out.
  bool isStyledSecond(String id) => _styledSeconds.containsKey(id);

  /// A new video: its tracks are numbered afresh.
  void _forgetStyledSeconds() {
    _styledSeconds.clear();
    _styling = null;
  }

  /// Shows the second subtitle in its own style while libmpv draws: a copy
  /// of its track as an ASS file in that font, color and opacity, put in
  /// its place. mpv styles both subtitles alike otherwise.
  ///
  /// [from] is a new track of the shown copy's source, whose file grew (more
  /// of a translation): the copy is made again from it and swapped in, so
  /// the plain track never shows in between.
  Future<void> _styleSecond(Player player, {String? from}) {
    // One at a time: each starts from the copy the one before put on screen.
    final run = _styleQueue.then((_) => _styleSecondNow(player, from: from));
    _styleQueue = run.catchError((_) {});
    return run;
  }

  Future<void> _styleSecondNow(Player player, {String? from}) async {
    final platform = player.platform;
    if (platform is! NativePlayer || !identical(player, this.player) || !libassDraws) return;
    final shown = secondaryTrackId;
    if (shown == 'no') return;
    final key = _secondStyleKey;
    final copy = _styledSeconds[shown];
    if (from == null && copy != null && copy.key == key) return _queueLibassLook();
    final source = from ?? copy?.source ?? shown;
    final job = '$source\u0000$key';
    if (_styling == job) return;
    _styling = job;
    try {
      final tracks = await mpvSubtitleTracks(platform);
      final made = _styledSeconds.entries.where((e) => e.value.source == source && e.value.key == key && tracks.containsKey(e.key)).firstOrNull;
      if (made != null) {
        await platform.setProperty('secondary-sid', made.key);
        await _dropCopy(platform, shown, keep: made.key);
        return;
      }
      final track = tracks[source];
      if (track == null) return;
      final cues = await _trackCues(platform, track);
      if (cues.isEmpty || !identical(player, this.player) || secondaryTrackId != shown || _secondStyleKey != key) return;
      final look = _libassLook;
      final folder = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}Lumtub subtitles');
      await folder.create(recursive: true);
      final file = File('${folder.path}${Platform.pathSeparator}second-${playing?.id ?? 'video'}-$source-${key.hashCode.toUnsigned(32)}.ass');
      if (await file.exists()) await file.delete();
      await file.writeAsString(secondAss(cues, settings, outline: look.em > 0 ? look.border / look.em : 0));
      final main = await platform.getProperty('sid');
      await platform.command(['sub-add', file.path, 'auto', track.title ?? '', track.language ?? '']);
      final list = jsonDecode(await platform.getProperty('track-list'));
      final added = list is List ? list.whereType<Map>().where((t) => t['type'] == 'sub' && t['external-filename'] == file.path).lastOrNull : null;
      if (added == null || !identical(player, this.player)) return;
      final id = '${added['id']}';
      _styledSeconds[id] = (source: source, key: key);
      if (secondaryTrackId != shown) return;
      await platform.setProperty('secondary-sid', id);
      // mpv may have picked the copy as the main subtitle too.
      if (await platform.getProperty('sid') != main) await platform.setProperty('sid', main.isEmpty ? 'no' : main);
      await _dropCopy(platform, shown, keep: id);
      logInfo('Second subtitle drawn in its own style (track $source as $id)');
    } catch (e) {
      logWarn('Could not style the second subtitle: $e');
      // Better plain than gone.
      if (from != null && secondaryTrackId == shown) await platform.setProperty('secondary-sid', from).catchError((_) {});
    } finally {
      if (_styling == job) _styling = null;
    }
  }

  /// Removes the styled copy [id] once [keep] shows in its place: copies of
  /// a growing translation would pile up in mpv's track list.
  Future<void> _dropCopy(NativePlayer platform, String id, {required String keep}) async {
    if (id == keep || !_styledSeconds.containsKey(id)) return;
    _styledSeconds.remove(id);
    try {
      await platform.command(['sub-remove', id]);
    } catch (e) {
      logDebug(() => 'Could not remove the old styled copy $id: $e');
    }
  }
}
