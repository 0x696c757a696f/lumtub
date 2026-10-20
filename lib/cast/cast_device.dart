/// What a TV or speaker is asked to play.
class CastMedia {
  const CastMedia({required this.url, required this.title, this.mime = 'video/mp4', this.start = Duration.zero});
  final String url;
  final String title;
  final String mime;
  final Duration start;
}

enum CastState { loading, playing, paused, stopped }

/// What a device reports about the playback it was given.
class CastStatus {
  const CastStatus({required this.state, this.position = Duration.zero, this.duration = Duration.zero});
  final CastState state;
  final Duration position;
  final Duration duration;
}

enum CastProtocol { dlna, chromecast }

/// A device that plays an address it is handed, whichever protocol it speaks.
/// Failures are thrown as [CastException] with a short message.
abstract class CastDevice {
  String get id;
  String get name;
  CastProtocol get protocol;

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
