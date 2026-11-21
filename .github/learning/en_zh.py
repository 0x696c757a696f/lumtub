"""Gives the English pack's words Chinese meanings and phonetics from
open data with a clear licence, in place of ECDICT's.

    en_zh.py EN_TSV ENGLISH_EXTRACT ZH_EXTRACT [wikdict=PATH] [cow=PATH wordnet=PATH]

EN_TSV is the word list the workflow wrote (word, phonetic, Chinese
meanings, forms, exam tags, Collins stars, rank, English meanings), and
is rewritten in place:

- Chinese meanings (column 3) come from the English Wiktionary's
  translation tables, where each Mandarin translation belongs to one
  sense of the word (ENGLISH_EXTRACT, kaikki.org's JSONL), then from the
  Chinese Wiktionary's English entries, written in Chinese (ZH_EXTRACT,
  gzipped JSONL); both CC BY-SA 4.0. A word neither has gets the
  Chinese lemmas of its most common WordNet senses from the Chinese Open
  Wordnet (cow=, its WN-LMF XML; WordNet-style licence), found through
  Princeton WordNet 3.0's index files (wordnet=, the NLTK zip). WikDict's en-zh translations
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


# Chinese varieties other than Mandarin, whose words a Mandarin reader
# would not use.
OTHER_CHINESE = re.compile(r'Cantonese|Hokkien|Min|Wu|Hakka|Teochew|Gan|Xiang|Jin|Dungan|Classical|Literary|Taishanese|Shanghainese', re.I)


def mandarin(item):
    code = item.get('lang_code') or item.get('code') or ''
    lang = item.get('lang') or ''
    tags = ' '.join(item.get('tags') or []) + ' ' + ' '.join(item.get('raw_tags') or [])
    if code == 'cmn' or 'Mandarin' in lang or 'Mandarin' in tags:
        return True
    # "Chinese" with no variety named: written Chinese, as Mandarin uses it.
    return (code == 'zh' or lang == 'Chinese') and not OTHER_CHINESE.search(lang + ' ' + tags)


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


# Contractions, which dictionaries leave out; written for this pack.
CONTRACTIONS = {
    "can't": 'v. 不能，不会', "cannot": 'v. 不能，不会', "couldn't": 'v. 不能，不会（过去）', "won't": 'v. 不会，将不', "wouldn't": 'v. 不会，不愿',
    "don't": 'v. 不（do not）', "doesn't": 'v. 不（does not）', "didn't": 'v. 没有（did not）', "isn't": 'v. 不是（is not）', "aren't": 'v. 不是（are not）',
    "wasn't": 'v. 不是（was not）', "weren't": 'v. 不是（were not）', "haven't": 'v. 没有（have not）', "hasn't": 'v. 没有（has not）', "hadn't": 'v. 没有（had not）',
    "shouldn't": 'v. 不应该', "mustn't": 'v. 不得，禁止', "needn't": 'v. 不必', "mightn't": 'v. 可能不', "shan't": 'v. 将不',
    "i'm": '我是（I am）', "you're": '你是（you are）', "we're": '我们是（we are）', "they're": '他们是（they are）', "it's": '它是（it is / it has）',
    "that's": '那是（that is）', "there's": '有（there is）', "let's": '让我们（let us）', "i've": '我已经（I have）', "i'll": '我将（I will）', "i'd": '我会；我曾（I would / I had）',
    "anymore": 'adv. 不再，再也（不）', "alright": 'adj. 好的，没问题；adv. 还好',
}


def wordnet_meanings(cow_path, wordnet_path):
    """word → lines of Chinese lemmas for its first WordNet senses, or
    a function giving [] when either file is missing."""
    if not cow_path or not wordnet_path:
        return lambda word: []
    import zipfile
    lemmas = defaultdict(list)
    current = None
    with open(cow_path, encoding='utf-8') as f:
        for line in f:
            found = re.search(r'<Lemma writtenForm="([^"]+)"', line)
            if found:
                current = found.group(1)
                continue
            found = re.search(r'synset="cow-(\d{8})-([nvars])"', line)
            if found and current:
                key = (found.group(1), 'a' if found.group(2) == 's' else found.group(2))
                if current not in lemmas[key]:
                    lemmas[key].append(current)
    index = defaultdict(dict)
    with zipfile.ZipFile(wordnet_path) as z:
        for pos, name in (('n', 'noun'), ('v', 'verb'), ('a', 'adj'), ('r', 'adv')):
            for line in z.read(f'wordnet/index.{name}').decode('utf-8').splitlines():
                if line.startswith(' '):
                    continue
                parts = line.split()
                pointers, synsets = int(parts[3]), int(parts[2])
                # Senses in order of how often they were met.
                index[parts[0].replace('_', ' ')][pos] = parts[6 + pointers:6 + pointers + synsets]
    print(f'Chinese Open Wordnet: {len(lemmas)} synsets; WordNet: {len(index)} words', flush=True)
    names = {'n': 'n.', 'v': 'v.', 'a': 'adj.', 'r': 'adv.'}

    def meanings(word):
        lines = []
        for pos in 'nvar':
            groups = [lemmas[(o, pos)][:3] for o in index.get(word.lower(), {}).get(pos, [])[:4] if lemmas.get((o, pos))]
            line = line_of(names[pos], groups[:3])
            if line:
                lines.append(line)
        return lines
    return meanings


def main():
    tsv, english_path, zh_path, *rest = sys.argv[1:]
    options = dict(arg.split('=', 1) for arg in rest)
    wikdict = options.get('wikdict', '')
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

    wordnet = wordnet_meanings(options.get('cow', ''), options.get('wordnet', ''))

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
    done = {}

    def lemma_of(row):
        # ECDICT's forms: 0:base word, when this one is a form of it.
        for part in row[3].split('/'):
            if part.startswith('0:') and part[2:] != row[0]:
                return part[2:]
        return ''

    # Base words first, so a form finds its base word's meanings.
    rows.sort(key=lambda r: bool(lemma_of(r)))
    with open(tsv, 'w', encoding='utf-8', newline='\n') as out:
        for row in rows:
            while len(row) < 10:
                row.append('')
            word = row[0]
            # The Chinese Wiktionary's own meanings join the translations,
            # after them within a part of speech.
            merged = {pos: list(groups) for pos, groups in tables.get(word, {}).items()}
            for pos, groups in glosses.get(word, {}).items():
                merged.setdefault(pos, []).extend(groups)
            lines = [line for line in (line_of(pos, groups) for pos, groups in merged.items()) if line]
            if lines:
                row[2], row[9] = '\\n'.join(lines[:MAX_LINES]), 'w'
                counts['wiktionary'] += 1
            elif word in CONTRACTIONS:
                row[2], row[9] = CONTRACTIONS[word], 'w'
                counts['contractions'] += 1
            elif wordnet(word):
                row[2], row[9] = '\\n'.join(wordnet(word)), 'w'
                counts['Chinese Open Wordnet'] += 1
            elif lemma_of(row) and done.get(lemma_of(row)):
                # An inflected form (socks, works): its base word's meanings.
                row[2], row[9] = done[lemma_of(row)], 'w'
                counts['base word'] += 1
            elif word in reference:
                row[2], row[9] = reference[word], 'd'
                counts['wikdict'] += 1
            else:
                row[2], row[9] = '', ''
                counts['none'] += 1
            if row[9] == 'w':
                done[word] = row[2]
            row[1] = ipa.get(word, '')
            row[5] = '0'
            if ranks is not None:
                row[6] = str(ranks.get(word.lower(), 0))
            out.write('\t'.join(row) + '\n')
    print(f"Chinese meanings: {counts['wiktionary']} from Wiktionary, {counts['Chinese Open Wordnet']} from the Chinese Open Wordnet, "
          f"{counts['contractions']} contractions, {counts['base word']} from base words, {counts['wikdict']} from WikDict, "
          f"{counts['none']} without, of {len(rows)}; IPA for {len(ipa)}", flush=True)
    for word in ('bank', 'run', 'get', 'set', 'however', 'beautiful', 'available', 'assess', 'totally', 'socks', 'psychological', "can't"):
        row = next((r for r in rows if r[0] == word), None)
        if row:
            print(f'  {word} /{row[1]}/ [{row[9]}] {row[2][:200]}', flush=True)
    if counts['wiktionary'] < 20000:
        sys.exit(f"only {counts['wiktionary']} words with Chinese meanings from Wiktionary")


if __name__ == '__main__':
    main()
