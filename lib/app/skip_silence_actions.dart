part of 'app_controller.dart';

/// 跳过静音: a silence-detecting filter in libmpv's audio chain and a faster
/// speed while it hears silence; see [SilenceSkipper].
extension SkipSilenceActions on AppController {
  /// Puts the filter in, or takes it out, to match the setting and the
  /// video playing; livestreams are never skipped.
  Future<void> _syncSilenceSkipping(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer || this.player != player) return;
    final want = settings.skipSilence && playing?.isLive != true;
    try {
      // Setting `af` replaces the chain, so the filter is put in again.
      await _removeAudioFilter(platform, SilenceSkipper.label);
      if (want) {
        final back = _silence.boosted ? _silence.userRate : null;
        if (back != null) await platform.setProperty('speed', '$back');
        _silence.enable(back ?? player.state.rate);
        await platform.command(['af', 'add', SilenceSkipper.filter]);
      } else {
        final back = _silence.disable();
        if (back != null) await platform.setProperty('speed', '$back');
      }
    } catch (e) {
      logWarn('Could not ${want ? 'turn on' : 'turn off'} skipping silence: $e');
    }
  }

  /// mpv's metadata from the filter changed. Runs inside mpv's event
  /// handling, so the speed is set later, never awaited here.
  void _onSilenceMetadata(Player player, String value) {
    final rate = _silence.onMetadata(value);
    final platform = player.platform;
    if (rate == null || platform is! NativePlayer || this.player != player) return;
    scheduleMicrotask(() => unawaited(platform
        .setProperty('speed', '$rate')
        .catchError((Object e) => logWarn('Could not change the speed for silence: $e'))));
  }

  /// Takes the filter labelled [label] out of libmpv's audio chain when it
  /// is there; asking for one that is not makes libmpv warn in the log.
  Future<void> _removeAudioFilter(NativePlayer platform, String label) async {
    final chain = await platform.getProperty('af').catchError((_) => '');
    if (!chain.contains('@$label:')) return;
    await platform.command(['af', 'remove', '@$label']).catchError((_) {});
  }
}
