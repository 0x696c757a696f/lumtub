"""Gives the English pack's words Chinese meanings and phonetics from
open data with a clear licence, in place of ECDICT's.

    en_zh.py EN_TSV ENGLISH_EXTRACT ZH_EXTRACT [WIKDICT]

EN_TSV is the word list the workflow wrote (word, phonetic, Chinese
meanings, forms, exam tags, Collins stars, rank, English meanings), and
is rewritten in place:

- Chinese meanings (column 3) come from the English Wiktionary's
  translation tables, where each Mandarin translation belongs to one
  sense of the word (ENGLISH_EXTRACT, kaikki.org's JSONL), then from the
  Chinese Wiktionary's English entries, written in Chinese (ZH_EXTRACT,
  gzipped JSONL); both CC BY-SA 4.0. WikDict's en-zh translations
  (WIKDICT, CC BY-SA) are used only for a word neither has, and marked
  so. A word none of them has keeps no Chinese meaning: the app shows
  its English ones rather than a guess.
- The phonetic (column 2) is the English Wiktionary's IPA, British
  first, as learners in China are taught.
- Collins stars (column 6) are dropped: they are Collins' own data.
- The rank (column 7) is the word's place in wordfreq's English list
  (code MIT, data CC BY-SA 4.0) when the wordfreq package is there.
- A tenth column (after English meanings and the CEFR level) says where the Chinese came from: `w` Wiktionary,
  `d` WikDict (shown as a reference translation), empty none.
"""
import gzip
import json
import re
import sqlite3
import sys
from collections import defaultdict

import opencc

simplified = opencc.OpenCC('t2s').convert

POS = {
    'noun': 'n.', 'verb': 'v.', 'adj': 'adj.', 'adv': 'adv.', 'pron': 'pron.', 'prep': 'prep.', 'conj': 'conj.',
    'intj': 'int.', 'num': 'num.', 'det': 'det.', 'article': 'art.', 'particle': 'part.', 'phrase': 'phr.',
    'contraction': 'contr.', 'prep_phrase': 'phr.', 'abbrev': 'abbr.',
}
MAX_LINES = 5
MAX_PER_LINE = 8
CJK = re.compile(r'[㐀-鿿]')
# What a translation or gloss should not carry along: notes in brackets,
# romanisation, the word's own head.
NOTE = re.compile(r'\s*[（(][^）)]*[）)]\s*')


def clean(text):
    return re.sub(r'\s+', ' ', str(text or '')).replace('\t', ' ').replace('\\n', ' ').strip()


def opener(path):
    return gzip.open(path, 'rt', encoding='utf-8') if path.endswith('.gz') else open(path, encoding='utf-8')


def mandarin(item):
    code = item.get('lang_code') or item.get('code') or ''
    lang = item.get('lang') or ''
    return code == 'cmn' or (code == 'zh' and 'Mandarin' in lang) or lang in ('Chinese Mandarin', 'Mandarin')


def translations_of(entry):
    """Sense → Mandarin words, in the order Wiktionary lists them."""
    items = list(entry.get('translations') or [])
    for sense in entry.get('senses') or []:
        for item in sense.get('translations') or []:
            items.append({**item, 'sense': item.get('sense') or (sense.get('glosses') or [''])[-1]})
    by_sense = {}
    for item in items:
        if not mandarin(item):
            continue
        word = clean(item.get('word'))
        if not CJK.search(word):
            continue
        tags = set(item.get('tags') or [])
        if 'Traditional-Chinese' in tags and 'Simplified-Chinese' not in tags:
            # Kept only if no simplified spelling follows; converted.
            rank = 1
        else:
            rank = 0
        words = by_sense.setdefault(clean(item.get('sense')), [])
        for part in re.split(r'[/／,，、]', word):
            part = simplified(NOTE.sub('', part)).strip()
            if part and CJK.search(part) and len(part) <= 12:
                words.append((rank, part))
    found = []
    for words in by_sense.values():
        # Simplified spellings first; the converted traditional ones add
        # nothing when they come out the same.
        seen = []
        for _, word in sorted(words, key=lambda w: w[0]):
            if word not in seen:
                seen.append(word)
        if seen:
            found.append(seen)
    return found


def ipa_of(entry):
    best = None
    for sound in entry.get('sounds') or []:
        ipa = clean(sound.get('ipa')).strip('/[]')
        if not ipa:
            continue
        tags = set(sound.get('tags') or [])
        score = 0 if tags & {'UK', 'Received-Pronunciation', 'RP', 'British'} else 1 if tags & {'US', 'General-American'} else 2
        if best is None or score < best[0]:
            best = (score, ipa)
    return best[1] if best else ''


