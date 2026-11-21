import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../format_policy.dart';
import '../player_settings.dart';
import '../video_codec.dart';
import '../widgets/pilinara_settings_tiles.dart';
import 'app_icons.dart';

/// The text under the disabled codecs, in the settings and the player menu.
String get disabledCodecsNote => tr('Once disabled, no playback strategy picks that codec.');

/// Said when a choice would disable every codec YouTube plays.
String get lastCodecNote => tr('Keep at least one of H.264, VP9 and AV1, or no video can play');

/// Said where H.264 cannot be disabled.
String get h264NeededNote => tr('VP9 and AV1 are not decoded in hardware here, so H.264 cannot be disabled, or every video would be decoded on the CPU');

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

/// Asks for one of [values], each with its one-line description, and
/// reports a changed choice.
Future<void> pickDescribed<T>(BuildContext context, {required String title, required T current, required List<(T, String, String)> values, required ValueChanged<T> onSelected}) async {
  final result = await showDialog<T>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final (value, label, description) in values)
          ListTile(
            dense: true,
            leading: Icon(value == current ? AppIcons.radioButton : AppIcons.circle),
            title: Text(label),
            subtitle: Text(description),
            onTap: () => Navigator.pop(context, value),
          ),
      ],
    ),
  );
  if (result != null && result != current) onSelected(result);
}

/// Asks for a [PlaybackStrategy], each with its one-line description, and
/// reports a changed choice.
Future<void> pickPlaybackStrategy(BuildContext context, PlaybackStrategy current, ValueChanged<PlaybackStrategy> onSelected) => pickDescribed(
      context,
      title: tr('Playback strategy'),
      current: current,
      values: [for (final s in PlaybackStrategy.values) (s, s.label, s.description)],
      onSelected: onSelected,
    );

/// How this device decodes AV1 and what automatic playback does about it.
String av1Note(PlayerSettings settings) {
  if (settings.disabledCodecs.contains(VideoCodec.av1)) return tr('AV1 is disabled');
  if (FormatPolicy.hardware(settings, VideoCodec.av1)) return tr('Hardware decoding. Smart auto prefers AV1: the same picture in less data');
  if (FormatPolicy.softwareOnly(settings, VideoCodec.av1)) return tr('Software decoding. Smart auto avoids AV1, which costs much power on the CPU');
  return tr('Not verified yet. Smart auto prefers other codecs until an AV1 video has played in hardware');
}

/// Asks which codecs to disable and reports the settings when they changed.
Future<void> pickDisabledCodecs(BuildContext context, PlayerSettings settings, ValueChanged<PlayerSettings> onSelected) async {
  final current = settings.disabledCodecs;
  final result = await showDialog<List<VideoCodec>>(
    context: context,
    builder: (context) => OrderedMultiSelectDialog<VideoCodec>(
      title: tr('Disabled video codecs'),
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
