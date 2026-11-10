import 'dart:isolate';

import '../app_log.dart';
import '../live_split.dart';
import '../native_core.dart';
import 'download_manager.dart';

/// Records live streams with lumtub_core, from the addresses [sources]
/// resolves (anew when [fresh]).
class CoreRecorder implements LiveRecorder {
  CoreRecorder({required this.sources, required this.proxy});

  final Future<LiveSplit?> Function(String videoId, {bool fresh}) sources;
  /// `http://host:port` to fetch through, or null.
  final String? Function() proxy;

  @override
  Future<int> start(String videoId, String stem) async {
    final core = NativeCore.instance;
    if (core == null) throw StateError(NativeCore.missingMessage);
    final split = await sources(videoId);
    if (split == null) throw StateError('no live streams to record');
    final started = core.recordStart(video: split.videoUrl, audio: split.audioUrl, stem: stem, userAgent: split.userAgent, proxy: proxy());
    final id = started.id;
    if (id == null) throw StateError(started.error ?? 'the recording could not start');
    logInfo('Recording $videoId as ${split.label}');
    return id;
  }

  @override
  ({int bytes, bool running, bool renew, String? error}) state(int id) {
    final map = NativeCore.instance?.recordState(id) ?? const {};
    for (final line in (map['log'] as List? ?? const [])) {
      logInfo('Recording: $line');
    }
    return (
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      running: map['running'] == true,
      renew: map['renew'] == true,
      error: map['error'] as String?,
    );
  }

  @override
  Future<void> renew(int id, String videoId) async {
    final split = await sources(videoId, fresh: true);
    if (split == null) throw StateError('the live has no streams any more');
    NativeCore.instance?.recordRenew(id, split.videoUrl, split.audioUrl);
  }

  @override
  Future<String?> stop(int id) => Isolate.run(() => NativeCore.recordStop(id));
}
