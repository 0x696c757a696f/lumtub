part of 'app_controller.dart';

/// 音量平衡: the [VolumeBalance] chain in libmpv's audio filters, kept to
/// the setting and the video playing.
extension VolumeBalanceActions on AppController {
  /// Puts the chain in, or takes it out, for the setting and the video
  /// playing, with that video's loudness when YouTube gave it.
  Future<void> _syncVolumeBalance(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer || this.player != player) return;
    final strength = settings.volumeBalance;
    final item = playing;
    // Setting `af` replaces the chain, so the filter is put in again.
    await platform.command(['af', 'remove', '@${VolumeBalance.label}']).catchError((_) {});
    if (strength <= 0 || item == null) return;
    final loudness = _repository?.streams.loudnessOf(item.id);
    final live = item.isLive;
    try {
      await platform.command(['af', 'add', VolumeBalance.filter(strength, loudnessDb: loudness, live: live)]);
      logInfo('Volume balance at $strength%${loudness == null ? '' : ', ${VolumeBalance.gainFor(loudness).toStringAsFixed(1)} dB for loudness ${loudness.toStringAsFixed(1)}'}');
    } catch (e) {
      // A libmpv built without alimiter still has the normaliser.
      try {
        await platform.command(['af', 'add', VolumeBalance.filter(strength, live: live, withLimiters: false)]);
        logInfo('Volume balance at $strength% without limiters: $e');
      } catch (e) {
        logWarn('Could not turn on volume balance: $e');
      }
    }
  }

  /// YouTube's loudness for [videoId] arrived, perhaps after the video
  /// started through yt-dlp.
  void _onLoudness(String videoId) {
    final player = this.player;
    if (player == null || settings.volumeBalance <= 0 || playing?.id != videoId) return;
    unawaited(_syncVolumeBalance(player));
  }
}
