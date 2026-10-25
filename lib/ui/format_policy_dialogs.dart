import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../player_settings.dart';
import '../video_codec.dart';
import '../widgets/pilinara_settings_tiles.dart';

/// The text under the disabled codecs, in the settings and the player menu.
String get disabledCodecsNote => tr('禁用后，所有播放策略都不会主动选择对应编码。');

/// Said when a choice would disable every codec YouTube plays.
String get lastCodecNote => tr('H.264、VP9、AV1 至少保留一个，否则视频无法播放');

/// [current] with [codec] disabled or enabled again; null when that would
/// leave nothing to play.
Set<VideoCodec>? withCodecDisabled(Set<VideoCodec> current, VideoCodec codec, bool disabled) {
  final next = disabled ? {...current, codec} : ({...current}..remove(codec));
  return VideoCodec.playableWithout(next) ? next : null;
}

void _sayLastCodec(BuildContext context) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lastCodecNote)));
}

/// Disables or enables [codec] through [save], or says why it cannot.
void toggleCodec(BuildContext context, Set<VideoCodec> current, VideoCodec codec, bool disabled, ValueChanged<Set<VideoCodec>> save) {
  final next = withCodecDisabled(current, codec, disabled);
  next == null ? _sayLastCodec(context) : save(next);
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

/// Asks which codecs to disable and reports the new set when it changed.
Future<void> pickDisabledCodecs(BuildContext context, Set<VideoCodec> current, ValueChanged<Set<VideoCodec>> onSelected) async {
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
  final next = result.toSet();
  if (!VideoCodec.playableWithout(next)) {
    if (context.mounted) _sayLastCodec(context);
    return;
  }
  if (next.length != current.length || !current.containsAll(next)) onSelected(next);
}
