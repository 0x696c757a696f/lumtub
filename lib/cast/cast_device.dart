import 'cast_subtitles.dart';

/// What a TV or speaker is asked to play.
class CastMedia {
  const CastMedia({required this.url, required this.title, this.mime = 'video/mp4', this.start = Duration.zero, this.offset = Duration.zero, this.duration, this.restart, this.subtitles});
  final String url;
  final String title;
  final String mime;
  final Duration start;

  /// Where in the video the stream begins, for a stream the app joins
  /// itself: the device counts its position from there.
  final Duration offset;

  /// The video's length, when the device cannot tell it from the stream.
  final Duration? duration;

  /// The same video streamed from another position, for a stream the
  /// device cannot seek in itself.
  final Future<CastMedia> Function(Duration at)? restart;

  /// The subtitles shown when the cast began, timed to this stream.
  final CastSubtitles? subtitles;
}

enum CastState { loading, playing, paused, stopped }

/// What a device reports about the playback it was given.
class CastStatus {
  const CastStatus({required this.state, this.position = Duration.zero, this.duration = Duration.zero});
  final CastState state;
  final Duration position;
  final Duration duration;
}

enum CastProtocol { dlna, chromecast, airplay }

/// A device that plays an address it is handed, whichever protocol it speaks.
/// Failures are thrown as [CastException] with a short message.
abstract class CastDevice {
  String get id;
  String get name;
  CastProtocol get protocol;

  /// The device's address and a port it listens on, to find which of this
  /// computer's addresses reaches it.
  String get host;
  int get port;

  /// Starts [media] at [CastMedia.start].
  Future<void> load(CastMedia media);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// Stops playback and lets go of the device.
  Future<void> stop();

  /// The current state, or null when the device did not answer.
  Future<CastStatus?> status();

  /// Drops connections without stopping playback.
  Future<void> close();
}

class CastException implements Exception {
  const CastException(this.message);
  final String message;
  @override
  String toString() => message;
}
