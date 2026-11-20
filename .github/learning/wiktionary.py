"""Builds the learning pack's Wiktionary dictionaries.

    wiktionary.py ZH_EXTRACT OUT_DIR LANG=EN_EXTRACT ...

ZH_EXTRACT is kaikki.org's extract of the Chinese Wiktionary (gzipped
JSONL), which gives Chinese meanings for some words; each EN_EXTRACT is
kaikki.org's extract of the English Wiktionary for one language (JSONL),
which gives English meanings and the forms of words. Writes
OUT_DIR/LANG-wiktionary.tsv, one word a line:

    word, reading, IPA, parts of speech, Chinese meanings, English
    meanings, the words it is a form of

between tabs, meanings one a line with a literal \\n between them, parts
of speech and base words between |. Both Wiktionaries are CC BY-SA 4.0.
"""
import gzip
import json
import re
import sys
from collections import defaultdict

MAX_SENSES = 8
MIN_WORDS = int(__import__("os").environ.get("MIN_WORDS", "20000"))
WORD = re.compile(r"^[^\W\d_](?:[\w'’\-]*[^\W\d_])?$")
SKIP_FORM_TAGS = {'table-tags', 'inflection-template', 'class', 'romanization', 'canonical', 'error-unrecognized-form'}
POS = {
    'noun': 'n.', 'verb': 'v.', 'adj': 'adj.', 'adv': 'adv.', 'pron': 'pron.', 'prep': 'prep.', 'conj': 'conj.',
    'intj': 'int.', 'num': 'num.', 'det': 'det.', 'article': 'art.', 'particle': 'part.', 'name': 'name',
    'phrase': 'phr.', 'suffix': 'suf.', 'prefix': 'pref.', 'postp': 'postp.', 'contraction': 'contr.',
}


def clean(text):
    return re.sub(r'\s+', ' ', str(text)).replace('\t', ' ').strip()


def opener(path):
    return gzip.open(path, 'rt', encoding='utf-8') if path.endswith('.gz') else open(path, encoding='utf-8')


def gloss_of(sense):
    glosses = sense.get('glosses') or sense.get('raw_glosses') or []
    return clean(glosses[-1]) if glosses else ''


def main():
    zh_path, out_dir, *pairs = sys.argv[1:]
    languages = dict(pair.split('=', 1) for pair in pairs)

    # Chinese meanings, from the Chinese Wiktionary.
    chinese = {code: defaultdict(list) for code in languages}
    wanted = re.compile(r'"lang_code":\s*"(?:%s)"' % '|'.join(map(re.escape, languages)))
    with opener(zh_path) as f:
        for line in f:
            if not wanted.search(line):
                continue
            entry = json.loads(line)
            code = entry.get('lang_code')
            word = clean(entry.get('word', ''))
            if code not in chinese or not word:
                continue
            pos = POS.get(entry.get('pos', ''), '')
            found = chinese[code][word]
            for sense in entry.get('senses', []):
                if sense.get('form_of') or len(found) >= MAX_SENSES:
                    continue
                gloss = gloss_of(sense)
                if gloss and gloss not in found:
                    found.append(f'{pos} {gloss}'.strip())
    for code, words in chinese.items():
        print(f'{code}: Chinese meanings for {len(words)} words', flush=True)

    for code, path in languages.items():
        words = {}

        def word_of(text):
            return words.setdefault(text, {'reading': '', 'ipa': '', 'pos': [], 'en': [], 'lemmas': []})

        with opener(path) as f:
            for line in f:
                entry = json.loads(line)
                if entry.get('lang_code', code) != code:
                    continue
                text = clean(entry.get('word', ''))
                if not text or not WORD.match(text):
                    continue
                record = word_of(text)
                pos = POS.get(entry.get('pos', ''), '')
                if pos and pos not in record['pos']:
                    record['pos'].append(pos)
                for form in entry.get('forms', []):
                    tags = set(form.get('tags', []))
                    if not record['reading'] and tags & {'romanization', 'canonical'} and form.get('form') != text:
                        record['reading'] = clean(form.get('form', ''))
                if not record['ipa']:
                    for sound in entry.get('sounds', []):
                        if sound.get('ipa'):
                            record['ipa'] = clean(sound['ipa']).strip('/[]')
                            break
                for sense in entry.get('senses', []):
                    for base in sense.get('form_of', []) + sense.get('alt_of', []):
                        lemma = clean(base.get('word', ''))
                        if lemma and lemma != text and lemma not in record['lemmas']:
                            record['lemmas'].append(lemma)
                    if sense.get('form_of') or len(record['en']) >= MAX_SENSES:
                        continue
                    gloss = gloss_of(sense)
                    if gloss:
                        gloss = f'{pos} {gloss}'.strip()
                        if gloss not in record['en']:
                            record['en'].append(gloss)
                # Forms listed on the lemma's own page: hablo → hablar.
                for form in entry.get('forms', []):
                    if set(form.get('tags', [])) & SKIP_FORM_TAGS:
                        continue
                    other = clean(form.get('form', ''))
                    if other and other != text and WORD.match(other):
                        lemmas = word_of(other)['lemmas']
                        if text not in lemmas and len(lemmas) < 6:
                            lemmas.append(text)

        kept = 0
        out_path = f'{out_dir}/{code}-wiktionary.tsv'
        with open(out_path, 'w', encoding='utf-8', newline='\n') as out:
            for text in sorted(words):
                record = words[text]
                zh = chinese[code].get(text, [])
                if not (zh or record['en'] or record['lemmas']):
                    continue
                out.write('\t'.join([
                    text, record['reading'], record['ipa'], '|'.join(record['pos']),
                    '\\n'.join(zh), '\\n'.join(record['en']), '|'.join(record['lemmas'][:6]),
                ]) + '\n')
                kept += 1
        with_zh = sum(1 for t in words if chinese[code].get(t))
        print(f'{code}: {kept} words, {with_zh} with Chinese meanings', flush=True)
        if kept < MIN_WORDS:
            sys.exit(f'{code}: only {kept} words')


if __name__ == '__main__':
    main()
