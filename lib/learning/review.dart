import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../app_directories.dart' show writeFileAtomic;
import '../app_log.dart';
import '../l10n/l10n.dart';
import 'vocabulary.dart';

/// How well a word came back in review.
enum ReviewGrade {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const ReviewGrade(this.value);
  final int value;
}

/// Where a word stands in review: how long it is likely to be remembered
/// ([stability], in days), how hard it is ([difficulty], 1 to 10), and
/// when it is next due.
@immutable
class ReviewState {
  const ReviewState({required this.stability, required this.difficulty, required this.due, required this.last, this.reps = 0, this.lapses = 0});

  final double stability;
  final double difficulty;
  final DateTime due;
  final DateTime last;
  final int reps;
  final int lapses;

  /// Remembered for three weeks or more at a time: no longer a new word.
  bool get known => stability >= 21;

  Map<String, Object?> toJson() => {
        's': double.parse(stability.toStringAsFixed(4)),
        'd': double.parse(difficulty.toStringAsFixed(4)),
        'due': due.toUtc().toIso8601String(),
        'last': last.toUtc().toIso8601String(),
        'reps': reps,
        'lapses': lapses,
      };

  static ReviewState? fromJson(Object? json) {
    if (json is! Map) return null;
    final s = json['s'], d = json['d'];
    final due = DateTime.tryParse('${json['due']}'), last = DateTime.tryParse('${json['last']}');
    if (s is! num || d is! num || due == null || last == null) return null;
    return ReviewState(
      stability: s.toDouble(),
      difficulty: d.toDouble(),
      due: due,
      last: last,
      reps: json['reps'] is int ? json['reps'] as int : 0,
      lapses: json['lapses'] is int ? json['lapses'] as int : 0,
    );
  }
}

/// The FSRS scheduler (version 4.5, its published default weights): from
/// a word's state and a grade, its next state, aiming at a 90 % chance of
/// still knowing the word when it comes back.
abstract final class Fsrs {
  static const w = [0.4072, 1.1829, 3.1262, 15.4722, 7.2102, 0.5316, 1.0651, 0.0234, 1.616, 0.1544, 1.0824, 1.9813, 0.0953, 0.2975, 2.2042, 0.2407, 2.9466];
  static const _decay = -0.5;
  static const _factor = 19 / 81;
  static const retention = 0.9;
  static const maxDays = 36500;

  /// A word forgotten comes back this soon, within the same session.
  static const relearn = Duration(minutes: 10);

  /// The chance of still knowing a word [days] after the last review.
  static double retrievability(double days, double stability) => math.pow(1 + _factor * days / stability, _decay).toDouble();

  /// Days until the chance of knowing the word falls to [retention].
  static int interval(double stability) =>
      (stability / _factor * (math.pow(retention, 1 / _decay) - 1)).round().clamp(1, maxDays);

  static double _initialDifficulty(int g) => (w[4] - (g - 3) * w[5]).clamp(1, 10).toDouble();

  /// The state after reviewing [state] (null for a word never reviewed)
  /// with [grade] at [now].
  static ReviewState next(ReviewState? state, ReviewGrade grade, DateTime now) {
    final g = grade.value;
    if (state == null) {
      final stability = w[g - 1];
      return ReviewState(
        stability: stability,
        difficulty: _initialDifficulty(g),
        due: grade == ReviewGrade.again ? now.add(relearn) : now.add(Duration(days: interval(stability))),
        last: now,
        reps: 1,
        lapses: grade == ReviewGrade.again ? 1 : 0,
      );
    }
    final days = math.max(0, now.difference(state.last).inHours / 24);
    final r = retrievability(days.toDouble(), state.stability);
    final d0 = state.difficulty - w[6] * (g - 3);
    final difficulty = (w[7] * _initialDifficulty(4) + (1 - w[7]) * d0).clamp(1, 10).toDouble();
    final double stability;
    if (grade == ReviewGrade.again) {
      stability = math.min(state.stability, w[11] * math.pow(difficulty, -w[12]) * (math.pow(state.stability + 1, w[13]) - 1) * math.exp(w[14] * (1 - r)));
    } else {
      final hard = grade == ReviewGrade.hard ? w[15] : 1.0;
      final easy = grade == ReviewGrade.easy ? w[16] : 1.0;
      stability = state.stability * (math.exp(w[8]) * (11 - difficulty) * math.pow(state.stability, -w[9]) * (math.exp(w[10] * (1 - r)) - 1) * hard * easy + 1);
    }
    return ReviewState(
      stability: stability,
      difficulty: difficulty,
      due: grade == ReviewGrade.again ? now.add(relearn) : now.add(Duration(days: interval(stability))),
      last: now,
      reps: state.reps + 1,
      lapses: state.lapses + (grade == ReviewGrade.again ? 1 : 0),
    );
  }
}

