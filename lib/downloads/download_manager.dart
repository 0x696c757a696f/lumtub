import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../app_directories.dart';
import '../app_log.dart';
import '../background_json.dart';
import '../friendly_error.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../process_priority.dart';
import '../sponsor_block.dart';
import '../video_codec.dart';
import 'download_models.dart';
import 'download_selection.dart';
import '../native_core.dart';
import '../user_folders.dart';

/// Per-call settings the manager reads when a download starts.
class DownloadOptions {
  const DownloadOptions({this.proxy, this.deno, this.cacheDirectory, this.subtitleLanguages, this.autoSubtitles = false, this.cutSponsors = false});
  /// yt-dlp's `--proxy` value, see `NetworkProxy.ytDlpValue`.
  final String? proxy;
  final String? deno;
  final String? cacheDirectory;
  /// yt-dlp's `--sub-langs`; null saves no subtitles.
  final String? subtitleLanguages;
  /// Also save automatic captions.
  final bool autoSubtitles;
  /// Leave the SponsorBlock segments out of joined files.
  final bool cutSponsors;
}

typedef ProcessStarter = Future<Process> Function(String executable, List<String> arguments, {Map<String, String>? environment});

/// Records live streams for the manager: lumtub_core fetching YouTube's
/// numbered fragments, with the addresses the app resolves.
abstract interface class LiveRecorder {
  /// Starts recording live [videoId] into the two [DownloadManager.recordFiles]
  /// of [stem]; the recording's id.
  Future<int> start(String videoId, String stem);

  /// How recording [id] goes; [renew] when an address expired.
  ({int bytes, bool running, bool renew, String? error}) state(int id);

  /// Brings recording [id] of [videoId] new addresses.
  Future<void> renew(int id, String videoId);

  /// Stops [id] once its files are written; why a stream failed, or null.
  Future<String?> stop(int id);
}

/// A downloaded video as playback finds it: the file and what the sidecar
/// `.info.json` and the neighbouring subtitle files hold.
class LocalVideo {
  LocalVideo(this.file, this.info, this.subtitles, this.segments);
  final File file;
  final Map<String, dynamic> info;
  final List<File> subtitles;
  final List<SkipSegment> segments;

  /// The subtitle file for the first of [languages] (such as `zh-Hans`)
  /// that has one, else the first file.
  File preferredSubtitle(List<String> languages) {
    for (final language in languages) {
      final match = subtitles.where((f) => f.path.toLowerCase().contains('.${language.trim().toLowerCase()}.')).firstOrNull;
      if (match != null) return match;
    }
    return subtitles.first;
  }

  /// The video codec of the file, from its sidecar; null when unknown.
  VideoCodec? get videoCodec => VideoCodec.of(info['vcodec']);

  /// The sidecar of [media]: the same name with `.info.json`.
  static File sidecarOf(String media) => File('${_base(media)}.info.json');

  static String _base(String media) {
    final dot = media.lastIndexOf('.');
    final slash = media.lastIndexOf(RegExp(r'[\\/]'));
    return dot > slash ? media.substring(0, dot) : media;
  }

  static LocalVideo read(File media) {
    var info = <String, dynamic>{};
    try {
      final data = jsonDecode(sidecarOf(media.path).readAsStringSync());
      if (data is Map<String, dynamic>) info = data;
    } catch (_) {
      // No sidecar: the file still plays.
    }
    final base = _base(media.path);
    final name = base.substring(base.lastIndexOf(RegExp(r'[\\/]')) + 1);
    final subtitles = <File>[];
    try {
      for (final entity in media.parent.listSync(followLinks: false)) {
        final file = entity.uri.pathSegments.last;
        if (entity is File && file.startsWith('$name.') && RegExp(r'\.(vtt|srt|ass)$').hasMatch(file)) subtitles.add(entity);
      }
    } on FileSystemException {
      // Played without subtitles.
    }
    subtitles.sort((a, b) => a.path.compareTo(b.path));
    // Downloads made before the rename keep their data under 'ytplus'.
    final raw = ((info['lumtub'] ?? info['ytplus']) as Map?)?['sponsorblock'];
    final segments = <SkipSegment>[
      if (raw is List)
        for (final s in raw.whereType<Map>())
          if (s['start'] is int && s['end'] is int) SkipSegment(Duration(milliseconds: s['start'] as int), Duration(milliseconds: s['end'] as int), '${s['category']}'),
    ];
    return LocalVideo(media, info, subtitles, segments);
  }
}

