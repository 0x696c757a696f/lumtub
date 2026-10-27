import 'dart:math';

import 'package:flutter/scheduler.dart';

import '../app_log.dart';

/// Counts the frames that took too long to build or draw and writes a line
/// to the log once a minute when there were any, with the page that was
/// open and how often the whole window was rebuilt, so a stutter the user
/// mentions can be found afterwards. It only reads the engine's timings.
class FrameStats {
  FrameStats._(this._page);

  /// A frame over this misses 30 fps.
  static const slow = Duration(milliseconds: 33);

  final String Function() _page;
  int _frames = 0;
  int _slow = 0;
  int _rebuilds = 0;
  Duration _worstBuild = Duration.zero;
  Duration _worstRaster = Duration.zero;
  final _pages = <String, int>{};
  DateTime _since = DateTime.now();

  static FrameStats? _instance;

  /// Starts counting; [page] names what is shown.
  static FrameStats start(String Function() page) {
    final stats = _instance ??= FrameStats._(page);
    SchedulerBinding.instance.addTimingsCallback(stats._timings);
    return stats;
  }

  /// One rebuild of the whole window.
  void rebuilt() => _rebuilds++;

  void _timings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _frames++;
      final build = timing.buildDuration;
      final raster = timing.rasterDuration;
      if (build > slow || raster > slow) {
        _slow++;
        final page = _page();
        _pages[page] = (_pages[page] ?? 0) + 1;
      }
      if (build > _worstBuild) _worstBuild = build;
      if (raster > _worstRaster) _worstRaster = raster;
    }
    final now = DateTime.now();
    if (now.difference(_since) < const Duration(minutes: 1)) return;
    if (_slow > 0) {
      final where = (_pages.entries.toList()..sort((a, b) => b.value - a.value)).take(3).map((e) => '${e.key} ${e.value}').join(', ');
      logInfo('Frames: $_slow of $_frames slow (worst build ${_ms(_worstBuild)}, raster ${_ms(_worstRaster)}) on $where; window rebuilt $_rebuilds times in ${max(1, now.difference(_since).inSeconds)} s');
    }
    _frames = _slow = _rebuilds = 0;
    _worstBuild = _worstRaster = Duration.zero;
    _pages.clear();
    _since = now;
  }

  static String _ms(Duration d) => '${(d.inMicroseconds / 1000).toStringAsFixed(1)} ms';
}
