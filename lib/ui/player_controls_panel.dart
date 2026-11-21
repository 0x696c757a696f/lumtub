part of 'player_controls.dart';

extension _MorePanel on _PlayerControlsState {
  void _openMore(BuildContext context) {
    _showBars();
    _menuOpened();
    unawaited(showPlayerPanel(
      context,
      title: tr('More settings'),
      builder: (panel) => ListenableBuilder(
        listenable: Listenable.merge([_c, _picture, videoFit]),
        builder: (panel, _) => _panelBody(context, panel),
      ),
    ).whenComplete(_menuClosed));
  }

  void _closePanel(BuildContext panel) => Navigator.of(panel, rootNavigator: true).pop();

  void _markLoop() {
    final c = _c;
    unawaited(c.markLoop().then((_) {
      final a = c.loopA, b = c.loopB;
      if (a != null && b != null) {
        _showFeedback(AppIcons.repeatOnce, tr('Looping {0} – {1}', [formatPlaybackTime(a), formatPlaybackTime(b)]));
      } else if (a != null) {
        _showFeedback(AppIcons.repeatOnce, tr('Point A {0}; press again to set point B', [formatPlaybackTime(a)]));
      } else {
        _showFeedback(AppIcons.repeatOnce, tr('A-B loop off'));
      }
    }));
  }

  /// The audio language [AppController.audioLanguage] selects among [languages].
  String _chosenLanguage(List<AudioLanguage> languages) {
    final wanted = _c.audioLanguage.toLowerCase();
    if (wanted.isNotEmpty) {
      for (final language in languages) {
        if (language.code.toLowerCase() == wanted) return language.code;
      }
      for (final language in languages) {
        if (language.code.toLowerCase().startsWith(wanted)) return language.code;
      }
    }
    final original = languages.where((l) => l.isOriginal).firstOrNull;
    return (original ?? languages.first).code;
  }

  Widget _audioTrackChoice() {
    final c = _c;
    final languages = c.availableAudioLanguages;
    if (languages.length > 1) {
      return PanelChoices<String>(
        label: tr('Audio track'),
        icon: AppIcons.musicNotes,
        collapsed: true,
        value: _chosenLanguage(languages),
        values: [for (final l in languages) (l.code, audioLanguageLabel(l))],
        onSelected: (code) {
          final language = languages.firstWhere((l) => l.code == code);
          unawaited(c.chooseAudioLanguage(language.isOriginal ? '' : code));
        },
      );
    }
    return StreamBuilder<Track>(
      stream: _player.stream.track,
      initialData: _player.state.track,
      builder: (context, snapshot) {
        final tracks = _player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
        if (tracks.length < 2) return const SizedBox.shrink();
        return PanelChoices<String>(
          label: tr('Audio track'),
          icon: AppIcons.musicNotes,
          collapsed: true,
          value: (snapshot.data ?? _player.state.track).audio.id,
          values: [for (final t in tracks) (t.id, trackLabel(t.id, t.title, t.language))],
          onSelected: (id) => unawaited(_player.setAudioTrack(tracks.firstWhere((t) => t.id == id))),
        );
      },
    );
  }

  Widget _sleepChoice() {
    final c = _c;
    final sleepAt = c.sleepAt;
    const off = -1, after = 0, none = -2;
    final remaining = sleepAt == null ? 0 : sleepAt.difference(DateTime.now()).inMinutes + 1;
    final value = sleepAt == null && !c.sleepAfterCurrent ? off : c.sleepAfterCurrent ? after : none;
    return PanelChoices<int>(
      label: sleepAt == null ? tr('Sleep timer') : tr('Sleep timer (pauses in {0} min)', [remaining]),
      icon: AppIcons.moonStars,
      value: value,
      values: [
        (off, tr('Off')),
        (after, tr('After the current video')),
        for (final minutes in const [15, 30, 45, 60, 90]) (minutes, tr('{0} min', [minutes])),
      ],
      onSelected: (v) {
        if (v == off) {
          c.setSleepTimer(null);
        } else if (v == after) {
          c.setSleepTimer(null, afterCurrent: true);
        } else {
          c.setSleepTimer(Duration(minutes: v));
        }
      },
    );
  }

