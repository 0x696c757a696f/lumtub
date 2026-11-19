import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';

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
  Future<bool> allowed();
  Future<Stream<Uint8List>> start({required int sampleRate});
  Future<void> stop();
  Future<void> dispose();
}

/// The record package's recorder, as 16-bit PCM in one channel: every
/// platform can stream that without an encoder (Linux would need ffmpeg
/// for a file).
class RecordMicrophone implements Microphone {
  RecordMicrophone({this.mixWithOthers = false});

  /// The 与其他应用混音 setting, which the audio session goes back to.
  bool mixWithOthers;
  AudioRecorder? _recorder;
  AudioRecorder get _mic => _recorder ??= AudioRecorder();

  @override
  Future<bool> allowed() => _mic.hasPermission();

  @override
  Future<Stream<Uint8List>> start({required int sampleRate}) =>
      _mic.startStream(RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: sampleRate, numChannels: 1, echoCancel: true, noiseSuppress: true));

  @override
  Future<void> stop() async {
    final recorder = _recorder;
    if (recorder == null) return;
    await recorder.stop();
    // Recording left iOS's audio session for calls (the receiver, the
    // silent switch); videos play as before again.
    if (Platform.isIOS) {
      await recorder.ios?.setAudioSessionCategory(category: IosAudioCategory.playback, options: [if (mixWithOthers) IosAudioCategoryOptions.mixWithOthers]);
    }
  }

  @override
  Future<void> dispose() async {
    final recorder = _recorder;
    _recorder = null;
    await recorder?.dispose();
  }
}

/// Records one take of the person saying a line, into [folder], as a WAV
/// file that only stays on this device. A new take replaces the last one.
class Shadowing {
  Shadowing(this.folder, {Microphone? microphone}) : _microphone = microphone ?? RecordMicrophone();

  static const sampleRate = 44100;
  /// The longest take kept: a forgotten recording stops by itself.
  static const longest = Duration(minutes: 2);

  final Directory folder;
  final Microphone _microphone;
  StreamSubscription<Uint8List>? _listening;
  final _bytes = BytesBuilder(copy: false);
  Timer? _limit;
  Completer<void>? _ended;

  bool get recording => _listening != null;

  /// The last take, once one was made.
  File? take;

  /// Starts recording; [onTooLong] is told when [longest] stops it.
  Future<void> start({void Function()? onTooLong}) async {
    if (recording) return;
    if (!await _microphone.allowed()) throw const ShadowException(denied: true);
    final Stream<Uint8List> stream;
    try {
      stream = await _microphone.start(sampleRate: sampleRate);
    } catch (e) {
      throw ShadowException(detail: '$e');
    }
    _bytes.clear();
    final ended = _ended = Completer<void>();
    _listening = stream.listen(_bytes.add, onDone: () {
      if (!ended.isCompleted) ended.complete();
    }, onError: (Object _) {
      if (!ended.isCompleted) ended.complete();
    });
    _limit = Timer(longest, () => onTooLong?.call());
  }

  /// Stops recording and saves the take; null when nothing was heard.
  Future<File?> stop() async {
    final listening = _listening;
    if (listening == null) return null;
    _limit?.cancel();
    try {
      await _microphone.stop();
      // The last bytes come before the stream ends.
      await _ended?.future.timeout(const Duration(seconds: 1), onTimeout: () {});
    } finally {
      await listening.cancel();
      _listening = null;
    }
    final pcm = _bytes.takeBytes();
    if (pcm.length < sampleRate ~/ 10) return null;
    await folder.create(recursive: true);
    final file = File('${folder.path}${Platform.pathSeparator}take.wav');
    await file.writeAsBytes(wavBytes(pcm, sampleRate: sampleRate), flush: true);
    return take = file;
  }

  /// Stops without keeping anything, and lets go of the microphone.
  Future<void> dispose() async {
    _limit?.cancel();
    await _listening?.cancel();
    _listening = null;
    try {
      await _microphone.stop();
    } catch (_) {}
    await _microphone.dispose();
    final file = take;
    take = null;
    if (file != null && await file.exists()) await file.delete();
  }
}

/// [pcm], 16-bit little-endian samples, as a WAV file.
Uint8List wavBytes(Uint8List pcm, {required int sampleRate, int channels = 1}) {
  final length = pcm.length - pcm.length % 2;
  final header = ByteData(44);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      header.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * channels * 2, Endian.little);
  header.setUint16(32, channels * 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(Uint8List.sublistView(pcm, 0, length)))
      .takeBytes();
}
