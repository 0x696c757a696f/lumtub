"""Turns a learning pack word list into the SQLite dictionary Lumtub's
core reads (lexicon.rs), so a dictionary is looked up on disk instead of
being read into memory.

    sqlite_pack.py FORMAT LANGUAGE IN.tsv OUT.sqlite

FORMAT is `ecdict` (word, phonetic, meanings, forms, …) or `wiktionary`
(word, reading, IPA, parts of speech, Chinese, English, base words).

Tables:
    meta(key, value)            format, language, version
    entry(id, line)             the word list's line, as the app reads it
    term(key, entry, form)      a word as written and in lower case
                                (form 0), or one of its forms (form 1),
                                to its entry

A Wiktionary line that only says which words it is a form of becomes
form rows to those words, not an entry of its own.
"""
import sqlite3
import sys

FORMAT_VERSION = '1'


def fold(word):
    """A word as subtitles write it: no stress marks, ё as е (lexicon.rs
    folds what it looks up the same way)."""
    return word.replace('\u0301', '').replace('\u0300', '').replace('ё', 'е').replace('Ё', 'Е')


def main():
    kind, language, source, target = sys.argv[1:]
    db = sqlite3.connect(target)
    db.executescript('''
        PRAGMA page_size = 4096;
        PRAGMA journal_mode = OFF;
        PRAGMA synchronous = OFF;
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
        CREATE TABLE entry(id INTEGER PRIMARY KEY, line TEXT NOT NULL);
        CREATE TABLE term(key TEXT NOT NULL, entry INTEGER NOT NULL, form INTEGER NOT NULL, PRIMARY KEY(key, entry)) WITHOUT ROWID;
    ''')
    db.executemany('INSERT INTO meta VALUES (?, ?)', [('format', kind), ('language', language), ('version', FORMAT_VERSION)])
    terms = {}

    def term(key, entry, form):
        for k in {key, key.lower(), fold(key), fold(key.lower())}:
            if k and (k, entry) not in terms:
                terms[(k, entry)] = form
            elif k and form == 0:
                terms[(k, entry)] = 0

    ids = {}
    entries = 0
    pending = []
    with open(source, encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            parts = line.split('\t')
            word = parts[0]
            if not word:
                continue
            if kind == 'wiktionary':
                meanings = len(parts) > 5 and (parts[4] or parts[5])
                lemmas = [l for l in (parts[6] if len(parts) > 6 else '').split('|') if l]
                if not meanings:
                    pending.extend((word, lemma) for lemma in lemmas)
                    continue
            entries += 1
            entry = entries
            db.execute('INSERT INTO entry VALUES (?, ?)', (entry, line))
            ids.setdefault(word, entry)
            ids.setdefault(fold(word), entry)
            term(word, entry, 0)
            if kind == 'ecdict' and len(parts) > 3:
                for part in parts[3].split('/'):
                    if len(part) > 2 and part[1] == ':' and part[0] not in '01':
                        pending.append((part[2:], word))
            if kind == 'wiktionary':
                pending.extend((word, lemma) for lemma in lemmas)
    for form, lemma in pending:
        entry = ids.get(lemma) or ids.get(lemma.lower()) or ids.get(fold(lemma)) or ids.get(fold(lemma.lower()))
        if entry and form != lemma:
            term(form, entry, 1)
    db.executemany('INSERT INTO term VALUES (?, ?, ?)', ((k, e, f) for (k, e), f in sorted(terms.items())))
    db.commit()
    # Shipped read-only: a plain journal, statistics for the planner, no
    # free pages.
    db.execute('PRAGMA journal_mode = DELETE')
    db.execute('ANALYZE')
    db.execute('VACUUM')
    problem = db.execute('PRAGMA integrity_check').fetchone()[0]
    db.close()
    if problem != 'ok':
        sys.exit(f'{target}: {problem}')
    print(f'{target}: {entries} entries, {len(terms)} terms')


if __name__ == '__main__':
    main()
