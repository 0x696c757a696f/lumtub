import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'app_log.dart';
import 'native_core.dart';

/// What [LocalDb.read] found: each list as (key, body) in order, and the
/// meta values.
typedef DbContents = ({Map<String, List<(String, Object?)>> lists, Map<String, String> meta});

/// `lumtub.db` in the data folder, kept by the Rust core (SQLite). Each
/// store hands over its lists whole, as keys in order with JSON bodies;
/// only the bodies that changed since the last write go to the core, and
/// the core writes only the rows that moved or changed.
class LocalDb {
  /// One per file, shared by the stores in it: after a failed write every
  /// store sends all of its lists again.
  factory LocalDb(String path) => _open.putIfAbsent(path, () => LocalDb._(path));

  LocalDb._(this.path);

  /// The database next to [file], such as `data/library.json`.
  factory LocalDb.beside(File file) => LocalDb('${file.parent.path}${Platform.pathSeparator}lumtub.db');

  static final _open = <String, LocalDb>{};

  final String path;

  /// Overrides [enabled]. Under `flutter test` stores keep their JSON
  /// files unless a test sets this to true: widget tests end while a
  /// write may still be running on another isolate, and Windows cannot
  /// delete a test's folder while the database is open.
  static bool? enabledForTesting;

  /// Whether stores keep their data here: the core is there and has the
  /// database. Without it they keep their JSON files.
  static bool get enabled =>
      enabledForTesting ?? (!_underTest && (NativeCore.instance?.library.providesSymbol('lumtub_store_write') ?? false));

  static final _underTest = Platform.environment['FLUTTER_TEST'] == 'true';

  /// The bodies each list had at the last write, by key, so the next one
  /// sends only what changed.
  final _sent = <String, Map<String, String>>{};

  /// Reads [lists] and the lists starting with one of [prefixes]. Throws
  /// [LocalDbException] when the database cannot be read; a damaged one
  /// has been set aside by then.
  Future<DbContents> read(List<String> lists, {List<String> prefixes = const []}) async {
    final ask = jsonEncode({'path': path, 'lists': lists, 'prefixes': prefixes});
    final answer = await Isolate.run(() => _read(ask));
    if (answer['error'] case final String error) throw LocalDbException(error, answer['setAside'] as String?);
    final found = <String, List<(String, Object?)>>{};
    for (final MapEntry(:key, :value) in (answer['lists'] as Map? ?? const {}).entries) {
      final entries = <(String, Object?)>[];
      for (final pair in value is List ? value : const []) {
        if (pair is List && pair.length == 2 && pair[0] is String) entries.add((pair[0] as String, pair[1]));
      }
      found[key as String] = entries;
      _sent[key] = {for (final (k, body) in entries) k: jsonEncode(body)};
    }
    final meta = <String, String>{
      for (final MapEntry(:key, :value) in (answer['meta'] as Map? ?? const {}).entries)
        if (value is String) key as String: value,
    };
    return (lists: found, meta: meta);
  }

  /// Makes the lists in [lists] hold these entries, in this order, and
  /// removes the lists in [drop]; [meta] is set as well. All of it is one
  /// transaction. On failure nothing is changed, and the next write sends
  /// everything again.
  Future<void> write(Map<String, List<(String, String)>> lists, {Iterable<String> drop = const [], Map<String, String> meta = const {}}) async {
    final ask = StringBuffer('{"path":')
      ..write(jsonEncode(path))
      ..write(',"drop":')
      ..write(jsonEncode(drop.toList()))
      ..write(',"meta":')
      ..write(jsonEncode(meta))
      ..write(',"lists":[');
    final sending = <String, Map<String, String>>{};
    var firstList = true;
    for (final MapEntry(key: name, value: entries) in lists.entries) {
      final before = _sent[name] ?? const {};
      final now = <String, String>{};
      final keys = StringBuffer();
      final bodies = StringBuffer();
      var changed = false;
      for (final (key, body) in entries) {
        if (now.containsKey(key)) continue;
        now[key] = body;
        if (keys.isNotEmpty) keys.write(',');
        keys.write(jsonEncode(key));
        final old = before[key];
        if (!identical(old, body) && old != body) {
          if (bodies.isNotEmpty) bodies.write(',');
          bodies
            ..write(jsonEncode(key))
            ..write(':')
            ..write(body);
          changed = true;
        }
      }
      if (now.length != before.length) changed = true;
      // Same keys and bodies: only the order could differ.
      if (!changed) {
        var at = 0;
        final order = before.keys.toList();
        for (final key in now.keys) {
          if (order[at++] != key) {
            changed = true;
            break;
          }
        }
      }
      sending[name] = now;
      if (!changed) continue;
      if (!firstList) ask.write(',');
      firstList = false;
      ask
        ..write('{"name":')
        ..write(jsonEncode(name))
        ..write(',"keys":[')
        ..write(keys)
        ..write('],"bodies":{')
        ..write(bodies)
        ..write('}}');
    }
    ask.write(']}');
    final dropped = drop.toList();
    if (firstList && dropped.isEmpty && meta.isEmpty) return;
    final text = ask.toString();
    final answer = await Isolate.run(() => _write(text));
    if (answer['error'] case final String error) {
      _sent.clear();
      throw LocalDbException(error, answer['setAside'] as String?);
    }
    _sent.addAll(sending);
    dropped.forEach(_sent.remove);
  }
}

