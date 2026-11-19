import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

import 'native_core.dart';

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

/// Records one take of the person saying a line, into [folder], as a WAV
/// file that only stays on this device. A new take replaces the last one.
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

  /// The last take, once one was made.
  File? take;

  /// How long [take] is.
  Duration takeLength = Duration.zero;

  File get _file => File('${folder.path}${Platform.pathSeparator}take.wav');

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

  /// Stops recording and saves the take; null when nothing was heard.
  Future<File?> stop() async {
    if (!_recording) return null;
    _recording = false;
    _limit?.cancel();
    await folder.create(recursive: true);
    final file = _file;
    final seconds = await _microphone.stopInto(file);
    if (seconds == null || seconds < shortest) {
      if (await file.exists()) await file.delete();
      take = null;
      return null;
    }
    takeLength = Duration(milliseconds: (seconds * 1000).round());
    return take = file;
  }

  /// Stops without keeping anything, and lets go of the microphone.
  Future<void> dispose() async {
    _limit?.cancel();
    _recording = false;
    try {
      await _microphone.release();
    } catch (_) {}
    final file = take;
    take = null;
    if (file != null && await file.exists()) await file.delete();
  }
}
