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
