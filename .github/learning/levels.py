"""Builds the word levels a learner can say they are at, one file a language.

    levels.py OUT_DIR hsk=COMPLETE_JSON jlpt=N5_JSON,N4_JSON,N3_JSON,N2_JSON,N1_JSON ko=KO_TSV

Writes OUT_DIR/<lang>-levels.tsv.gz: `word<TAB>level` lines, level 1 the
easiest, each word at the lowest level it is listed at.

- zh: the HSK lists, new HSK 1-6 and 7-9 as 7 (old HSK levels for words
  only the old lists have), from complete-hsk-vocabulary (MIT).
- ja: JLPT N5 (1) to N1 (5) from OpenJLPT (CC BY-SA 4.0), based on
  Jonathan Waller's lists and linked to JMdict.
- ko: the Korean Basic Dictionary's 초급/중급/고급 (1-3), already in the
  Korean word list.
- es, fr, de, it, ru: about CEFR A1 (1) to C2 (6), by how often the word
  is used (wordfreq, data CC BY-SA 4.0): a guide, not an official list.
"""
import gzip
import json
import os
import sys
import unicodedata

# The most used words of each band, by rank.
BANDS = [(600, 1), (1500, 2), (3000, 3), (5500, 4), (9500, 5), (16000, 6)]
EUROPEAN = ['es', 'fr', 'de', 'it', 'ru']


def keep(levels, word, level):
    word = unicodedata.normalize('NFC', word.strip())
    if word and (word not in levels or level < levels[word]):
        levels[word] = level


def hsk(path):
    levels = {}
    with open(path, encoding='utf-8') as f:
        entries = json.load(f)
    for entry in entries:
        tags = entry.get('level') or entry.get('l') or []
        new = [int(t[4:]) for t in tags if t.startswith('new-') and t[4:].isdigit()]
        old = [int(t[4:]) for t in tags if t.startswith('old-') and t[4:].isdigit()]
        level = min(min(new), 7) if new else (min(old) if old else None)
        if level is None:
            continue
        keep(levels, entry.get('simplified') or entry.get('s') or '', level)
        for form in entry.get('forms') or entry.get('f') or []:
            keep(levels, form.get('traditional') or form.get('t') or '', level)
    return levels


def jlpt(paths):
    entries = []
    for level, path in enumerate(paths, start=1):
        with open(path, encoding='utf-8') as f:
            for row in json.load(f):
                entries.append((level, row.get('word') or '', row.get('reading') or ''))
    levels = {}
    for level, word, _ in entries:
        keep(levels, word, level)
    # Words written in kana in a line look up by their kana too, unless
    # another word is read the same at an easier level.
    for level, _, reading in entries:
        keep(levels, reading, level)
    return levels


def korean(path):
    levels = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) > 7 and parts[7] in ('1', '2', '3'):
                keep(levels, parts[0], int(parts[7]))
    return levels


def by_frequency(lang):
    from wordfreq import top_n_list
    levels = {}
    words = top_n_list(lang, BANDS[-1][0], wordlist='best')
    for rank, word in enumerate(words, start=1):
        if not any(c.isalpha() for c in word):
            continue
        level = next(level for top, level in BANDS if rank <= top)
        keep(levels, word.lower(), level)
    return levels


def write(out, lang, levels, least):
    if len(levels) < least:
        sys.exit(f'{lang}: only {len(levels)} words with a level, expected at least {least}')
    path = os.path.join(out, f'{lang}-levels.tsv.gz')
    with gzip.open(path, 'wt', encoding='utf-8', newline='\n', compresslevel=9) as f:
        for word in sorted(levels):
            if '\t' not in word and '\n' not in word:
                f.write(f'{word}\t{levels[word]}\n')
    counts = {}
    for level in levels.values():
        counts[level] = counts.get(level, 0) + 1
    print(f'{lang} levels: {len(levels)} words, by level {dict(sorted(counts.items()))}', flush=True)


def main():
    out, *args = sys.argv[1:]
    given = dict(a.split('=', 1) for a in args)
    write(out, 'zh', hsk(given['hsk']), 10000)
    write(out, 'ja', jlpt(given['jlpt'].split(',')), 7000)
    if 'ko' in given:
        write(out, 'ko', korean(given['ko']), 3000)
    for lang in EUROPEAN:
        write(out, lang, by_frequency(lang), 12000)


if __name__ == '__main__':
    main()
