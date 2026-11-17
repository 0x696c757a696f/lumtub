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

  /// Tests that look at the JSON files set this to false.
  static bool? enabledForTesting;

  /// Whether stores keep their data here: the core is there and has the
  /// database. Without it they keep their JSON files.
  static bool get enabled => enabledForTesting ?? (NativeCore.instance?.library.providesSymbol('lumtub_store_write') ?? false);

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

class LocalDbException implements Exception {
  const LocalDbException(this.message, this.setAside);
  final String message;
  /// Where a damaged database was moved, if it was.
  final String? setAside;

  @override
  String toString() => setAside == null ? message : '$message (kept as $setAside)';
}

Map<String, dynamic> _call(String symbol, String ask) {
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

Map<String, dynamic> _read(String ask) => _call('lumtub_store_read', ask);

Map<String, dynamic> _write(String ask) => _call('lumtub_store_write', ask);