/// The download queue: runs up to [maxConcurrent] yt-dlp processes, keeps the
/// list in [file] and finds the downloaded files for playback.
class _NoList {
  const _NoList();
}

class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.file,
    required this.ytDlpPath,
    required String defaultDirectory,
    this.maxConcurrent = 2,
    ProcessStarter? start,
    this.environment,
    this.options,
    this.sponsorSegments,
    this.onFinished,
    this.join,
    this.cover,
    this.recorder,
  })  : _directory = defaultDirectory,
        _start = start ?? _backgroundStart;

  static Future<Process> _backgroundStart(String executable, List<String> arguments, {Map<String, String>? environment}) =>
      ProcessTree.start(executable, arguments, environment: environment, background: true);

  /// Where the list and the folder setting are saved.
  final File file;
  final String ytDlpPath;
  final int maxConcurrent;
  final ProcessStarter _start;
  final Map<String, String> Function()? environment;
  final DownloadOptions Function()? options;
  /// SponsorBlock segments to keep with a finished download.
  final Future<List<SkipSegment>> Function(String videoId)? sponsorSegments;
  /// Called once a download's file is complete.
  final void Function(DownloadTask task)? onFinished;
  /// Joins a picture and a sound file into one without ffmpeg; the path
  /// written, or why not.
  final Future<Joined> Function(JoinRequest request)? join;
  /// The cover picture (JPEG) of a video, to put inside a joined file.
  final Future<List<int>?> Function(String videoId)? cover;
  /// Records live streams; without it (or [join]) they cannot be saved.
  final LiveRecorder? recorder;

  /// Whether a live stream can be recorded.
  bool get canRecord => recorder != null && join != null;

  /// The picture and sound files a recording of [stem] writes.
  static List<String> recordFiles(String stem) => ['$stem.live-video.part', '$stem.live-audio.part'];

  /// Lives recorded at once; each holds a connection and writes all the
  /// time, so more wait their turn.
  static const maxRecordings = 3;

  /// Recordings under way: the task's id and the recording's.
  final _recordings = <String, int>{};
  /// The running [_record] calls, so [shutdown] can wait for them.
  final _recordTasks = <String, Future<void>>{};
  /// Set once [shutdown] or [dispose] began: recordings are stopped and
  /// their files kept as they are for the next start to join.
  bool _closing = false;

  String _directory;
  DownloadDefaults _defaults = const DownloadDefaults();
  final List<DownloadTask> tasks = [];
  final _active = <String>{};
  final _processes = <String, Process>{};
  final _stopping = <String>{};
  /// Stopped downloads whose files are deleted once the process has exited,
  /// since Windows will not delete a file yt-dlp still has open.
  final _wipe = <String>{};
  DateTime _notified = DateTime(0);

  /// Ticks with download progress, at most twice a second. The manager itself
  /// only notifies when a task is added, removed or changes status, so the
  /// rest of the app is not rebuilt by progress.
  final progress = ValueNotifier<int>(0);
  Timer? _saveTimer;

  /// Where new downloads are saved.
  String get directory => _directory;

  /// What the download dialog chose last, offered again next time.
  DownloadDefaults get defaults => _defaults;

  /// Whether video and audio streams can be joined into one file.
  bool get canMerge => join != null;

  /// Whether [task]'s picture and sound come as two files for [join].
  bool _joins(DownloadTask task) =>
      join != null && !(task.selection?.audioOnly ?? task.quality.audioOnly) && (task.selection?.needsMerge ?? true);

  /// The name yt-dlp gives each stream of a joined download, and what
  /// the joined file is called.
  static const _joinedPart = '%(title).80B [%(id)s].f%(format_id)s.%(ext)s';
  static final _partSuffix = RegExp(r'\.f[^.\\/]+\.[^.\\/]+$');

  /// The folder for downloads when none was chosen: Lumtub in the user's
  /// videos folder (Videos, or Movies on macOS).
  static String defaultDirectoryFor(Map<String, String> env, String fallback) {
    final videos = userFolder(UserFolder.videos, environment: env);
    return videos == null ? fallback : '$videos${Platform.pathSeparator}Lumtub';
  }

  // Persistence.

  Future<void> load() async {
    try {
      if (!await file.exists()) throw const _NoList();
      final data = jsonDecode(await file.readAsString());
      if (data is Map) {
        final dir = data['directory']?.toString();
        if (dir != null && dir.isNotEmpty) _directory = dir;
        _defaults = DownloadDefaults.fromJson(data['defaults']);
        for (final raw in data['tasks'] as List? ?? const []) {
          final task = DownloadTask.fromJson(raw);
          if (task == null) continue;
          // What the last run left half done continues.
          if (task.status == DownloadStatus.downloading) task.status = DownloadStatus.queued;
          tasks.add(task);
        }
      }
    } on _NoList {
      // No list yet: start empty.
    } catch (e) {
      await setBrokenFileAside(file, e);
    }
    notifyListeners();
    _pump();
  }

  Future<void> _saving = Future.value();

  /// Stops the live recordings, leaving their files for the next start to
  /// join, and waits a few seconds for them to settle; call before [dispose].
  Future<void> shutdown() async {
    _closing = true;
    final tasks = _recordTasks.values.toList();
    if (tasks.isEmpty) return;
    try {
      await Future.wait(tasks).timeout(const Duration(seconds: 5));
    } catch (e) {
      logWarn('Recordings did not settle before exit: $e');
    }
  }

  /// Completes when every change so far is written, including one still
  /// waiting for its delay.
  Future<void> flush() {
    if (_saveTimer?.isActive ?? false) unawaited(_save());
    return _saving;
  }

  /// Writes are queued so a later state never lands before an earlier one.
  Future<void> _save() {
    _saveTimer?.cancel();
    return _saving = _saving.then((_) => _write());
  }

  /// Saves after a second of quiet, so a burst of changes is one write.
  void _saveSoon() {
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(const Duration(seconds: 1), () => unawaited(_save()));
  }

  Future<void> _write() async {
    try {
      await writeFileAtomic(file, jsonEncode({'directory': _directory, 'defaults': _defaults.toJson(), 'tasks': tasks.map((t) => t.toJson()).toList()}));
    } on FileSystemException catch (e) {
      logError('Could not save the download list', e);
    }
  }

  Future<void> setDirectory(String path) async {
    _directory = path;
    notifyListeners();
    await _save();
  }

  Future<void> setDefaults(DownloadDefaults defaults) async {
    _defaults = defaults;
    await _save();
  }

  // Queue.

  DownloadTask? taskFor(String id) => tasks.where((t) => t.id == id).firstOrNull;

  /// Queues [item]; null when it is already downloaded or in the queue.
  DownloadTask? add(VideoItem item, DownloadQuality quality, {DownloadSelection? selection}) {
    final existing = taskFor(item.id);
    if (existing != null) {
      if (existing.status == DownloadStatus.done && existing.filePath != null && File(existing.filePath!).existsSync()) return null;
      if (existing.active || existing.status == DownloadStatus.paused) return null;
      tasks.remove(existing);
    }
    final task = DownloadTask(item: item, quality: quality, directory: _directory, selection: selection);
    tasks.insert(0, task);
    _changed();
    return task;
  }

  void pause(String id) {
    final task = taskFor(id);
    if (task == null || !task.active) return;
    task.status = DownloadStatus.paused;
    task.speed = null;
    _stop(id);
    _changed();
  }

  void resume(String id) {
    final task = taskFor(id);
    if (task == null || task.status != DownloadStatus.paused) return;
    task.status = DownloadStatus.queued;
    _changed();
  }

  /// Stops [id] and drops what was downloaded so far.
  void cancel(String id) {
    final task = taskFor(id);
    if (task == null || !(task.active || task.status == DownloadStatus.paused)) return;
    task.status = DownloadStatus.cancelled;
    task.speed = null;
    unawaited(_wipeAfterStop(task));
    _changed();
  }

  void retry(String id) {
    final task = taskFor(id);
    if (task == null || (task.status != DownloadStatus.failed && task.status != DownloadStatus.cancelled)) return;
    // A failed download resumes its .part file, so the bar keeps its place until new progress arrives; a cancelled one was wiped.
    if (task.status == DownloadStatus.cancelled) {
      task.downloaded = 0;
      task.total = null;
    }
    task.status = DownloadStatus.queued;
    task.error = null;
    _changed();
  }

  /// Removes [id] from the list, and its files from disk when [deleteFiles].
  Future<void> remove(String id, {bool deleteFiles = false}) async {
    final task = taskFor(id);
    if (task == null) return;
    tasks.remove(task);
    _stop(id);
    _changed();
    if (deleteFiles) await _wipeAfterStop(task);
  }

  Future<void> _wipeAfterStop(DownloadTask task) async {
    if (_active.contains(task.id)) {
      _stop(task.id);
      _wipe.add(task.id);
    } else {
      await _deleteFiles(task);
    }
  }

  void _stop(String id) {
    if (_active.contains(id) && (taskFor(id)?.item.isLive ?? false)) _stopping.add(id);
    final process = _processes[id];
    if (process == null) return;
    _stopping.add(id);
    process.kill();
  }

  void _changed() {
    notifyListeners();
    _saveSoon();
    _pump();
  }

  /// Whether a download or recording is running.
  bool get working => _active.isNotEmpty;

  int _held = 0;

  /// Runs [step] with no new task starting meanwhile, as while the cache
  /// they use is being cleared.
  Future<T> holding<T>(Future<T> Function() step) async {
    _held++;
    try {
      return await step();
    } finally {
      _held--;
      _pump();
    }
  }

  /// Starts queued tasks while there are free places.
  void _pump() {
    if (_held > 0) return;
    if (_closing) return;
    for (final task in tasks.reversed.toList()) {
      if (task.status != DownloadStatus.queued || _active.contains(task.id)) continue;
      // A recording runs as long as the live and takes no download's place;
      // recordings have their own limit.
      final live = task.item.isLive;
      if (!live && _active.length - _recordings.length >= maxConcurrent) continue;
      if (live && _recordTasks.length >= maxRecordings) continue;
      _active.add(task.id);
      task.status = DownloadStatus.downloading;
      if (live) {
        final id = task.id;
        _recordTasks[id] = _record(task).whenComplete(() {
          _recordTasks.remove(id);
          _pump();
        });
      } else {
        unawaited(_run(task));
      }
    }
  }

  /// yt-dlp's arguments for [task].
  List<String> arguments(DownloadTask task) {
    final o = options?.call() ?? const DownloadOptions();
    final selection = task.selection;
    final audio = selection?.audioOnly ?? task.quality.audioOnly;
    final joins = _joins(task);
    return [
      '--no-warnings',
      '--newline',
      '--progress',
      '--no-simulate',
      '--no-playlist',
      '--windows-filenames',
      '--extractor-retries', '3',
      '--retries', '10',
      '--fragment-retries', '10',
      if (o.cacheDirectory != null) ...['--cache-dir', o.cacheDirectory!],
      if (o.deno != null) ...['--js-runtimes', 'deno:${o.deno!}'],
      if (o.proxy != null) ...['--proxy', o.proxy!],
      '--paths', task.directory,
      '-o', joins ? _joinedPart : '%(title).80B [%(id)s].%(ext)s',
      // One sidecar and one set of subtitles for the joined file.
      if (joins) ...['-o', 'infojson:%(title).80B [%(id)s].%(ext)s', '-o', 'subtitle:%(title).80B [%(id)s].%(ext)s'],
      '--progress-template', DownloadProgress.progressTemplate,
      '--print', DownloadProgress.filePrint,
      '--write-info-json',
      '--format', joins ? selection?.joinFormat() ?? task.quality.joinFormat() : selection?.format() ?? task.quality.format(),
      // Files are kept as YouTube sends them, which the core reads; yt-dlp
      // never runs an ffmpeg it may find on PATH.
      '--fixup', 'never',
      if (!audio && o.subtitleLanguages != null) ...[
        '--write-subs',
        if (o.autoSubtitles) '--write-auto-subs',
        '--sub-langs', o.subtitleLanguages!,
        '--sub-format', 'vtt/best',
        '--sleep-subtitles', '1',
        // A subtitle YouTube refuses (429) is skipped, not the whole video.
        '--ignore-errors',
      ],
      '--', task.item.url,
    ];
  }

  /// Records live [task] until it ends or is stopped, then joins what was
  /// recorded. A task left recording when Lumtub closed has its files
  /// joined instead.
  Future<void> _record(DownloadTask task) async {
    final id = task.id;
    final recorder = this.recorder;
    if (recorder == null || join == null) {
      task.status = DownloadStatus.failed;
      task.error = tr('Live streams cannot be downloaded');
      _active.remove(id);
      _changed();
      return;
    }
    var stem = task.filePath;
    final earlier = stem != null && File(recordFiles(stem).first).existsSync();
    String? error;
    if (!earlier) {
      final now = DateTime.now();
      String two(int n) => '$n'.padLeft(2, '0');
      final title = task.item.title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').replaceAll(RegExp(r'\s+'), ' ').trim();
      final short = title.length > 80 ? title.substring(0, 80).trim() : title;
      stem = '${task.directory}${Platform.pathSeparator}$short [$id] ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}-${two(now.minute)}';
      task.filePath = stem;
      _saveSoon();
      try {
        await Directory(task.directory).create(recursive: true);
        _recordings[id] = await recorder.start(id, stem);
      } catch (e) {
        error = friendlyFileError(e);
      }
      final recording = _recordings[id];
      if (recording != null) {
        var renewing = false;
        var last = (bytes: 0, at: DateTime.now());
        while (!_stopping.contains(id) && !_closing) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (_closing) break;
          final state = recorder.state(recording);
          final now = DateTime.now();
          final seconds = now.difference(last.at).inMilliseconds / 1000;
          task.downloaded = state.bytes;
          task.speed = seconds > 0 ? (state.bytes - last.bytes) / seconds : null;
          last = (bytes: state.bytes, at: now);
          progress.value++;
          if (!state.running) {
            error = state.error;
            break;
          }
          if (state.renew && !renewing) {
            renewing = true;
            unawaited(recorder.renew(recording, id).catchError((Object e) => logWarn('Recording $id: no new address: $e')).whenComplete(() => renewing = false));
          }
        }
        if (_recordings.remove(id) != null) error = await recorder.stop(recording) ?? error;
      }
    }
    if (_closing) {
      _active.remove(id);
      return;
    }
    final stopped = _stopping.remove(id);
    task.speed = null;
    if (_wipe.remove(id)) {
      await _deleteFiles(task);
    } else if (task.status != DownloadStatus.cancelled) {
      final files = recordFiles(stem);
      final recorded = files.every((f) => File(f).existsSync() && File(f).lengthSync() > 0);
      if (!recorded) {
        task.status = DownloadStatus.failed;
        task.error = error ?? tr('The downloaded file was not found');
      } else {
        if (error != null) logWarn('Recording $id stopped: $error');
        await _finishRecording(task, stem, files);
      }
    }
    if (stopped && task.status == DownloadStatus.paused) task.status = DownloadStatus.done;
    _active.remove(id);
    _changed();
  }

  Future<void> _finishRecording(DownloadTask task, String stem, List<String> files) async {
    task.status = DownloadStatus.downloading;
    task.finishing = true;
    _changed();
    File? coverFile;
    try {
      final bytes = await cover?.call(task.id);
      if (bytes != null) coverFile = await File('$stem.cover.jpg').writeAsBytes(bytes);
    } catch (e) {
      logWarn('No cover for ${task.id} inside the file: $e');
    }
    final joined = await join!(JoinRequest(video: files[0], audio: files[1], stem: stem, title: task.item.title, cover: coverFile?.path));
    task.finishing = false;
    try {
      await coverFile?.delete();
    } on FileSystemException {
      // Left for the user.
    }
    final out = joined.path;
    if (out == null) {
      task.status = DownloadStatus.failed;
      task.error = joined.error ?? tr('The downloaded file was not found');
      return;
    }
    for (final part in files) {
      try {
        await File(part).delete();
      } on FileSystemException {
        // Left for the user.
      }
    }
    // Played from the file now, not as the live it was.
    task.item = task.item.withLiveStatus('was_live');
    try {
      await LocalVideo.sidecarOf(out).writeAsString(jsonEncode({
        'id': task.id,
        'title': task.item.title,
        'channel': task.item.channel,
        'webpage_url': task.item.url,
        'was_live': true,
      }), flush: true);
    } catch (e) {
      logError('Could not save the offline info of ${task.id}', e);
    }
    task.filePath = out;
    task.total = task.downloaded = File(out).lengthSync();
    task.status = DownloadStatus.done;
    onFinished?.call(task);
  }

  Future<void> _run(DownloadTask task) async {
    final id = task.id;
    final printed = <String>[];
    final errors = <String>[];
    String? shown;
    int exitCode;
    try {
      await Directory(task.directory).create(recursive: true);
      final env = {
        ...?environment?.call(),
        // So that titles in the printed path survive the pipe on Windows.
        'PYTHONUTF8': '1',
        'PYTHONIOENCODING': 'utf-8',
      };
      final process = await _start(ytDlpPath, arguments(task), environment: env);
      _processes[id] = process;
      lowerPriority(process.pid);
      // A pause that came while the process was starting.
      if (task.status != DownloadStatus.downloading) _stop(id);
      void line(String text) {
        final progress = DownloadProgress.parse(text);
        if (progress != null) {
          _progress(task, progress);
          return;
        }
        final path = DownloadProgress.parseFile(text);
        if (path != null) {
          printed.add(path);
        } else if (text.trim().isNotEmpty) {
          errors.add(text.trim());
          if (errors.length > 20) errors.removeAt(0);
        }
      }

      final decoder = const Utf8Decoder(allowMalformed: true);
      final done = [
        process.stdout.transform(decoder).transform(const LineSplitter()).forEach(line),
        process.stderr.transform(decoder).transform(const LineSplitter()).forEach(line),
      ];
      exitCode = await process.exitCode;
      await Future.wait(done);
    } catch (e) {
      if (e is FileSystemException) {
        shown = friendlyFileError(e);
      } else {
        errors.add('$e');
      }
      exitCode = -1;
    }
    _processes.remove(id);
    if (_stopping.remove(id)) {
      // Paused, cancelled or removed: the status was set by the caller.
    } else if (exitCode == 0) {
      await _finish(task, printed);
    } else {
      task.status = DownloadStatus.failed;
      task.speed = null;
      final raw = errors.lastWhere((e) => e.startsWith('ERROR'), orElse: () => errors.isEmpty ? 'yt-dlp exited with code $exitCode' : errors.last);
      task.error = shown ?? friendlyDownloadError(raw);
    }
    if (_wipe.remove(id)) await _deleteFiles(task);
    _active.remove(id);
    _changed();
  }

  void _progress(DownloadTask task, DownloadProgress p) {
    task.downloaded = p.downloaded;
    task.total = p.total;
    task.speed = p.speed;
    task.eta = p.eta;
    // Twice a second is plenty for the page.
    final now = DateTime.now();
    if (p.finished || now.difference(_notified) >= const Duration(milliseconds: 500)) {
      _notified = now;
      progress.value++;
    }
  }

  Future<void> _finish(DownloadTask task, List<String> printed) async {
    var path = printed.lastOrNull;
    List<SkipSegment>? segments;
    var cut = const <(Duration, Duration)>[];
    if (_joins(task) && printed.length >= 2) {
      if (options?.call().cutSponsors ?? false) segments = await _segments(task);
      final stem = printed.first.replaceFirst(_partSuffix, '');
      final container = task.selection?.container.name ?? 'auto';
      File? coverFile;
      if (container != 'webm') {
        try {
          final bytes = await cover?.call(task.id);
          if (bytes != null) coverFile = await File('$stem.cover.jpg').writeAsBytes(bytes);
        } catch (e) {
          logWarn('No cover for ${task.id} inside the file: $e');
        }
      }
      final joined = await join!(JoinRequest(
        video: printed.first,
        audio: printed.last,
        stem: stem,
        container: container,
        subtitles: await subtitleFilesOf(stem),
        title: task.item.title,
        cover: coverFile?.path,
        cut: [for (final s in segments ?? const <SkipSegment>[]) (s.start, s.end)],
      ));
      try {
        await coverFile?.delete();
      } on FileSystemException {
        // Left for the user.
      }
      final out = joined.path;
      if (out == null) {
        task.status = DownloadStatus.failed;
        task.speed = null;
        task.error = joined.error ?? tr('The downloaded file was not found');
        return;
      }
      for (final part in printed) {
        try {
          await File(part).delete();
        } on FileSystemException {
          // Left for the user.
        }
      }
      path = out;
      cut = joined.cut;
    }
    if (path == null || !await File(path).exists()) path = await _findMedia(task);
    if (path == null) {
      task.status = DownloadStatus.failed;
      task.error = tr('The downloaded file was not found');
      return;
    }
    task.filePath = path;
    task.status = DownloadStatus.done;
    task.speed = null;
    task.eta = null;
    task.downloaded = task.total ?? task.downloaded;
    try {
      await _writeSidecar(task, path, segments ?? await _segments(task), cut);
    } catch (e) {
      logError('Could not save the offline info of ${task.id}', e);
    }
    onFinished?.call(task);
  }

  /// The subtitle files yt-dlp saved beside [stem] (`stem.en.vtt`), each
  /// with its language.
  static Future<List<({String path, String language})>> subtitleFilesOf(String stem) async {
    final file = File(stem);
    final name = file.uri.pathSegments.last;
    final found = <({String path, String language})>[];
    try {
      await for (final entity in file.parent.list()) {
        final other = entity.uri.pathSegments.last;
        if (entity is! File || !other.startsWith('$name.')) continue;
        final match = RegExp(r'^\.([A-Za-z0-9_-]+)\.(vtt|srt)$').firstMatch(other.substring(name.length));
        if (match != null) found.add((path: entity.path, language: match[1]!.replaceFirst(RegExp(r'-orig$'), '')));
      }
    } on FileSystemException {
      // None then.
    }
    found.sort((a, b) => a.path.compareTo(b.path));
    return found;
  }

  static const _sidecarKeys = [
    'id', 'title', 'channel', 'uploader', 'channel_url', 'channel_id', 'upload_date', 'view_count', 'like_count', 'description', 'duration', 'chapters', 'webpage_url', 'vcodec',
  ];

  Future<List<SkipSegment>> _segments(DownloadTask task) async {
    try {
      return await sponsorSegments?.call(task.id) ?? const [];
    } catch (_) {
      // Nothing skipped or cut then.
      return const [];
    }
  }

  /// Cuts yt-dlp's `.info.json` down to what the watch page shows (its
  /// format list is large and its addresses expire) and adds the
  /// SponsorBlock segments, so playback can restore both offline. Times
  /// are moved past the stretches [cut] out of the file, and segments
  /// wholly cut are left out.
  Future<void> _writeSidecar(DownloadTask task, String media, List<SkipSegment> segments, List<(Duration, Duration)> cut) async {
    final sidecar = LocalVideo.sidecarOf(media);
    var full = <String, dynamic>{};
    if (sidecar.existsSync()) {
      final data = await decodeJsonInBackground(await sidecar.readAsString());
      if (data is Map<String, dynamic>) full = data;
    }
    final kept = <Map<String, Object>>[];
    for (final s in segments) {
      final start = shiftPastCuts(s.start, cut), end = shiftPastCuts(s.end, cut);
      if (end > start) kept.add({'start': start.inMilliseconds, 'end': end.inMilliseconds, 'category': s.category});
    }
    await sidecar.writeAsString(jsonEncode({
      for (final key in _sidecarKeys)
        if (full[key] != null) key: key == 'chapters' && cut.isNotEmpty ? shiftChapters(full[key], cut) : key == 'duration' && cut.isNotEmpty && full[key] is num ? _shiftSeconds(full[key] as num, cut) : full[key],
      'lumtub': {'sponsorblock': kept},
    }), flush: true);
  }

  /// Where [at] lands once the stretches [cut] (in order) are left out: a
  /// time inside one lands where it starts.
  static Duration shiftPastCuts(Duration at, List<(Duration, Duration)> cut) {
    var shifted = at;
    for (final (from, to) in cut) {
      if (at >= to) {
        shifted -= to - from;
      } else if (at > from) {
        shifted -= at - from;
      }
    }
    return shifted;
  }

  static double _shiftSeconds(num seconds, List<(Duration, Duration)> cut) =>
      shiftPastCuts(Duration(milliseconds: (seconds * 1000).round()), cut).inMilliseconds / 1000;

  /// yt-dlp's chapter list moved past [cut]; chapters wholly cut are left out.
  static Object? shiftChapters(Object? chapters, List<(Duration, Duration)> cut) {
    if (chapters is! List) return chapters;
    return [
      for (final c in chapters.whereType<Map>())
        if (c['start_time'] is num && c['end_time'] is num)
          if ((_shiftSeconds(c['start_time'] as num, cut), _shiftSeconds(c['end_time'] as num, cut)) case (final start, final end) when end > start) {...c, 'start_time': start, 'end_time': end},
    ];
  }

  /// The media file of [task] in its folder, by the `[id]` in its name.
  Future<String?> _findMedia(DownloadTask task) async {
    try {
      await for (final entity in Directory(task.directory).list(followLinks: false)) {
        final name = entity.uri.pathSegments.last;
        if (entity is File && name.contains('[${task.id}]') && RegExp(r'\.(mp4|m4a|webm|mkv|mp3|opus)$').hasMatch(name)) return entity.path;
      }
    } on FileSystemException {
      // Not found.
    }
    return null;
  }

  /// Every file Lumtub wrote for [task]: the video, partial data, sidecar
  /// and subtitles, which all carry the video id in their name.
  Future<void> _deleteFiles(DownloadTask task) async {
    try {
      final dir = Directory(task.directory);
      if (!await dir.exists()) return;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && entity.uri.pathSegments.last.contains('[${task.id}]')) {
          try {
            await entity.delete();
          } on FileSystemException {
            // Still in use; left for the user.
          }
        }
      }
    } on FileSystemException {
      // Nothing to delete.
    }
  }

  // Playback.

  /// The downloaded [id] when its file is still there.
  Future<LocalVideo?> localVideo(String id) async {
    final task = taskFor(id);
    final path = task?.filePath;
    if (task == null || task.status != DownloadStatus.done || path == null) return null;
    final media = File(path);
    if (!await media.exists()) return null;
    // One play asks several times; the files do not change in between.
    final recent = _recentLocal;
    if (recent != null && recent.path == path && DateTime.now().difference(recent.at) < const Duration(seconds: 10)) return recent.video;
    // The sidecar and the folder listing are read away from the UI isolate.
    final video = Isolate.run(() => LocalVideo.read(media));
    _recentLocal = (path: path, at: DateTime.now(), video: video);
    return video;
  }

  ({String path, DateTime at, Future<LocalVideo> video})? _recentLocal;

  @override
  void dispose() {
    _closing = true;
    final recorder = this.recorder;
    for (final recording in _recordings.values) {
      if (recorder != null) unawaited(recorder.stop(recording).then<void>((_) {}, onError: (Object e) => logWarn('A recording did not stop: $e')));
    }
    _recordings.clear();
    for (final process in _processes.values) {
      process.kill();
    }
    _saveTimer?.cancel();
    progress.dispose();
    super.dispose();
  }
}

/// A picture and a sound file for the core to join, and what goes inside
/// besides.
class JoinRequest {
  const JoinRequest({required this.video, required this.audio, required this.stem, this.container = 'auto', this.subtitles = const [], this.title, this.cover, this.cut = const []});
  final String video;
  final String audio;
  /// The joined file's path without its extension.
  final String stem;
  /// mp4, webm, mkv, or `auto` for the one that fits the streams.
  final String container;
  final List<({String path, String language})> subtitles;
  final String? title;
  /// A JPEG file.
  final String? cover;
  /// Stretches to leave out; the core narrows each to keyframes inside it.
  final List<(Duration, Duration)> cut;

  Map<String, Object?> toJson() => {
        'video': video,
        'audio': audio,
        'out': stem,
        'container': container,
        'subtitles': [for (final s in subtitles) {'path': s.path, 'language': s.language}],
        if (title != null) 'title': title,
        if (cover != null) 'cover': cover,
        if (cut.isNotEmpty) 'cut': [for (final (from, to) in cut) [from.inMilliseconds / 1000, to.inMilliseconds / 1000]],
      };
}
