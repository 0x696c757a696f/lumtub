import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../app_log.dart';

/// Whether frames are running late again and again, as on a processor
/// slowed by heat or a battery saver: then Lumtub draws lighter on its own
/// until they keep time again. Animations finish at once (a fade or zoom is
/// frames the list needs), surfaces leave out their patterns, and a card
/// pointed at shows no preview frames. Scrolling keeps its glide, which is
/// timed by the clock and only shows fewer steps.
///
/// It reads the engine's frame timings only: a frame over [late] to build
/// or draw counts, and [strainedAt] of the last [window] frames turn it on;
/// it goes off once no more than [easedAt] of them are late and it has
/// been on for [held] at least, so it does not flicker.
abstract final class FramePressure {
  /// A frame over this misses 60 fps with room to spare.
  static const late = Duration(milliseconds: 20);
  static const window = 60;
  static const strainedAt = 12;
  static const easedAt = 3;
  static const held = Duration(seconds: 20);

  static final strained = ValueNotifier(false);
  static bool get on => strained.value;

  static final _recent = ListQueue<bool>();
  static int _late = 0;
  static final _since = Stopwatch();
  static bool _watching = false;

  /// Starts reading frame timings; later calls do nothing.
  static void watch() {
    if (_watching) return;
    _watching = true;
    SchedulerBinding.instance.addTimingsCallback(_timings);
  }

  static void _timings(List<FrameTiming> timings) {
    for (final timing in timings) {
      add(timing.buildDuration > late || timing.rasterDuration > late);
    }
  }

  /// Counts one frame, late or on time.
  @visibleForTesting
  static void add(bool isLate) {
    _recent.addLast(isLate);
    if (isLate) _late++;
    if (_recent.length > window && _recent.removeFirst()) _late--;
    if (!strained.value && _recent.length == window && _late >= strainedAt) {
      _since
        ..reset()
        ..start();
      strained.value = true;
      logInfo('Frames keep running late ($_late of the last $window): lighter drawing until they keep time');
    } else if (strained.value && _late <= easedAt && _since.elapsed >= held) {
      strained.value = false;
      logInfo('Frames keep time again: full drawing');
    }
  }

  /// Back to the start, for tests.
  @visibleForTesting
  static void reset() {
    _recent.clear();
    _late = 0;
    strained.value = false;
  }
}
