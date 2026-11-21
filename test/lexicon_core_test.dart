import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/english_dictionary.dart';
import 'package:lumtub/learning/lexicon.dart';
import 'package:lumtub/learning/wiktionary_dictionary.dart';
import 'package:lumtub/native_core.dart';

/// A dictionary file laid out as sqlite_pack.py writes it, made with
/// Python's sqlite3 module.
Future<String?> _pack(Directory dir, String name, List<String> sql) async {
  final path = '${dir.path}${Platform.pathSeparator}$name';
  try {
    const script = 'import sqlite3, sys\ndb = sqlite3.connect(sys.argv[1])\ndb.executescript(sys.stdin.buffer.read().decode(\'utf-8\'))\ndb.commit()\n';
    final process = await Process.start(Platform.isWindows ? 'python' : 'python3', ['-c', script, path]);
    process.stdin.encoding = utf8;
    process.stdin.write(sql.map((s) => '$s;').join('\n'));
    await process.stdin.close();
    return await process.exitCode == 0 ? path : null;
  } on ProcessException {
    return null;
  }
}

const _schema = [
  'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID',
  'CREATE TABLE entry(id INTEGER PRIMARY KEY, line TEXT NOT NULL)',
  'CREATE TABLE term(key TEXT NOT NULL, entry INTEGER NOT NULL, form INTEGER NOT NULL, PRIMARY KEY(key, entry)) WITHOUT ROWID',
  "INSERT INTO meta VALUES ('version', '1')",
];

void main() {
  final skip = NativeCore.instance == null ? 'needs lumtub_core (LUMTUB_CORE_DLL)' : null;

  test('English and Wiktionary dictionaries look words up in the core', () async {
    final dir = await Directory.systemTemp.createTemp('lumtub lexicon 词典');
    addTearDown(() => dir.delete(recursive: true));
    // Closed first, so Windows lets the folder go.
    addTearDown(() {
      CoreLexicon.close('en');
      CoreLexicon.close('ru');
    });
    final en = await _pack(dir, 'en.sqlite', [
      ..._schema,
      "INSERT INTO entry VALUES (1, 'run\trʌn\tvi. 跑\tp:ran/i:running\tzk gk\t5\t300')",
      "INSERT INTO term VALUES ('run', 1, 0), ('ran', 1, 1), ('running', 1, 1)",
    ]);
    final ru = await _pack(dir, 'ru.sqlite', [
      ..._schema,
      "INSERT INTO entry VALUES (1, 'ёлка\tjólka\t\tn.\tn. 枞树\tn. fir tree\t')",
      "INSERT INTO term VALUES ('ёлка', 1, 0), ('елка', 1, 0), ('ёлки', 1, 1), ('елки', 1, 1)",
    ]);
    if (en == null || ru == null) {
      markTestSkipped('needs Python');
      return;
    }
    final english = EnglishDictionary(CoreLexicon.open('en', en));
    expect(english.lookup('Running').single.word, 'run');
    expect(english.levelOf('ran'), EnglishLevel.middleSchool.index);
    expect(english.lookup('zzz'), isEmpty);
    final russian = WiktionaryDictionary('ru', CoreLexicon.open('ru', ru));
    final found = russian.lookup('елки');
    expect(found.single.word, 'ёлка');
    expect(found.single.form, isTrue);
    expect(russian.lookup('Ёлка').single.form, isFalse);
    CoreLexicon.close('ru');
    expect(() => CoreLexicon.open('ru', '${dir.path}/missing.sqlite'), throwsStateError);
  }, skip: skip);

  test('the core cuts French and Spanish lines into words', () async {
    final dir = await Directory.systemTemp.createTemp('lumtub words');
    addTearDown(() => dir.delete(recursive: true));
    addTearDown(() => CoreLexicon.close('es'));
    final es = await _pack(dir, 'es.sqlite', [
      ..._schema,
      "INSERT INTO entry VALUES (1, 'hacer\t\t\tv.\t做\tto do\t')",
      "INSERT INTO term VALUES ('hacer', 1, 0)",
    ]);
    if (es == null) {
      markTestSkipped('needs Python');
      return;
    }
    const line = 'J’ai vu l’homme 😀, a-t-il dit.';
    final words = CoreWords.cut('fr', line)!;
    expect([for (final w in words) line.substring(w.start, w.end)], ['J’', 'ai', 'vu', 'l’', 'homme', 'a', 'il', 'dit']);
    expect(words.first.keys.first, "J'");
    final spanish = WiktionaryDictionary('es', CoreLexicon.open('es', es));
    final found = spanish.lookup('Hacerlo');
    expect(found.single.word, 'hacer');
    expect(found.single.form, isTrue);
    CoreLexicon.close('es');
    expect(CoreWords.cut('ko', '안녕하세요'), isNull);
  }, skip: skip);
}
