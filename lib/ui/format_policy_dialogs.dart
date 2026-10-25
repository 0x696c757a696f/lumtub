import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../format_policy.dart';
import '../player_settings.dart';
import '../video_codec.dart';
import '../widgets/pilinara_settings_tiles.dart';

/// The text under the disabled codecs, in the settings and the player menu.
String get disabledCodecsNote => tr('禁用后，所有播放策略都不会主动选择对应编码。');

/// Said when a choice would disable every codec YouTube plays.
String get lastCodecNote => tr('H.264、VP9、AV1 至少保留一个，否则视频无法播放');

/// Said where H.264 cannot be disabled.
String get h264NeededNote => tr('VP9 和 AV1 都不能硬解，不能禁用 H.264，否则所有视频都要用 CPU 软解');

/// [settings] with [codec] disabled or enabled again; null when that would
/// leave nothing to play.
PlayerSettings? withCodecDisabled(PlayerSettings settings, VideoCodec codec, bool disabled) {
  final current = settings.disabledCodecs;
  return _withCodecs(settings, disabled ? {...current, codec} : ({...current}..remove(codec)));
}

PlayerSettings? _withCodecs(PlayerSettings settings, Set<VideoCodec> next) {
  if (!VideoCodec.playableWithout(next)) return null;
  if (next.contains(VideoCodec.h264) && !settings.disabledCodecs.contains(VideoCodec.h264) && !FormatPolicy.canDisableH264(settings)) return null;
  return settings.withDisabledCodecs(next);
}

void _say(BuildContext context, String text) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

String _why(PlayerSettings settings, Set<VideoCodec> next) => VideoCodec.playableWithout(next) ? h264NeededNote : lastCodecNote;

/// Disables or enables [codec] through [save], or says why it cannot.
void toggleCodec(BuildContext context, PlayerSettings settings, VideoCodec codec, bool disabled, ValueChanged<PlayerSettings> save) {
  final next = withCodecDisabled(settings, codec, disabled);
  if (next != null) return save(next);
  final current = settings.disabledCodecs;
  _say(context, _why(settings, disabled ? {...current, codec} : current));
}

/// Asks for a [PlaybackStrategy], each with its one-line description, and
/// reports a changed choice.
Future<void> pickPlaybackStrategy(BuildContext context, PlaybackStrategy current, ValueChanged<PlaybackStrategy> onSelected) async {
  final result = await showDialog<PlaybackStrategy>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(tr('播放策略')),
      children: [
        for (final strategy in PlaybackStrategy.values)
          ListTile(
            dense: true,
            leading: Icon(strategy == current ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            title: Text(strategy.label),
            subtitle: Text(strategy.description),
            onTap: () => Navigator.pop(context, strategy),
          ),
      ],
    ),
  );
  if (result != null && result != current) onSelected(result);
}

/// Asks which codecs to disable and reports the settings when they changed.
Future<void> pickDisabledCodecs(BuildContext context, PlayerSettings settings, ValueChanged<PlayerSettings> onSelected) async {
  final current = settings.disabledCodecs;
  final result = await showDialog<List<VideoCodec>>(
    context: context,
    builder: (context) => OrderedMultiSelectDialog<VideoCodec>(
      title: tr('禁用视频编码'),
      ordered: false,
      initValues: current,
      values: [for (final codec in VideoCodec.values) (codec, codec.label, disabledCodecsNote)],
    ),
  );
  if (result == null) return;
  final chosen = result.toSet();
  if (chosen.length == current.length && current.containsAll(chosen)) return;
  final next = _withCodecs(settings, chosen);
  if (next == null) {
    if (context.mounted) _say(context, _why(settings, chosen));
    return;
  }
  onSelected(next);
}
