import 'dart:async';
import 'dart:collection';
import 'dart:ui' show VoidCallback;

import 'app_log.dart';
import 'translation.dart';

/// Whether titles in video and playlist lists show their translation, and
/// how.
enum TitleTranslation {
  off,

  /// The translation stands in place of the title; the original shows on hover.
  replace,

  /// The translation on the first line, the original under it.
  translationFirst,

  /// The original on the first line, the translation under it.
  originalFirst;

  bool get bilingual => this == translationFirst || this == originalFirst;
}

/// Translations of the titles lists show, asked for only while a title is
/// on screen.
///
/// A title widget calls [listen] when it is built and [unlisten] when it
/// goes away. A title that stays for [dwell] is queued; one scrolled past
/// sooner is dropped before anything is sent. At most [maxInFlight] titles
/// are being translated at once; the translator gathers those asked for
/// together into one request and keeps its answers on disk. Each answer
/// wakes only the widgets showing that title, so nothing else rebuilds.
/// Every step costs O(1) per title, apart from [configure], which goes once
/// over the titles on screen.
class TitleTranslations {
  TitleTranslations({
    this.dwell = const Duration(milliseconds: 250),
    this.maxInFlight = 40,
    this.maxKept = 4000,
    this.retryAfter = const Duration(minutes: 1),
    this.maxLength = 300,
    this.maxTries = 3,
    this.firstPause = const Duration(seconds: 15),
    this.longestPause = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration dwell;
  final int maxInFlight;

  /// Answers kept in memory; the oldest goes first.
  final int maxKept;

  /// How long a title whose translation failed is left alone.
  final Duration retryAfter;

  /// Longer text is never sent: no YouTube title is this long.
  final int maxLength;
  final int maxTries;
  final Duration firstPause;
  final Duration longestPause;
  final DateTime Function() _now;

  TitleTranslation _mode = TitleTranslation.off;
  Translator? _translator;
  String _target = '';
  bool Function(String text) _needs = (_) => true;
  Object? _setup;

  /// Raised by [configure]: answers to questions asked before are dropped.
  int _generation = 0;

  /// Title → its translation, or the title itself when it is left as it is.
  /// Insertion order is recency.
  final _kept = <String, String>{};
  final _listeners = HashMap<String, List<VoidCallback>>();

  /// Titles waiting to be sent, with when they came on screen; oldest first.
  final _queue = <String, DateTime>{};
  final _inFlight = HashSet<String>();
  final _failed = <String, DateTime>{};
  final _tries = <String, int>{};
  DateTime _pausedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _backoff = Duration.zero;
  Timer? _timer;

  TitleTranslation get mode => _mode;

  /// The language titles are translated into.
  String get target => _target;
  bool get on => _mode != TitleTranslation.off;

  /// Titles queued or being translated, for tests.
  int get waiting => _queue.length + _inFlight.length;

  /// Sets how titles are translated. [setup] names everything the answers
  /// depend on (service, target, languages left alone); when it changes,
  /// what is known is forgotten and the titles on screen are asked again
  /// (the translator's own cache answers those it already made).
  void configure(
      {required TitleTranslation mode,
      required Translator translator,
      required String target,
      required bool Function(String text) needs,
      required Object setup}) {
    final changed = setup != _setup || !identical(translator, _translator);
    if (!changed && mode == _mode) return;
    _mode = mode;
    _translator = translator;
    _target = target;
    _needs = needs;
    if (changed) {
      _setup = setup;
      _generation++;
      _kept.clear();
      _queue.clear();
      _inFlight.clear();
      _failed.clear();
      _tries.clear();
      _pausedUntil = DateTime.fromMillisecondsSinceEpoch(0);
      _backoff = Duration.zero;
      _timer?.cancel();
      _timer = null;
    }
    if (!on) {
      _queue.clear();
      _timer?.cancel();
      _timer = null;
    }
    final shown = [
      for (final MapEntry(:key, :value) in _listeners.entries) (key, [...value])
    ];
    for (final (text, callbacks) in shown) {
      if (on) _admit(text);
      for (final callback in callbacks) {
        callback();
      }
    }
  }

  /// The translation to show for [text]; null while there is none (off,
  /// not known yet, failed, or nothing to translate).
  String? lookup(String text) {
    if (!on) return null;
    final kept = _kept[text];
    return kept == null || kept == text ? null : kept;
  }

  /// [text] is on screen: [onReady] is called when its translation comes.
  void listen(String text, VoidCallback onReady) {
    (_listeners[text] ??= []).add(onReady);
    if (on) _admit(text);
  }

  /// [text] left the screen; it is not sent if it has not been yet.
  void unlisten(String text, VoidCallback onReady) {
    final callbacks = _listeners[text];
    if (callbacks == null) return;
    callbacks.remove(onReady);
    if (callbacks.isNotEmpty) return;
    _listeners.remove(text);
    _queue.remove(text);
    if (_queue.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _admit(String text) {
    final kept = _kept.remove(text);
    if (kept != null) {
      _kept[text] = kept;
      return;
    }
    if (_queue.containsKey(text) || _inFlight.contains(text)) return;
    final failed = _failed[text];
    if (failed != null) {
      if (_now().isBefore(failed)) return;
      _failed.remove(text);
    }
    if (text.trim().isEmpty || text.length > maxLength || !_needs(text)) {
      _keep(text, text);
      return;
    }
    _queue[text] = _now();
    _schedule();
  }

  void _schedule() {
    if (_timer != null || _queue.isEmpty || _inFlight.length >= maxInFlight) return;
    var at = _queue.values.first.add(dwell);
    if (_pausedUntil.isAfter(at)) at = _pausedUntil;
    final wait = at.difference(_now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, _pump);
  }

  void _pump() {
    _timer = null;
    final now = _now();
    if (now.isBefore(_pausedUntil)) return _schedule();
    while (_queue.isNotEmpty && _inFlight.length < maxInFlight) {
      final MapEntry(key: text, value: since) = _queue.entries.first;
      if (now.difference(since) < dwell) break;
      _queue.remove(text);
      _send(text);
    }
    _schedule();
  }

  void _send(String text) {
    final translator = _translator;
    if (translator == null) return;
    _inFlight.add(text);
    final generation = _generation;
    final target = _target;
    unawaited(translator.translate(text, target).then((result) {
      if (generation != _generation) return;
      _inFlight.remove(text);
      _tries.remove(text);
      _backoff = Duration.zero;
      final clean = result.replaceAll(RegExp(r'\s+'), ' ').trim();
      _keep(text,
          clean.isEmpty || clean == text.replaceAll(RegExp(r'\s+'), ' ').trim() ? text : clean);
      _wake(text);
    }, onError: (Object error) {
      if (generation != _generation) return;
      _inFlight.remove(text);
      _pause();
      // Asked again after the pause while it is still on screen, a few
      // times at most; then left alone for [retryAfter].
      final tries = (_tries[text] ?? 0) + 1;
      if (tries < maxTries && _listeners.containsKey(text)) {
        _tries[text] = tries;
        _queue[text] = _now();
      } else {
        _tries.remove(text);
        if (_failed.length >= maxKept) _failed.clear();
        _failed[text] = _now().add(retryAfter);
      }
      logDebug(() => 'Title translation failed: $error');
    }).whenComplete(() {
      if (generation == _generation) _schedule();
    }));
  }

  /// A refusal or failure stops every title for a while, longer each time
  /// in a row (15 s, 30 s, … 5 min), so a busy service is not asked again
  /// and again, and subtitles keep its allowance. Failures of requests
  /// already under way count once.
  void _pause() {
    final now = _now();
    if (now.isBefore(_pausedUntil)) return;
    _backoff = _backoff == Duration.zero ? firstPause : _backoff * 2;
    if (_backoff > longestPause) _backoff = longestPause;
    _pausedUntil = now.add(_backoff);
  }

  void _keep(String text, String translation) {
    _kept.remove(text);
    _kept[text] = translation;
    while (_kept.length > maxKept) {
      _kept.remove(_kept.keys.first);
    }
  }

  void _wake(String text) {
    final callbacks = _listeners[text];
    if (callbacks == null) return;
    for (final callback in [...callbacks]) {
      callback();
    }
  }
}

/// The one every title widget asks; [AppController] configures it.
final titleTranslations = TitleTranslations();