/// Texts made for a video (transcripts and AI summaries), kept in the
/// same `lumtub.db` as the library by the core's `store_texts`.
extension LocalDbTexts on LocalDb {
  /// Whether this core keeps texts; older cores and tests keep files.
  static bool get available => LocalDb.enabled && (NativeCore.instance?.library.providesSymbol('lumtub_store_texts') ?? false);

  Future<Map<String, dynamic>> _texts(String op, Map<String, Object?> fields) async {
    final ask = jsonEncode({'path': path, 'op': op, ...fields});
    final answer = await Isolate.run(() => callCoreJson('lumtub_store_texts', ask));
    if (answer['error'] case final String error) throw LocalDbException(error, answer['setAside'] as String?);
    return answer;
  }

  /// Keeps [body] as [video]'s transcript in [lang]; of [origin], only the
  /// newest [keep] stay (0 keeps all).
  Future<void> putTranscript(String video, String lang, String origin, String body, {String model = '', int keep = 0}) =>
      _texts('transcript.put', {'video': video, 'lang': lang, 'origin': origin, 'model': model, 'body': body, 'keep': keep});

  /// [video]'s transcripts, newest first.
  Future<List<SavedTranscript>> transcripts(String video, {List<String> origins = const []}) async {
    final answer = await _texts('transcript.get', {'video': video, 'origins': origins});
    return [
      for (final t in answer['transcripts'] is List ? answer['transcripts'] as List : const [])
        if (t is Map)
          (
            lang: '${t['lang']}',
            origin: '${t['origin']}',
            model: '${t['model'] ?? ''}',
            body: '${t['body'] ?? ''}',
            created: DateTime.fromMillisecondsSinceEpoch(((t['created'] as num?) ?? 0).toInt() * 1000),
          ),
    ];
  }

  /// Forgets [video]'s transcripts (all videos when empty), of [origin]
  /// only when given.
  Future<void> forgetTranscripts({String video = '', String origin = ''}) => _texts('transcript.forget', {'video': video, 'origin': origin});

  Future<void> putSummary(String video, String lang, String provider, String body, {int keep = 0}) =>
      _texts('summary.put', {'video': video, 'lang': lang, 'provider': provider, 'body': body, 'keep': keep});

  Future<String?> summary(String video, String lang) async {
    final found = (await _texts('summary.get', {'video': video, 'lang': lang}))['summary'];
    return found is Map ? found['body'] as String? : null;
  }

  /// Forgets [video]'s summaries in every language (all videos when empty).
  Future<void> forgetSummaries({String video = ''}) => _texts('summary.forget', {'video': video});
}

/// A transcript kept in `lumtub.db`. [origin] is `human`, `youtube-auto`,
/// `machine-local` or `machine-cloud`.
typedef SavedTranscript = ({String lang, String origin, String model, String body, DateTime created});

class LocalDbException implements Exception {
  const LocalDbException(this.message, this.setAside);
  final String message;
  /// Where a damaged database was moved, if it was.
  final String? setAside;

  @override
  String toString() => setAside == null ? message : '$message (kept as $setAside)';
}

/// The JSON answer of the core's [symbol] to [ask], or `{error}`; run it
/// on another isolate.
Map<String, dynamic> callCoreJson(String symbol, String ask) {
  final core = NativeCore.instance;
  if (core == null) return {'error': NativeCore.missingMessage};
  try {
    final call = core.library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>(symbol);
    final text = core.take(core.withText(ask, call));
    final answer = text == null ? null : jsonDecode(text);
    return answer is Map<String, dynamic> ? answer : {'error': 'No answer from $symbol'};
  } catch (e) {
    logWarn('$symbol failed: $e');
    return {'error': '$e'};
  }
}

Map<String, dynamic> _read(String ask) => callCoreJson('lumtub_store_read', ask);

Map<String, dynamic> _write(String ask) => callCoreJson('lumtub_store_write', ask);
