"""Gives the Japanese word list Chinese meanings.

    ja_zh.py ZH_EXTRACT JA_TSV [WIKDICT]

ZH_EXTRACT is kaikki.org's extract of the Chinese Wiktionary (gzipped
JSONL, CC BY-SA 4.0); its Japanese entries are written in Chinese.
WIKDICT, WikDict's ja-zh SQLite dictionary (CC BY-SA), fills in words the
Chinese Wiktionary lacks. JA_TSV is the JMdict list built before it
(kanji forms, kana forms, parts of speech, English senses, common),
rewritten in place with a sixth column: Chinese meanings, a literal \\n
between them, empty where neither source has the word.

A meaning goes to the JMdict entry written the same way; when several
are, the one read as the Chinese Wiktionary says, else the common one.
"""
import gzip
import json
import re
import sqlite3
import sys
from collections import defaultdict

# Simplified characters for the learners the meanings are for; without
# the converter the pack would mix in Traditional ones, so it is required.
import opencc
simplified = opencc.OpenCC('t2s').convert

MAX_SENSES = 6
KANA = re.compile(r'^[ぁ-ゟ゠-ヿー]+$')
POS = {
    'noun': 'n.', 'verb': 'v.', 'adj': 'adj.', 'adv': 'adv.', 'pron': 'pron.', 'conj': 'conj.', 'intj': 'int.',
    'num': 'num.', 'particle': 'part.', 'suffix': 'suf.', 'prefix': 'pref.', 'phrase': 'phr.', 'counter': 'cnt.',
}


def clean(text):
    return re.sub(r'\s+', ' ', str(text or '')).replace('\t', ' ').replace('\\n', ' ').strip()


# A dictionary line's own head: 属する【ぞくする】.
HEAD = re.compile(r'^\S*【[^】]*】\s*')
# Japanese dictionaries' part-of-speech marks: 自サ, 他五, 自他下一, 名, 形动…
POS_MARK = re.compile(r'^(?:[自他]{1,2}(?:サ|カ|ザ|[五上下][一二]?|変)?|名|代|形|形动|形動|副|连体|連体|接|感|助|助动|助動|接头|接尾)(?:\s+|(?=[^\s\w]))')
JAPANESE = re.compile(r'[ぁ-ゟ゠-ヿ]')


def tidy(gloss):
    """[gloss] as a meaning: without the word's own head, part-of-speech
    marks or the example sentences some sources run on after it."""
    gloss = HEAD.sub('', gloss)
    while True:
        bare = POS_MARK.sub('', gloss, count=1)
        if bare == gloss:
            break
        gloss = bare
    # 属于。 美術部に属する 属于美术部。 → 属于: what follows the first
    # full stop is an example when it has kana in it.
    first, stop, rest = gloss.partition('。')
    if stop and JAPANESE.search(rest):
        gloss = first
    return gloss.strip(' 。；;，,')


def add(found, gloss):
    """Adds [gloss] unless it, or the same with other punctuation, is in."""
    def key(text):
        # Without a part of speech in front (v. 嘱托) or punctuation.
        return re.sub(r'[\s，,；;、。]', '', re.sub(r'^[a-z]+\.\s', '', text))
    if gloss and key(gloss) and all(key(g) != key(gloss) for g in found):
        found.append(gloss)


def readings_of(entry):
    """The kana an entry of the Chinese Wiktionary gives for its word."""
    found = []
    for form in entry.get('forms') or []:
        text = clean(form.get('form') if isinstance(form, dict) else '')
        if KANA.match(text) and text not in found:
            found.append(text)
    for key in ('hiragana', 'katakana'):
        text = clean(entry.get(key))
        if KANA.match(text) and text not in found:
            found.append(text)
    return found


def main():
    zh_path, ja_tsv, *rest = sys.argv[1:]
    wikdict = rest[0] if rest else ''

    rows = []
    by_form = defaultdict(list)
    with open(ja_tsv, encoding='utf-8') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            parts += [''] * (6 - len(parts))
            rows.append(parts[:6])
            i = len(rows) - 1
            kanji = [k for k in parts[0].split('|') if k]
            for form in kanji or [k for k in parts[1].split('|') if k]:
                by_form[form].append(i)

    def place(word, readings):
        """The row [word] belongs to, or None."""
        found = by_form.get(word) or []
        if readings:
            read = [i for i in found if set(rows[i][1].split('|')) & set(readings)]
            found = read or found
        if not found:
            return None
        common = [i for i in found if rows[i][4] == '1']
        return (common or found)[0]

    chinese = defaultdict(list)
    from_wiktionary = 0
    with gzip.open(zh_path, 'rt', encoding='utf-8') as f:
        for line in f:
            if '"lang_code": "ja"' not in line and '"lang_code":"ja"' not in line:
                continue
            entry = json.loads(line)
            if entry.get('lang_code') != 'ja':
                continue
            word = clean(entry.get('word'))
            row = place(word, readings_of(entry)) if word else None
            if row is None:
                continue
            pos = POS.get(entry.get('pos', ''), '')
            found = chinese[row]
            before = len(found)
            for sense in entry.get('senses') or []:
                if sense.get('form_of') or sense.get('alt_of') or len(found) >= MAX_SENSES:
                    continue
                glosses = sense.get('glosses') or sense.get('raw_glosses') or []
                gloss = tidy(simplified(clean(glosses[-1]))) if glosses else ''
                if not gloss:
                    continue
                add(found, f'{pos} {gloss}' if pos and not gloss.startswith(pos) else gloss)
            if len(found) > before and before == 0:
                from_wiktionary += 1

    from_wikdict = 0
    if wikdict:
        with sqlite3.connect(wikdict) as db:
            for word, translations, score in db.execute('select written_rep, trans_list, max_score from simple_translation'):
                word = clean(word)
                if not word or not translations or float(score or 0) < 1:
                    continue
                row = place(word, [])
                if row is None or chinese.get(row):
                    continue
                meaning = '；'.join(dict.fromkeys(t for t in (tidy(simplified(clean(t))) for t in str(translations).split('|')) if t))
                if meaning:
                    chinese[row] = [meaning]
                    from_wikdict += 1

    with open(ja_tsv, 'w', encoding='utf-8', newline='\n') as out:
        for i, parts in enumerate(rows):
            parts[5] = '\\n'.join(chinese.get(i, []))
            out.write('\t'.join(parts) + '\n')
    common = sum(1 for r in rows if r[4] == '1')
    common_zh = sum(1 for i, r in enumerate(rows) if r[4] == '1' and chinese.get(i))
    print(f'ja: Chinese meanings for {len(chinese)} of {len(rows)} entries ({from_wiktionary} from the Chinese Wiktionary, '
          f'{from_wikdict} from WikDict); common words {common_zh} of {common}', flush=True)
    if len(chinese) < 5000:
        sys.exit('too few Chinese meanings for Japanese')


if __name__ == '__main__':
    main()
