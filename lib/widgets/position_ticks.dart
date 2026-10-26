import 'package:media_kit/media_kit.dart';

/// [player]'s position, at most every [step] of the video (a seek or a
/// step back is passed at once). mpv reports it every frame; a progress
/// line redrawn 60 times a second for a change too small to see costs
/// battery for nothing.
Stream<Duration> coarsePosition(Player player, {Duration step = const Duration(milliseconds: 250)}) => coarse(player.stream.position, step: step);

/// [positions] thinned out as [coarsePosition] does.
Stream<Duration> coarse(Stream<Duration> positions, {Duration step = const Duration(milliseconds: 250)}) {
  Duration? last;
  return positions.where((position) {
    final previous = last;
    if (previous != null && position >= previous && position - previous < step) return false;
    last = position;
    return true;
  });
}