  Widget _panelBody(BuildContext context, BuildContext panel) {
    final c = _c;
    final settings = c.settings;
    final fullscreen = isFullscreen(context);
    final loopA = c.loopA, loopB = c.loopB;
    final detail = FormatPolicy.disabledNames(settings);
    final screenshotDetail = tr('Saved to Pictures\\Lumtub and copied to the clipboard');
    final qualitySelected = settings.maxHeight == 0 && c.droppedCap > 0 ? -1 : settings.maxHeight;
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          PanelToggle(label: tr('Keep window on top'), icon: AppIcons.pushPin, value: c.pinned, onChanged: (_) => c.togglePinned()),
          PanelToggle(label: tr('Listen only'), icon: AppIcons.headphonesFill, value: c.audioOnly, onChanged: (_) => unawaited(c.toggleAudioOnly())),
          PanelToggle(label: tr('SponsorBlock'), icon: AppIcons.shield, value: settings.sponsorBlock, onChanged: (_) => unawaited(c.toggleSponsorBlock())),
          PanelToggle(label: tr('Playback info'), icon: AppIcons.info, value: c.showStats, onChanged: (_) => c.toggleStats()),
          PanelToggle(label: tr('Mirror'), icon: AppIcons.flipHorizontal, value: _picture.mirrored, onChanged: (v) => unawaited(_picture.setMirrored(v))),
          PanelToggle(
            label: loopA != null && loopB != null ? tr('A-B looping') : loopA != null ? tr('Set point B') : tr('A-B loop'),
            icon: AppIcons.repeatOnce,
            value: loopA != null,
            onChanged: (_) => _markLoop(),
          ),
          PanelToggle(
            label: tr('In-app mini player'),
            icon: AppIcons.pictureInpicture,
            value: false,
            onChanged: (_) async {
              _closePanel(panel);
              if (fullscreen) await widget.state?.exitFullscreen();
              c.enterMini();
            },
          ),
        ]),
      ),
      PanelHeading(tr('Video')),
      if (isPhone(context))
        PanelChoices<double>(
          label: tr('Speed'),
          icon: AppIcons.gauge,
          value: _player.state.rate,
          values: [for (final speed in settings.speeds) (speed, '${trimSpeed(speed)}X')],
          onSelected: (speed) => unawaited(_player.setRate(speed)),
        ),
      PanelChoices<int>(
        label: tr('Quality'),
        icon: AppIcons.sealCheck,
        value: qualitySelected,
        values: [for (final h in c.qualityChoices) (h, qualityLabel(h, c.availableFrameRates[h]))],
        onSelected: (h) => unawaited(c.setMaxHeight(h)),
      ),
      PanelChoices<VideoFit>(
        label: tr('Aspect ratio'),
        icon: AppIcons.arrowsOut,
        value: videoFit.value,
        values: [for (final fit in VideoFit.values) (fit, fit.label)],
        onSelected: (fit) => videoFit.value = fit,
      ),
      PanelChoices<int>(
        label: tr('Rotate'),
        icon: AppIcons.arrowClockwise,
        value: _picture.rotation,
        values: [for (final r in PictureTransform.rotations) (r, '$r°')],
        onSelected: (r) => unawaited(_picture.setRotation(r)),
      ),
      PanelChoices<double>(
        label: tr('Zoom'),
        icon: AppIcons.magnifyingGlassPlus,
        value: _picture.zoom,
        values: [for (final z in PictureTransform.zoomLevels) (z, z == 1 ? tr('Original size') : '${trimSpeed(z)}x')],
        onSelected: (z) => unawaited(_picture.setZoom(z)),
      ),
      PanelLink(
        label: tr('Video and A/V sync adjustments'),
        icon: AppIcons.slidersHorizontal,
        onTap: () {
          _closePanel(panel);
          unawaited(openPictureSettings(context, c));
        },
      ),
      PanelHeading(tr('Sound')),
      PanelChoices<AudioQuality>(
        label: tr('Audio quality'),
        icon: AppIcons.musicNote,
        value: settings.audioQuality,
        values: [for (final q in AudioQuality.values) (q, q.label)],
        onSelected: (q) => unawaited(c.reloadVideo(settings.copyWith(audioQuality: q))),
      ),
      PanelChoices<DubbedAudio>(
        label: tr('Dubbed audio'),
        icon: AppIcons.musicNotes,
        collapsed: true,
        value: settings.dubbedAudio,
        values: [for (final d in DubbedAudio.values) (d, d.label)],
        onSelected: (d) => unawaited(c.reloadVideo(settings.copyWith(dubbedAudio: d))),
      ),
      _audioTrackChoice(),
      PanelHeading(tr('Play')),
      PanelChoices<PlayOrder>(
        label: tr('Playback order'),
        icon: AppIcons.repeat,
        value: settings.playOrder,
        values: [for (final o in PlayOrder.values) (o, o.label)],
        onSelected: (o) => unawaited(c.setPlayOrder(o)),
      ),
      _sleepChoice(),
      PanelChoices<PlaybackStrategy>(
        label: tr('Playback strategy'),
        icon: AppIcons.filmStrip,
        value: settings.strategy,
        values: [for (final s in PlaybackStrategy.values) (s, s.label)],
        onSelected: (s) => unawaited(c.reloadVideo(settings.copyWith(strategy: s))),
      ),
      PanelLink(
        label: tr('Disabled video codecs'),
        icon: AppIcons.prohibit,
        detail: detail.isEmpty ? tr('None') : detail,
        onTap: () => unawaited(pickDisabledCodecs(context, settings, (v) => unawaited(c.reloadVideo(v)))),
      ),
      PanelLink(
        label: tr('Subtitles'),
        icon: AppIcons.subtitles,
        detail: '${settings.subtitleMode.label} · ${settings.subtitleLanguage.label}',
        onTap: () {
          _closePanel(panel);
          _openSubtitles(context);
        },
      ),
      PanelHeading(tr('Tools')),
      PanelLink(
        label: tr('Screenshot (S)'),
        icon: AppIcons.camera,
        opens: false,
        detail: Platform.isWindows ? screenshotDetail : screenshotDetail.replaceAll('\\', '/'),
        onTap: () {
          _closePanel(panel);
          _screenshot();
        },
      ),
      PanelLink(
        label: tr('Subtitle list'),
        icon: AppIcons.textAlignLeft,
        detail: tr('Click a line to jump there; A / D previous or next line, R replays'),
        onTap: () {
          _closePanel(panel);
          _openSubtitleList(context);
        },
      ),
      PanelLink(
        label: keyNames(tr('Copy current subtitle (Ctrl+C)')),
        icon: AppIcons.copy,
        opens: false,
        onTap: () {
          final text = c.currentSubtitleText;
          if (text.isEmpty) return;
          unawaited(Clipboard.setData(ClipboardData(text: text)));
          _closePanel(panel);
          _showFeedback(AppIcons.copy, tr('Subtitle copied'));
        },
      ),
      PanelLink(
        label: tr('Reload video'),
        icon: AppIcons.arrowsClockwise,
        opens: false,
        detail: tr('Reload from current position'),
        onTap: () {
          _closePanel(panel);
          unawaited(c.reloadVideo());
        },
      ),
      PanelLink(
        label: tr('Keyboard shortcuts'),
        icon: AppIcons.keyboard,
        onTap: () => unawaited(showShortcutHelp(context, c.preferences)),
      ),
    ]);
  }
}
