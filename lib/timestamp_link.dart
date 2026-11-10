/// A youtu.be link to [videoId] that starts at [position], or null for a
/// live stream, a position at the very start or an id that is not a YouTube
/// video's.
String? timestampLink(String videoId, Duration position, {bool live = false}) {
  final seconds = position.inSeconds;
  if (live || seconds <= 0 || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) return null;
  return 'https://youtu.be/$videoId?t=$seconds';
}
