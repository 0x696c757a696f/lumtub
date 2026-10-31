import 'dart:convert';

import 'native_core.dart';

/// One line of a subtitle track with its time span.
typedef SubtitleCue = ({Duration start, Duration end, String text});

final _timing = RegExp(r'^\s*((?:\d+:)?\d{1,2}:\d{2}[.,]\d{1,3})\s+-->\s+((?:\d+:)?\d{1,2}:\d{2}[.,]\d{1,3})');
final _tag = RegExp(r'<[^>]*>|\{\\[^}]*\}');

/// The cues of a WebVTT or SRT file, in time order, each on one line.
/// Automatic captions repeat the line before as the first line of the next
/// cue; only new lines stay. Other formats give none. The native core
/// parses when it is there.
List<SubtitleCue> parseSubtitleCues(String text) {
  final core = NativeCore.instance;
  final json = core?.take(core.withText(text, core.subtitleCues));
  if (json != null) {
    return [
      for (final cue in jsonDecode(json) as List)
        if (cue case [final int start, final int end, final String line]) (start: Duration(milliseconds: start), end: Duration(milliseconds: end), text: line),
    ];
  }
  return dartSubtitleCues(text);
}

/// [parseSubtitleCues] without the native core.
List<SubtitleCue> dartSubtitleCues(String text) {
  final cues = <SubtitleCue>[];
  String? previous;
  for (final block in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split(RegExp(r'\n{2,}'))) {
    final lines = block.split('\n');
    final at = lines.indexWhere(_timing.hasMatch);
    if (at < 0) continue;
    final match = _timing.firstMatch(lines[at])!;
    var body = [
      for (final line in lines.skip(at + 1))
        if (_unescape(line.replaceAll(_tag, '')).trim() case final clean when clean.isNotEmpty) clean,
    ];
    if (body.isNotEmpty && body.first == previous) body = body.sublist(1);
    if (body.isEmpty) continue;
    previous = body.last;
    cues.add((start: _time(match[1]!), end: _time(match[2]!), text: body.join(' ')));
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

/// [cues] as an SRT file.
String toSrt(List<SubtitleCue> cues) {
  String stamp(Duration d) {
    String two(int n, [int width = 2]) => n.toString().padLeft(width, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)},${two(d.inMilliseconds % 1000, 3)}';
  }

  final out = StringBuffer();
  for (final (i, cue) in cues.indexed) {
    out
      ..writeln(i + 1)
      ..writeln('${stamp(cue.start)} --> ${stamp(cue.end)}')
      ..writeln(cue.text)
      ..writeln();
  }
  return out.toString();
}

/// The cue shown at [position], else the last one before it; -1 before the first.
int cueIndexAt(List<SubtitleCue> cues, Duration position) {
  var low = 0, high = cues.length - 1, found = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (cues[mid].start <= position) {
      found = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return found;
}

Duration _time(String text) {
  final parts = text.replaceAll(',', '.').split(':');
  final seconds = double.parse(parts.last);
  final minutes = int.parse(parts[parts.length - 2]);
  final hours = parts.length > 2 ? int.parse(parts[0]) : 0;
  return Duration(milliseconds: ((hours * 3600 + minutes * 60) * 1000 + seconds * 1000).round());
}

String _unescape(String text) => text.replaceAll('&nbsp;', ' ').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&amp;', '&');

/// A line of the main subtitle with what the second subtitle says while it
/// is spoken.
typedef PairedCue = ({SubtitleCue cue, String? second});

/// [main]'s cues with the [second] cues spoken with them. Where one second
/// line spans several main lines, as a translation joined into whole
/// sentences does, those main lines become one row, so each row reads as a
/// sentence beside its translation.
List<PairedCue> pairSubtitleCues(List<SubtitleCue> main, List<SubtitleCue> second) {
  if (second.isEmpty) return [for (final cue in main) (cue: cue, second: null)];
  final joinNext = List.filled(main.length, false);
  var from = 0;
  for (final other in second) {
    while (from < main.length && main[from].end <= other.start) {
      from++;
    }
    int? first, last;
    for (var i = from; i < main.length && main[i].start < other.end; i++) {
      final overlap = _overlap(main[i], other);
      // A brush at either end does not tie a main line to this one.
      if (overlap >= const Duration(milliseconds: 300) && overlap * 10 >= (main[i].end - main[i].start) * 3) {
        first ??= i;
        last = i;
      }
    }
    if (first != null) {
      for (var i = first; i < last!; i++) {
        joinNext[i] = true;
      }
    }
  }
  final rows = <SubtitleCue>[];
  for (var i = 0; i < main.length; i++) {
    var row = main[i];
    // Overlapping lines could chain on; a row stays a sentence long.
    while (joinNext[i] && i + 1 < main.length && main[i + 1].end - row.start <= _longestRow) {
      i++;
      row = (start: row.start, end: main[i].end, text: joinCueText(row.text, main[i].text));
    }
    rows.add(row);
  }
  final out = <PairedCue>[];
  from = 0;
  final taken = List.filled(second.length, false);
  for (final cue in rows) {
    while (from < second.length && second[from].end <= cue.start) {
      from++;
    }
    final lines = <String>[];
    for (var j = from; j < second.length && second[j].start < cue.end; j++) {
      if (taken[j]) continue;
      final other = second[j];
      final overlap = _overlap(cue, other);
      // A second line belongs where most of it is spoken.
      if (overlap * 2 >= other.end - other.start || overlap >= const Duration(seconds: 1)) {
        lines.add(other.text);
        taken[j] = true;
      }
    }
    out.add((cue: cue, second: lines.isEmpty ? null : lines.reduce(joinCueText)));
  }
  // YouTube's translation of automatic captions often leaves a line empty
  // and puts its words in the next one: that line joins the next row.
  final joined = <PairedCue>[];
  for (var i = 0; i < out.length; i++) {
    var row = out[i];
    while (row.second == null && i + 1 < out.length && out[i + 1].second != null && out[i + 1].cue.start - row.cue.end <= const Duration(seconds: 1) && out[i + 1].cue.end - row.cue.start <= _longestRow) {
      i++;
      row = (cue: (start: row.cue.start, end: out[i].cue.end, text: joinCueText(row.cue.text, out[i].cue.text)), second: out[i].second);
    }
    joined.add(row);
  }
  return joined;
}

const _longestRow = Duration(seconds: 15);

Duration _overlap(SubtitleCue a, SubtitleCue b) {
  final end = a.end < b.end ? a.end : b.end;
  final start = a.start > b.start ? a.start : b.start;
  return end > start ? end - start : Duration.zero;
}

/// [a] and [b] as one line: with a space between words, none between
/// Chinese or Japanese characters.
String joinCueText(String a, String b) {
  if (a.isEmpty || b.isEmpty) return a + b;
  return _wide.hasMatch(a[a.length - 1]) || _wide.hasMatch(b[0]) ? '$a$b' : '$a $b';
}

final _wide = RegExp(r'[　-ヿ㐀-鿿豈-﫿＀-￯]');
