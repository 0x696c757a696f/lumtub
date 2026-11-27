import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'line_pause.dart';
import 'subtitle_cues.dart';

/// 精学: the four steps one stretch of a video is studied in.
enum StudyStep {
  /// 盲听: a short stretch without subtitles, for the gist.
  blind,

  /// 字幕精学: the whole stretch with its subtitles, pausing after each line.
  read,

  /// 跟读: the hardest lines, slower, from their end backwards.
  shadow,

  /// 复听: the whole stretch again without subtitles, then a self-rating.
  relisten,
}

/// A stretch of a video studied at a time: the subtitle lines [first] to
/// [last], both included.
class StudyUnit {
  const StudyUnit(this.first, this.last, this.start, this.end);
  final int first;
  final int last;
  final Duration start;
  final Duration end;

  Duration get length => end - start;

  @override
  bool operator ==(Object other) => other is StudyUnit && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => 'StudyUnit($first..$last, $start..$end)';
}

/// How long a stretch is by default, and the least and most it can be set to.
const studyUnitDefault = Duration(seconds: 120);
const studyUnitShortest = Duration(seconds: 60);
const studyUnitLongest = Duration(seconds: 180);

final _sentenceEnd = RegExp(r'''[.!?。！？…؟।][\s"'”’」』）)\]]*$''');

/// Whether [text] ends a sentence.
bool endsSentence(String text) => _sentenceEnd.hasMatch(text.trim());

/// [lines] cut into stretches of about [target], each at least half as
/// long and at most half as long again (60 to 180 s for two minutes).
/// A stretch ends where a sentence ends; a chapter start in [breaks] that
/// falls between two lines ends it there instead, so chapters stay whole
/// unless they are too long. A short end joins the stretch before it.
List<StudyUnit> studyUnits(List<SubtitleCue> lines, {List<Duration> breaks = const [], Duration target = studyUnitDefault}) {
  if (lines.isEmpty) return const [];
  final shortest = target * 0.5, longest = target * 1.5;
  const slack = Duration(milliseconds: 1500);
  bool chapterAfter(int j) {
    if (j + 1 >= lines.length) return false;
    final before = lines[j].end, after = lines[j + 1].start;
    return breaks.any((b) => b > lines[j].start + slack && b >= before - slack && b <= after + slack);
  }

  Duration gapAfter(int j) => j + 1 < lines.length ? lines[j + 1].start - lines[j].end : Duration.zero;
  final units = <StudyUnit>[];
  var first = 0;
  while (first < lines.length) {
    final start = lines[first].start;
    int? cut;
    int? chapter, sentence, gap;
    Duration? sentenceOff;
    for (var j = first; j < lines.length; j++) {
      final length = lines[j].end - start;
      if (length > longest && j > first) break;
      // A chapter shorter than the shortest stretch is joined to the next.
      if (chapterAfter(j) && length >= shortest) {
        chapter = j;
        break;
      }
      if (length < shortest) continue;
      if (endsSentence(lines[j].text)) {
        final off = (length - target).abs();
        if (sentenceOff == null || off < sentenceOff || off == sentenceOff && gapAfter(j) > gapAfter(sentence!)) {
          sentence = j;
          sentenceOff = off;
        }
      }
      if (gap == null || gapAfter(j) > gapAfter(gap)) gap = j;
    }
    cut = chapter ?? sentence ?? gap;
    if (cut == null) {
      // Not even the shortest stretch is left, or one line is longer than
      // the longest: up to the end, or that line alone.
      var j = first;
      while (j + 1 < lines.length && lines[j + 1].end - start <= longest) {
        j++;
      }
      cut = j;
    }
    // What is left after this cut is too short to be a stretch of its own.
    if (cut + 1 < lines.length && chapter == null) {
      final rest = lines.last.end - lines[cut + 1].start;
      if (rest < shortest * 0.5 && lines.last.end - start <= longest + shortest * 0.5 && !breaks.any((b) => b > lines[cut! + 1].start + slack)) cut = lines.length - 1;
    }
    units.add(StudyUnit(first, cut, start, lines[cut].end));
    first = cut + 1;
  }
  // A last stretch far too short joins the one before, unless a chapter
  // starts it.
  if (units.length >= 2 && units.last.length < shortest * 0.5) {
    final last = units.removeLast(), before = units.removeLast();
    final chapterStarts = breaks.any((b) => (b - last.start).abs() <= slack);
    if (chapterStarts) {
      units.addAll([before, last]);
    } else {
      units.add(StudyUnit(before.first, last.last, before.start, last.end));
    }
  }
  return units;
}

