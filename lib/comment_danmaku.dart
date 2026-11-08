import 'live_chat.dart';
import 'youtube_comments.dart';

/// A moment of the video written in a comment: `1:23` or `1:02:03`.
final _moment = RegExp(r'(?<![\d:.])(?:(\d{1,2}):)?(\d{1,2}):(\d{2})(?![\d:])');

/// Separators left at the start of a line once its moment is taken off,
/// as in `0:00 - Intro`.
final _lead = RegExp(r'^[\s\-–—:|·•.)\]]+');

/// Longest line flown, in characters.
const _longest = 80;

/// The moment [match] names, or null when it is not a time (`25:99`).
Duration? _time(RegExpMatch match) {
  final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
  final minutes = int.parse(match.group(2)!);
  final seconds = int.parse(match.group(3)!);
  if (seconds >= 60 || (match.group(1) != null && minutes >= 60)) return null;
  return Duration(hours: hours, minutes: minutes, seconds: seconds);
}

/// The lines of [comments] that name a moment of the video, as bullet chat
/// flying at that moment, the way 弹幕 replay a recorded chat. A line that
/// starts with its moment flies without it (`3:45 this part` → `this part`);
/// one with it inside flies whole. A comment naming more than three moments
/// is a list of chapters and is left out, as is a moment past [length].
List<LiveChatMessage> timedComments(Iterable<YoutubeComment> comments, {Duration? length}) {
  final found = <LiveChatMessage>[];
  for (final comment in comments) {
    final lines = <(Duration, String)>[];
    for (final line in comment.text.split('\n')) {
      final match = _moment.firstMatch(line);
      if (match == null) continue;
      final at = _time(match);
      if (at == null || (length != null && length > Duration.zero && at > length)) continue;
      var text = line.trim();
      if (line.substring(0, match.start).trim().isEmpty) text = line.substring(match.end).replaceFirst(_lead, '').trim();
      if (text.isEmpty) continue;
      if (text.runes.length > _longest) text = '${String.fromCharCodes(text.runes.take(_longest - 1))}…';
      lines.add((at, text));
    }
    if (lines.isEmpty || lines.length > 3) continue;
    for (final (i, (at, text)) in lines.indexed) {
      found.add(LiveChatMessage(
        id: 'comment:${comment.id}:$i',
        kind: LiveChatKind.message,
        text: text,
        offset: at,
        author: comment.author,
        authorChannelId: comment.channelId,
        authorAvatar: comment.avatar,
        emojis: comment.emojis,
      ));
    }
  }
  found.sort((a, b) => a.offset!.compareTo(b.offset!));
  return found;
}
