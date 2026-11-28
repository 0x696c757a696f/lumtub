import 'subtitle_cues.dart';

/// 每句说完暂停: tells when playback reaches the end of a subtitle line.
/// The pause comes a moment before the line's end, as libmpv takes that
/// long to stop and the next line may start right where this one ends.
class LinePause {
  /// How long before a line's end playback pauses, at normal speed.
  static const lead = Duration(milliseconds: 120);

  /// A step longer than this between two positions is a seek, which never
  /// pauses: a jump past the end of a line skipped it on purpose.
  static const _seek = Duration(milliseconds: 1500);

  Duration? _last;

  /// Forgets the last position: after a seek, a new video or other lines.
  void reset() => _last = null;

  /// Whether playback, now at [position] after the last one observed,
  /// passed where the line playing at that last one pauses. [rate] is the
  /// playback speed, which brings the pause that much earlier.
  bool observe(List<SubtitleCue> lines, Duration position, {double rate = 1}) {
    final last = _last;
    _last = position;
    if (last == null || lines.isEmpty || position <= last) return false;
    final speed = rate.clamp(0.25, 4.0);
    if (position - last > _seek * speed) return false;
    final index = cueIndexAt(lines, last);
    if (index < 0) return false;
    final at = pauseAt(lines[index], rate: speed);
    return last < at && position >= at;
  }

  /// Where playback pauses for [line].
  static Duration pauseAt(SubtitleCue line, {double rate = 1}) {
    final at = line.end - lead * rate;
    return at > line.start ? at : line.start;
  }
}

/// The line to go to from [position] for 上一句 ([skip] -1), 重听这一句 (0)
/// or 下一句 (1): null when there is none. Between two lines, the one just
/// heard is "this line". A position a moment before a line's start counts
/// as that line, as replaying starts a little early.
int? lineToStep(List<SubtitleCue> lines, Duration position, int skip) {
  if (lines.isEmpty) return null;
  final current = cueIndexAt(lines, position + replayEarly * 2);
  final target = current < 0 ? 0 : current + skip.sign;
  if (target < 0) return 0;
  if (target >= lines.length) return null;
  return target;
}

/// How much before a line's start replaying it begins, so its first sound
/// is not cut off.
const replayEarly = Duration(milliseconds: 80);

/// Where playback goes to play [line] from its start.
Duration lineStart(SubtitleCue line) =>
    line.start > replayEarly ? line.start - replayEarly : Duration.zero;

/// 模糊翻译: whether the blurred second subtitle shows plainly now. It
/// shows while the pointer is over it, and from a tap or key until the
/// next line comes.
class TranslationReveal {
  bool _hover = false;
  bool _pressed = false;
  String _pressedOn = '';

  bool get shown => _hover || _pressed;

  /// The pointer went over the second subtitle or left it. True when
  /// [shown] changed.
  bool hover(bool over) {
    final was = shown;
    _hover = over;
    return shown != was;
  }

  /// A tap or key shows the second subtitle [showing], or hides it again.
  bool toggle(String showing) {
    final was = shown;
    _pressed = !shown;
    if (!_pressed) _hover = false;
    _pressedOn = _clean(showing);
    return shown != was;
  }

  /// The second subtitle shows [text] now: another line hides it again
  /// when a tap or key showed it. Blank text in between (the gap between
  /// two lines, or the same line's track swapped) does not count.
  bool lineChanged(String text) {
    final clean = _clean(text);
    if (!_pressed || clean.isEmpty || clean == _pressedOn) return false;
    if (_pressedOn.isEmpty) {
      _pressedOn = clean;
      return false;
    }
    _pressed = false;
    return !shown;
  }

  /// Back to blurred, for a new video.
  bool reset() {
    final was = shown;
    _hover = _pressed = false;
    _pressedOn = '';
    return was;
  }

  /// [text] without what follows a blank line: Lumtub's copy of a second
  /// subtitle for libmpv holds the main one's lines there, invisible.
  static String _clean(String text) => secondLines(text);
}

/// The second subtitle's own lines in [text] as libmpv reports them.
String secondLines(String text) {
  final lines = text.split('\n');
  final blank = lines.indexWhere(
      (l) => l.trim().isEmpty, lines.indexWhere((l) => l.trim().isNotEmpty).clamp(0, lines.length));
  return (blank < 0 ? lines : lines.sublist(0, blank)).join('\n').trim();
}