/// The unit [position] is in: the last one starting at or before it.
int unitAt(List<StudyUnit> units, Duration position) {
  var found = 0;
  for (final (i, unit) in units.indexed) {
    if (unit.start - replayEarly * 2 > position) break;
    found = i;
  }
  return found;
}

/// Where the blind listening of [unit] stops: after the line that brings
/// it to 15 s, at 30 s at most, never past the unit.
Duration blindEnd(List<SubtitleCue> lines, StudyUnit unit) {
  const least = Duration(seconds: 15), most = Duration(seconds: 30);
  for (var i = unit.first; i <= unit.last; i++) {
    final length = lines[i].end - unit.start;
    if (length >= least) return length > most ? unit.start + most : lines[i].end;
  }
  return unit.end;
}

/// One part of a line said back from its end: the words from [from] (a
/// share of the line's length, 0 at its start) to the end.
typedef ReverseChunk = ({String text, String before, double from});

final _spaced = RegExp(r'\s');
final _clauseEnd = RegExp(r'[,;:，、；：—–]$');

/// [text] in growing parts from its end, as 逆向分块 follows it: the last
/// few words, then a few more, up to the whole line. Lines in a script
/// without spaces go by characters. Four parts at most.
List<ReverseChunk> reverseChunks(String text) {
  final clean = text.replaceAll('\n', ' ').trim();
  if (clean.isEmpty) return const [];
  final spaced = _spaced.hasMatch(clean);
  // Where each unit (word or character) starts in [clean].
  final starts = <int>[];
  if (spaced) {
    for (final match in RegExp(r'\S+').allMatches(clean)) {
      starts.add(match.start);
    }
  } else {
    final runes = clean.runes.toList();
    var at = 0;
    for (final rune in runes) {
      starts.add(at);
      at += String.fromCharCode(rune).length;
    }
  }
  final count = starts.length;
  final least = spaced ? 3 : 4;
  final size = max(least, (count / 4).ceil());
  if (count <= size) return [(text: clean, before: '', from: 0)];
  // A part starts after a comma or other pause in the line when one is
  // near, so it is a phrase said in one breath rather than a cut word run.
  bool pauseBefore(int unit) => unit > 0 && _clauseEnd.hasMatch(clean.substring(0, starts[unit]).trimRight());
  final cuts = <int>[];
  var next = count - size;
  while (next > 0) {
    final previous = cuts.isEmpty ? count : cuts.last;
    var cut = next;
    for (var d = 1; d <= size ~/ 2 && !pauseBefore(cut); d++) {
      if (next - d > 0 && pauseBefore(next - d)) {
        cut = next - d;
      } else if (next + d < previous - 1 && pauseBefore(next + d)) {
        cut = next + d;
      }
    }
    // The rest is too short to be a step of its own: the whole line follows.
    if (cut < size ~/ 2 && !pauseBefore(cut)) break;
    cuts.add(cut);
    next = cut - size;
  }
  final chunks = [
    for (final cut in cuts) (text: clean.substring(starts[cut]), before: clean.substring(0, starts[cut]).trimRight(), from: starts[cut] / clean.length),
  ];
  chunks.add((text: clean, before: '', from: 0));
  return chunks;
}

/// Where playback starts for [chunk] of [line]: a moment before its first
/// word, by its share of the line, as there are no word timings.
Duration chunkStart(SubtitleCue line, ReverseChunk chunk) {
  if (chunk.from <= 0) return lineStart(line);
  final at = line.start + (line.end - line.start) * chunk.from - const Duration(milliseconds: 250);
  return at < line.start ? line.start : at;
}

/// What [StudyRun.observe] saw happen.
enum StudyEvent {
  /// The blind stretch ended.
  blindDone,

  /// The unit's last line ended while reading.
  readDone,

  /// The line being shadowed ended.
  chunkDone,

