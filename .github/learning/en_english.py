"""Adds English meanings to the English pack's word list.

    en_english.py EN_TSV ENGLISH_EXTRACT

EN_TSV is the ECDICT list the workflow wrote (word, phonetic, Chinese
meanings, forms, exam tags, Collins stars, rank, then ECDICT's own
English definitions, mostly WordNet's). ENGLISH_EXTRACT is kaikki.org's
extract of the English Wiktionary's English words (JSONL, CC BY-SA 4.0).
The eighth column becomes the word's Wiktionary meanings, plainer and
newer than WordNet's, or stays ECDICT's when Wiktionary has none. The
file is rewritten in place.
"""
import gzip
import json
import re
import sys

MAX_SENSES = 6
POS = {
    'noun': 'n.', 'verb': 'v.', 'adj': 'adj.', 'adv': 'adv.', 'pron': 'pron.', 'prep': 'prep.', 'conj': 'conj.',
    'intj': 'int.', 'num': 'num.', 'det': 'det.', 'article': 'art.', 'particle': 'part.', 'phrase': 'phr.',
    'contraction': 'contr.', 'prep_phrase': 'phr.',
}
# Senses a learner meets rarely: left out while better ones remain.
RARE = {'obsolete', 'archaic', 'rare', 'dated', 'historical', 'nonstandard', 'dialectal', 'misspelling', 'Internet', 'slang', 'vulgar', 'derogatory', 'offensive'}


def clean(text):
    return re.sub(r'\s+', ' ', str(text)).replace('\t', ' ').strip()


def opener(path):
    return gzip.open(path, 'rt', encoding='utf-8') if path.endswith('.gz') else open(path, encoding='utf-8')


def main():
    tsv, extract = sys.argv[1:]
    with open(tsv, encoding='utf-8') as f:
        rows = [line.rstrip('\n').split('\t') for line in f]
    wanted = {row[0] for row in rows}
    common, rare = {}, {}
    english = re.compile(r'"lang_code":\s*"en"')
    with opener(extract) as f:
        for line in f:
            if not english.search(line):
                continue
            entry = json.loads(line)
            word = clean(entry.get('word', ''))
            if entry.get('lang_code') != 'en' or word not in wanted:
                continue
            pos = POS.get(entry.get('pos', ''))
            if not pos:
                continue
            for sense in entry.get('senses', []):
                if sense.get('form_of') or sense.get('alt_of'):
                    continue
                glosses = sense.get('glosses') or []
                if not glosses:
                    continue
                gloss = clean(glosses[-1])
                if not gloss or len(gloss) > 240:
                    continue
                target = rare if set(sense.get('tags', [])) & RARE else common
                found = target.setdefault(word, [])
                text = f'{pos} {gloss}'
                if text not in found and len(found) < MAX_SENSES:
                    found.append(text)
    from_wiktionary = 0
    with open(tsv, 'w', encoding='utf-8', newline='\n') as out:
        for row in rows:
            while len(row) < 8:
                row.append('')
            senses = (common.get(row[0], []) + rare.get(row[0], []))[:MAX_SENSES]
            if senses:
                row[7] = '\\n'.join(senses)
                from_wiktionary += 1
            out.write('\t'.join(row) + '\n')
    with_english = sum(1 for row in rows if len(row) > 7 and row[7])
    print(f'English meanings: {from_wiktionary} words from Wiktionary, {with_english} of {len(rows)} in all', flush=True)
    if from_wiktionary < 20000:
        sys.exit(f'only {from_wiktionary} words from Wiktionary')


if __name__ == '__main__':
    main()
