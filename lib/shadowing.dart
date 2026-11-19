import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

import 'native_core.dart';
import 'subtitle_cues.dart';

/// 跟读录音: what the shadowing is doing now.
enum ShadowStage { idle, recording, original, mine }

/// Why recording could not start.
class ShadowException implements Exception {
  const ShadowException({this.denied = false, this.detail = ''});
  final bool denied;
  final String detail;

  @override
  String toString() => denied ? 'Microphone access denied' : 'Could not record: $detail';
}

/// The microphone, behind what [Shadowing] needs of it, so tests can
/// stand in for it.
abstract class Microphone {
  /// Asks to record; false when the person or the system said no.
  Future<bool> allowed();
  Future<void> start();

  /// Stops and writes what was heard to [file] as WAV: its length in
  /// seconds, or null when nothing was heard.
  Future<double?> stopInto(File file);

  /// Lets go of the microphone once no more takes come.
  Future<void> release();
}

/// The Rust core's microphone (native/lumtub_core/src/mic.rs), the same
/// on every platform. Android and iOS ask for it through the shell first;
/// iOS also moves its audio session to one that records, and back.
class CoreMicrophone implements Microphone {
  CoreMicrophone({this.mixWithOthers = false});

  /// The 与其他应用混音 setting, which iOS's audio session goes back to.
  bool mixWithOthers;
  static const _shell = MethodChannel('lumtub/windows_shell');
  static bool get _asks => Platform.isAndroid || Platform.isIOS;

  @override
  Future<bool> allowed() async {
    if (!_asks) return true;
    return await _shell.invokeMethod<bool>('microphone', {'on': true, 'mix': mixWithOthers}) ?? false;
  }

  @override
  Future<void> start() async {
    final error = await Isolate.run(NativeCore.micStart);
    if (error != null) throw ShadowException(detail: error);
  }

  @override
  Future<double?> stopInto(File file) async {
    final path = file.path;
    final answer = await Isolate.run(() => NativeCore.micStop(path));
    await _done();
    if (answer.error != null) throw ShadowException(detail: answer.error!);
    return answer.seconds;
  }

  @override
  Future<void> release() async {
    final path = '${Directory.systemTemp.path}${Platform.pathSeparator}lumtub-discarded-take.wav';
    final answer = await Isolate.run(() => NativeCore.micStop(path));
    if (answer.seconds != null) await File(path).delete().catchError((Object _) => File(path));
    await _done();
  }

  Future<void> _done() async {
    if (!Platform.isIOS) return;
    await _shell.invokeMethod<bool>('microphone', {'on': false, 'mix': mixWithOthers}).catchError((Object _) => false);
  }
}

/// One take of a line, and once read from the video's cache, the line as
/// the video says it.
class ShadowTake {
  ShadowTake(this.line, this.file, this.length);
  final SubtitleCue line;
  final File file;
  final Duration length;

  /// The video's sound around the line; its last [originalSeconds] are the
  /// line.
  File? original;
  double originalSeconds = 0;

  /// What the core joins for this line (NativeCore.micJoin).
  Map<String, Object> get part => {if (original != null) 'original': original!.path, 'seconds': originalSeconds, 'take': file.path};
}

/// Records the person saying lines, into [folder], as WAV files that only
/// stay on this device: one take for each line, the newest kept.
class Shadowing {
  Shadowing(this.folder, {Microphone? microphone}) : _microphone = microphone ?? CoreMicrophone();

  /// The longest take kept: a forgotten recording stops by itself.
  static const longest = Duration(minutes: 2);

  /// Shorter than this, a take is a slip of the key and is not kept.
  static const shortest = 0.1;

  final Directory folder;
  final Microphone _microphone;
  Timer? _limit;
  bool _recording = false;

  bool get recording => _recording;

  /// The takes, by the start of their line.
  final takes = <Duration, ShadowTake>{};

  /// The take made last.
  ShadowTake? last;

  /// The takes in the order of their lines.
  List<ShadowTake> get inOrder => takes.values.toList()..sort((a, b) => a.line.start.compareTo(b.line.start));

  File fileFor(SubtitleCue line, String kind, String extension) => File('${folder.path}${Platform.pathSeparator}$kind-${line.start.inMilliseconds}.$extension');

  /// Starts recording; [onTooLong] is told when [longest] stops it.
  Future<void> start({void Function()? onTooLong}) async {
    if (_recording) return;
    if (!await _microphone.allowed()) throw const ShadowException(denied: true);
    try {
      await _microphone.start();
    } on ShadowException {
      rethrow;
    } catch (e) {
      throw ShadowException(detail: '$e');
    }
    _recording = true;
    _limit = Timer(longest, () => onTooLong?.call());
  }

  /// Stops recording and keeps the take of [line], in place of any earlier
  /// one; null when nothing was heard.
  Future<ShadowTake?> stop(SubtitleCue line) async {
    if (!_recording) return null;
    _recording = false;
    _limit?.cancel();
    await folder.create(recursive: true);
    // A take too short to keep must not replace the line's last one.
    final heard = File('${folder.path}${Platform.pathSeparator}recording.wav');
    final seconds = await _microphone.stopInto(heard);
    if (seconds == null || seconds < shortest) {
      if (await heard.exists()) await heard.delete();
      return null;
    }
    final file = await heard.rename(fileFor(line, 'take', 'wav').path);
    final take = ShadowTake(line, file, Duration(milliseconds: (seconds * 1000).round()));
    take.original = takes[line.start]?.original;
    take.originalSeconds = takes[line.start]?.originalSeconds ?? 0;
    return last = takes[line.start] = take;
  }

  /// Stops without keeping anything, lets go of the microphone and deletes
  /// every take.
  Future<void> dispose() async {
    _limit?.cancel();
    _recording = false;
    try {
      await _microphone.release();
    } catch (_) {}
    takes.clear();
    last = null;
    if (await folder.exists()) await folder.delete(recursive: true);
  }
}

/// What saving a take writes: the take, the line and then the take, or
/// every line recorded so far, each followed by its take.
enum ShadowExport { mine, withLine, all }