  /// The unit ended while listening again.
  relistenDone,
}

/// One video studied: which unit and step, and what this session learned
/// about its lines. Hard lines are kept only while it lasts.
class StudyRun {
  StudyRun({required this.videoId, required this.lines, required this.units, this.unit = 0, this.step = StudyStep.blind});

  final String videoId;
  final List<SubtitleCue> lines;
  final List<StudyUnit> units;
  int unit;
  StudyStep step;

  /// 盲听: the subtitles were asked for.
  bool revealed = false;

  /// How often each line was played again while reading.
  final replays = <int, int>{};

  /// Lines marked hard by hand, or unmarked (false).
  final marked = <int, bool>{};

  /// 跟读: the lines practised, which one now and how much of it.
  List<int> shadowLines = const [];
  int shadowAt = 0;
  int chunk = 0;

  /// The unit was listened to again; its rating is asked for.
  bool rating = false;

  /// The unit is done, rated (30, 70 or 90) or not (null).
  bool done = false;
  int? rated;

  /// Ratings given this session, by unit.
  final ratings = <int, int>{};

  Duration? _last;

  StudyUnit get current => units[unit];
  bool get lastUnit => unit >= units.length - 1;

  /// A line played again this often while reading is a hard one.
  static const hardAfter = 2;

  bool isHard(int line) => marked[line] ?? (replays[line] ?? 0) >= hardAfter;

  /// The hard lines of this unit, most replayed first.
  List<int> get hardLines {
    final unit = current;
    final hard = [for (var i = unit.first; i <= unit.last; i++) if (isHard(i)) i];
    hard.sort((a, b) {
      final byMarked = (marked[b] ?? false ? 1 : 0) - (marked[a] ?? false ? 1 : 0);
      if (byMarked != 0) return byMarked;
      final byReplays = (replays[b] ?? 0) - (replays[a] ?? 0);
      return byReplays != 0 ? byReplays : a - b;
    });
    return hard;
  }

  /// The lines 跟读 goes through: up to three hard ones in the order they
  /// come, else the unit's longest line.
  List<int> pickShadowLines() {
    final hard = hardLines.take(3).toList()..sort();
    if (hard.isNotEmpty) return hard;
    final unit = current;
    var longest = unit.first;
    for (var i = unit.first; i <= unit.last; i++) {
      if (lines[i].text.length > lines[longest].text.length) longest = i;
    }
    return [longest];
  }

  /// The line shadowed now.
  int? get shadowLine => shadowAt < shadowLines.length ? shadowLines[shadowAt] : null;

  List<ReverseChunk> get chunks => switch (shadowLine) { final line? => reverseChunks(lines[line].text), null => const [] };

  /// The line [position] is in, within the unit; null outside it.
  int? lineAt(Duration position) {
    final i = cueIndexAt(lines, position + replayEarly * 2);
    final unit = current;
    return i >= unit.first && i <= unit.last ? i : null;
  }

  /// Marks the line at [position] hard, or not. True when it is hard now.
  bool toggleHard(Duration position) {
    final line = lineAt(position);
    if (line == null) return false;
    final hard = !isHard(line);
    marked[line] = hard;
    return hard;
  }

  /// Moves to [step] of the unit now.
  void enter(StudyStep next) {
    step = next;
    done = false;
    rated = null;
    revealed = false;
    rating = false;
    _last = null;
    if (next == StudyStep.shadow) {
      shadowLines = pickShadowLines();
      shadowAt = 0;
      chunk = 0;
    }
  }

  /// Moves to unit [index], at its first step.
  void enterUnit(int index) {
    unit = index.clamp(0, units.length - 1);
    done = false;
    rated = null;
    enter(StudyStep.blind);
  }

  /// The flow itself seeks, to [to]: positions until playback is there
  /// are left out, so the jump is not a line played again.
  void seeked({Duration? to}) {
    _last = null;
    _target = to;
    _stale = 0;
  }

  Duration? _target;
  int _stale = 0;

  /// Where the step now stops.
  Duration? get stopAt {
    final unit = current;
    return switch (step) {
      StudyStep.blind => blindEnd(lines, unit),
      StudyStep.read => LinePause.pauseAt(lines[unit.last]),
      StudyStep.shadow => switch (shadowLine) { final line? => LinePause.pauseAt(lines[line]), null => null },
      StudyStep.relisten => unit.end,
    };
  }