def line_of(pos, groups):
    """One part of speech's meanings: a sense's words between commas,
    senses between semicolons."""
    seen, senses = set(), []
    for group in groups:
        words = [w for w in group if w not in seen]
        if not words:
            continue
        words = words[:MAX_PER_LINE - len(seen)]
        seen.update(words)
        senses.append('，'.join(words))
        if len(seen) >= MAX_PER_LINE:
            break
    return f'{pos} {"；".join(senses)}' if senses else ''


def main():
    tsv, english_path, zh_path, *rest = sys.argv[1:]
    wikdict = rest[0] if rest else ''
    with open(tsv, encoding='utf-8') as f:
        rows = [line.rstrip('\n').split('\t') for line in f]
    wanted = {row[0] for row in rows}

    # The English Wiktionary: translation tables and IPA.
    tables = defaultdict(lambda: defaultdict(list))
    ipa = {}
    english = re.compile(r'"lang_code":\s*"en"')
    with opener(english_path) as f:
        for line in f:
            if not english.search(line):
                continue
            entry = json.loads(line)
            word = clean(entry.get('word'))
            if entry.get('lang_code', 'en') != 'en' or word not in wanted:
                continue
            if word not in ipa:
                found = ipa_of(entry)
                if found:
                    ipa[word] = found
            pos = POS.get(entry.get('pos', ''))
            if pos:
                tables[word][pos].extend(translations_of(entry))

    # The Chinese Wiktionary's English entries.
    glosses = defaultdict(lambda: defaultdict(list))
    with opener(zh_path) as f:
        for line in f:
            if not english.search(line):
                continue
            entry = json.loads(line)
            word = clean(entry.get('word'))
            if entry.get('lang_code') != 'en' or word not in wanted:
                continue
            pos = POS.get(entry.get('pos', ''))
            if not pos:
                continue
            for sense in entry.get('senses') or []:
                if sense.get('form_of') or sense.get('alt_of'):
                    continue
                gloss = (sense.get('glosses') or [''])[-1]
                gloss = simplified(NOTE.sub('', clean(gloss))).strip(' 。；;，,')
                # A Chinese meaning, not an English explanation.
                if gloss and CJK.search(gloss) and len(gloss) <= 40:
                    glosses[word][pos].append([part.strip() for part in re.split(r'[；;]', gloss) if part.strip()])

    reference = {}
    if wikdict:
        with sqlite3.connect(wikdict) as db:
            for word, translations, score in db.execute('select written_rep, trans_list, max_score from simple_translation'):
                word = clean(word)
                if word not in wanted or not translations or float(score or 0) < 1:
                    continue
                parts = [simplified(NOTE.sub('', clean(t))).strip() for t in str(translations).split('|')]
                parts = [p for p in dict.fromkeys(parts) if p and CJK.search(p)]
                if parts:
                    reference[word] = '，'.join(parts[:MAX_PER_LINE])

    try:
        import wordfreq
        ranks = {w: i + 1 for i, w in enumerate(wordfreq.top_n_list('en', 200000))}
    except ImportError:
        ranks = None
        print('wordfreq is missing: ranks stay as they were', flush=True)

    counts = defaultdict(int)
    with open(tsv, 'w', encoding='utf-8', newline='\n') as out:
        for row in rows:
            while len(row) < 10:
                row.append('')
            word = row[0]
            lines = []
            for pos, groups in tables.get(word, {}).items():
                line = line_of(pos, groups)
                if line:
                    lines.append(line)
            covered = {line.split(' ', 1)[0] for line in lines}
            for pos, groups in glosses.get(word, {}).items():
                if pos not in covered:
                    line = line_of(pos, groups)
                    if line:
                        lines.append(line)
            if lines:
                row[2], row[9] = '\\n'.join(lines[:MAX_LINES]), 'w'
                counts['wiktionary'] += 1
            elif word in reference:
                row[2], row[9] = reference[word], 'd'
                counts['wikdict'] += 1
            else:
                row[2], row[9] = '', ''
                counts['none'] += 1
            row[1] = ipa.get(word, '')
            row[5] = '0'
            if ranks is not None:
                row[6] = str(ranks.get(word.lower(), 0))
            out.write('\t'.join(row) + '\n')
    print(f"Chinese meanings: {counts['wiktionary']} from Wiktionary, {counts['wikdict']} from WikDict, "
          f"{counts['none']} without, of {len(rows)}; IPA for {len(ipa)}", flush=True)
    for word in ('bank', 'run', 'get', 'set', 'apple', 'however', 'beautiful', 'serendipity'):
        row = next((r for r in rows if r[0] == word), None)
        if row:
            print(f'  {word} /{row[1]}/ [{row[9]}] {row[2][:200]}', flush=True)
    if counts['wiktionary'] < 20000:
        sys.exit(f"only {counts['wiktionary']} words with Chinese meanings from Wiktionary")


if __name__ == '__main__':
    main()