/// One day's reviews, for the streak.
@immutable
class ReviewDay {
  const ReviewDay(this.day, this.count);
  final String day;
  final int count;
}

/// Review states of the vocabulary book's words, kept in `review.json`
/// beside it, and the days on which words were reviewed.
class ReviewStore extends ChangeNotifier {
  ReviewStore(this.file);

  final File file;
  final Map<String, ReviewState> _states = {};
  final Map<String, int> _days = {};
  bool _loaded = false;

  /// New words to bring in a day, so the reviews do not pile up.
  static const newPerDay = 20;

  ReviewState? of(String key) => _states[key];

  static String dayOf(DateTime time) => time.toLocal().toIso8601String().substring(0, 10);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return;
      final words = json['words'];
      if (words is Map) {
        for (final MapEntry(:key, :value) in words.entries) {
          final state = ReviewState.fromJson(value);
          if (state != null) _states['$key'] = state;
        }
      }
      final days = json['days'];
      if (days is Map) {
        for (final MapEntry(:key, :value) in days.entries) {
          if (value is int) _days['$key'] = value;
        }
      }
      notifyListeners();
    } catch (e) {
      logWarn('Could not read the review schedule: $e');
    }
  }

  /// Words of [words] to review at [now]: those due, oldest due first,
  /// then words never reviewed, oldest kept first, up to what is left of
  /// today's [newPerDay].
  List<VocabularyWord> due(List<VocabularyWord> words, DateTime now) {
    final today = dayOf(now);
    final newToday = _states.values.where((s) => s.reps == 1 && dayOf(s.last) == today).length;
    final old = [for (final w in words) if (_states[w.key] case final s? when !s.due.isAfter(now)) w]
      ..sort((a, b) => _states[a.key]!.due.compareTo(_states[b.key]!.due));
    final fresh = [for (final w in words.reversed) if (!_states.containsKey(w.key)) w].take(math.max(0, newPerDay - newToday));
    return [...old, ...fresh];
  }

  /// How many of [words] are due now, new words included.
  int dueCount(List<VocabularyWord> words, DateTime now) => due(words, now).length;

  /// Words of [words] remembered well enough to count as learnt.
  int knownCount(List<VocabularyWord> words) => words.where((w) => _states[w.key]?.known ?? false).length;

  /// The days in a row, up to [now], with at least one review; today
  /// counts once a review is done, and a streak still alive from
  /// yesterday counts until today ends.
  int streak(DateTime now) {
    var day = DateTime(now.year, now.month, now.day);
    if (!_days.containsKey(dayOf(day))) day = day.subtract(const Duration(days: 1));
    var count = 0;
    while (_days.containsKey(dayOf(day))) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  int reviewedOn(DateTime day) => _days[dayOf(day)] ?? 0;

  /// What [grade] would give [key] at [now], without keeping it: for the
  /// intervals shown on the grade buttons.
  ReviewState preview(String key, ReviewGrade grade, DateTime now) => Fsrs.next(_states[key], grade, now);

  Future<void> grade(String key, ReviewGrade grade, DateTime now) async {
    _states[key] = Fsrs.next(_states[key], grade, now);
    _days.update(dayOf(now), (n) => n + 1, ifAbsent: () => 1);
    notifyListeners();
    await _save();
  }

  /// Drops the schedule of words no longer in the book.
  Future<void> keepOnly(Iterable<String> keys) async {
    final kept = keys.toSet();
    final before = _states.length;
    _states.removeWhere((key, _) => !kept.contains(key));
    if (_states.length != before) await _save();
  }

  Future<void> _save() async {
    try {
      await writeFileAtomic(file, jsonEncode({
        'version': 1,
        'words': {for (final MapEntry(:key, :value) in _states.entries) key: value.toJson()},
        'days': _days,
      }));
    } catch (e) {
      logError('Could not save the review schedule', e);
    }
  }
}

/// A grade's next interval as a learner reads it: minutes, days, months
/// or years.
String reviewIntervalLabel(Duration d) {
  if (d.inMinutes < 60) return tr('{0} min', [math.max(1, d.inMinutes)]);
  if (d.inHours < 24) return tr('{0} h', [d.inHours]);
  final days = (d.inHours / 24).round();
  if (days < 31) return tr('{0} d', [days]);
  if (days < 365) return tr('{0} mo', [(days / 30).round()]);
  return tr('{0} y', [(days / 365).toStringAsFixed(1)]);
}

final _stores = <String, ReviewStore>{};

/// The review schedule kept beside [book].
ReviewStore reviewStoreOf(VocabularyBook book) =>
    _stores.putIfAbsent(book.file.path, () => ReviewStore(File('${book.file.parent.path}${Platform.pathSeparator}review.json')));
