import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'app_log.dart';

/// Which queue a job waits in. Work done on this device is limited so it
/// never takes the computer away from playback; work a service does only
/// waits on the network.
enum JobLane {
  /// Recognition and text generation on this device: one at a time.
  heavy(1),

  /// Small models on this device, such as embeddings: one at a time.
  light(1),

  /// Requests to a service the user set up.
  network(2);

  const JobLane(this.limit);

  /// How many jobs of this lane run at once.
  final int limit;
}

/// Which job goes first when several wait in one lane.
enum JobPriority {
  /// For the video playing now.
  watching,

  /// Something the user just asked for.
  asked,

  /// Work nobody waits for, such as filling an index. Waits while
  /// [JobQueue.backgroundPaused] says so.
  background,
}

/// What a running job is told and can tell.
class JobContext {
  JobContext._(this._job);
  final _Job _job;

  /// Whether the job was cancelled; long work checks it between steps.
  bool get cancelled => _job.cancelled;

  /// Throws [JobCancelled] once the job is cancelled.
  void checkCancelled() {
    if (_job.cancelled) throw const JobCancelled();
  }

  /// Shows what the job is doing, and [done] of [total] steps.
  void progress(String stage, [int done = 0, int total = 0]) {
    _job.info = _job.info._with(stage: stage, done: done, total: total);
    _job.queue._changed();
  }
}

class JobCancelled implements Exception {
  const JobCancelled();

  @override
  String toString() => 'The job was cancelled';
}

/// A job as the interface shows it.
@immutable
class JobInfo {
  const JobInfo({required this.key, required this.lane, required this.priority, required this.running, this.stage = '', this.done = 0, this.total = 0});
  final String key;
  final JobLane lane;
  final JobPriority priority;
  final bool running;
  final String stage;
  final int done;
  final int total;

  JobInfo _with({bool? running, String? stage, int? done, int? total}) =>
      JobInfo(key: key, lane: lane, priority: priority, running: running ?? this.running, stage: stage ?? this.stage, done: done ?? this.done, total: total ?? this.total);
}

class _Job<T> {
  _Job(this.queue, this.info, this.work, this.order);
  final JobQueue queue;
  JobInfo info;
  final Future<T> Function(JobContext) work;
  final int order;
  final completer = Completer<T>();
  bool cancelled = false;

  Future<void> run() async {
    try {
      completer.complete(await work(JobContext._(this)));
    } catch (e, stack) {
      completer.completeError(e, stack);
    }
  }
}

/// The one queue for AI work and other long jobs: each [JobLane] runs at
/// most its limit at once, the most urgent first, and background jobs wait
/// while the computer saves power, runs on battery or plays a video that
/// already drops frames ([backgroundPaused]).
///
/// A job is known by its key: asking again for a job that is already
/// queued or running joins it rather than doing the work twice.
class JobQueue extends ChangeNotifier {
  JobQueue({bool Function()? backgroundPaused}) : backgroundPaused = backgroundPaused ?? (() => false);

  /// Whether background jobs should wait for now. Asked whenever a slot
  /// frees up and on [wake].
  final bool Function() backgroundPaused;

  final _waiting = <_Job<Object?>>[];
  final _running = <_Job<Object?>>[];
  final _byKey = HashMap<String, _Job<Object?>>();
  var _order = 0;
  var _disposed = false;

  /// The jobs queued and running, running first.
  List<JobInfo> get jobs => [for (final j in _running) j.info, for (final j in _waiting) j.info];

  /// The job known by [key], if queued or running.
  JobInfo? job(String key) => _byKey[key]?.info;

  /// Runs [work] as the job [key] once its lane has room, and answers what
  /// it answers. Throws [JobCancelled] when it is cancelled before it
  /// starts; a running job stops at its next [JobContext.checkCancelled].
  Future<T> run<T>(String key, Future<T> Function(JobContext job) work, {JobLane lane = JobLane.network, JobPriority priority = JobPriority.asked}) {
    // A job told to stop is not joined: the new request starts afresh.
    if (_byKey[key] case final same? when !same.cancelled) {
      return same.completer.future.then((value) => value as T);
    }
    final job = _Job<Object?>(this, JobInfo(key: key, lane: lane, priority: priority, running: false), (context) async => work(context), _order++);
    _byKey[key] = job;
    _waiting.add(job);
    _pump();
    return job.completer.future.then((value) => value as T);
  }

  /// Cancels the job [key]: a waiting one is dropped, a running one is
  /// told to stop.
  void cancel(String key) {
    final job = _byKey[key];
    if (job == null) return;
    job.cancelled = true;
    if (_waiting.remove(job)) {
      _byKey.remove(key);
      job.completer.completeError(const JobCancelled());
      _changed();
    }
  }

  /// Looks again whether background jobs may start, such as after the
  /// power cable was plugged in.
  void wake() => _pump();

  void _pump() {
    if (_disposed) return;
    var started = false;
    for (final lane in JobLane.values) {
      while (_running.where((j) => j.info.lane == lane).length < lane.limit) {
        final next = _next(lane);
        if (next == null) break;
        _waiting.remove(next);
        next.info = next.info._with(running: true);
        _running.add(next);
        started = true;
        unawaited(next.run().whenComplete(() => _finished(next)));
      }
    }
    if (started) _changed();
  }

  _Job<Object?>? _next(JobLane lane) {
    final paused = backgroundPaused();
    _Job<Object?>? best;
    for (final job in _waiting) {
      if (job.info.lane != lane || (paused && job.info.priority == JobPriority.background)) continue;
      if (best == null || job.info.priority.index < best.info.priority.index || (job.info.priority == best.info.priority && job.order < best.order)) best = job;
    }
    return best;
  }

  void _finished(_Job<Object?> job) {
    _running.remove(job);
    if (identical(_byKey[job.info.key], job)) _byKey.remove(job.info.key);
    logDebug(() => 'Job ${job.info.key} finished');
    _changed();
    _pump();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final job in [..._waiting, ..._running]) {
      job.cancelled = true;
    }
    for (final job in _waiting) {
      job.completer.completeError(const JobCancelled());
    }
    _waiting.clear();
    super.dispose();
  }
}