  /// Called with each position while playing: counts lines played again
  /// and tells when the step's stretch ended.
  StudyEvent? observe(Duration position, {double rate = 1}) {
    if (_target case final target?) {
      final there = position >= target - const Duration(milliseconds: 300) && position <= target + const Duration(seconds: 2);
      if (!there && ++_stale < 40) return null;
      _target = null;
      _last = position;
      return null;
    }
    final last = _last;
    _last = position;
    if (last == null || done || rating) return null;
    if (position < last - const Duration(milliseconds: 300)) {
      if (step == StudyStep.read) {
        final line = lineAt(position);
        if (line != null) replays[line] = (replays[line] ?? 0) + 1;
      }
      return null;
    }
    final speed = rate.clamp(0.25, 4.0);
    if (position <= last || position - last > const Duration(milliseconds: 1500) * speed) return null;
    var stop = stopAt;
    if (stop == null) return null;
    if (step != StudyStep.relisten && step != StudyStep.blind) stop = stop + LinePause.lead - LinePause.lead * speed;
    if (!(last < stop && position >= stop)) return null;
    return switch (step) {
      StudyStep.blind => StudyEvent.blindDone,
      StudyStep.read => StudyEvent.readDone,
      StudyStep.shadow => StudyEvent.chunkDone,
      StudyStep.relisten => StudyEvent.relistenDone,
    };
  }
}

/// Where each video's study stopped, to go on from there, and the length
/// of a unit chosen. Kept in a JSON file in the config folder.
class StudyStore {
  StudyStore(this.file);
  final File file;

  /// Videos remembered, newest first; older ones are forgotten.
  static const kept = 300;

  Duration unitLength = studyUnitDefault;
  double slowRate = 0.85;
  final _videos = <String, ({Duration unitStart, StudyStep step, DateTime at})>{};

  ({Duration unitStart, StudyStep step, DateTime at})? of(String videoId) => _videos[videoId];

  Future<void> load() async {
    try {
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return;
      readFrom(raw);
    } catch (_) {
      // A broken file starts over.
    }
  }

  void readFrom(Map raw) {
    if (raw['unitSeconds'] case final num seconds) {
      unitLength = Duration(seconds: seconds.round().clamp(studyUnitShortest.inSeconds, studyUnitLongest.inSeconds));
    }
    if (raw['slowRate'] case final num rate) slowRate = rate.toDouble().clamp(0.5, 1.0);
    if (raw['videos'] case final Map videos) {
      for (final MapEntry(:key, :value) in videos.entries) {
        if (value is! Map || key is! String) continue;
        final start = value['unitStart'], step = value['step'], at = DateTime.tryParse('${value['at']}');
        if (start is! num || step is! num || at == null) continue;
        _videos[key] = (unitStart: Duration(milliseconds: start.round()), step: StudyStep.values[step.round().clamp(0, StudyStep.values.length - 1)], at: at);
      }
    }
  }

  Map<String, Object?> toJson() {
    final videos = _videos.entries.toList()..sort((a, b) => b.value.at.compareTo(a.value.at));
    return {
      'unitSeconds': unitLength.inSeconds,
      'slowRate': slowRate,
      'videos': {
        for (final MapEntry(:key, :value) in videos.take(kept)) key: {'unitStart': value.unitStart.inMilliseconds, 'step': value.step.index, 'at': value.at.toUtc().toIso8601String()},
      },
    };
  }

  void remember(String videoId, Duration unitStart, StudyStep step) => _videos[videoId] = (unitStart: unitStart, step: step, at: DateTime.now());

  void forget(String videoId) => _videos.remove(videoId);

  Future<void> _saving = Future.value();

  Future<void> save() => _saving = _saving.then((_) async {
        try {
          await file.parent.create(recursive: true);
          final temp = File('${file.path}.tmp');
          await temp.writeAsString(jsonEncode(toJson()), flush: true);
          await temp.rename(file.path);
        } catch (_) {
          // Not saving only loses where to go on from.
        }
      });
}
