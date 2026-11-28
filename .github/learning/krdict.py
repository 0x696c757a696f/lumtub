"""Puts the Korean Basic Dictionary (한국어기초사전, National Institute of
Korean Language, CC BY-SA 2.0 KR) into the Korean word list ahead of
Wiktionary: every one of its 50,000-odd words has Chinese meanings and a
learner's level.

    krdict.py VOCAB_DIR KO_TSV

VOCAB_DIR is a checkout of github.com/basickorean/basickorean-vocab (the
dictionary's open data as JSON shards: shards/core/<key>.json and
shards/tr/<lang>/<key>.json). KO_TSV is wiktionary.py's Korean list,
rewritten in place: a word the Basic Dictionary has takes its meanings,
reading (pronunciation in Hangul), level and forms, keeping Wiktionary's
IPA and base words; other words stay as they were.

Two columns are added to every line: the level (1 beginner, 2
intermediate, 3 advanced: the dictionary's own 초급/중급/고급, not TOPIK)
and where the meanings come from (`krdict`, or empty for Wiktionary).
"""

import glob
import json
import os
import re
import sys

MAX_SENSES = 8
LEVELS = {'초급': '1', '중급': '2', '고급': '3'}
POS = {
    '명사': 'n.',
    '의존 명사': 'n.',
    '동사': 'v.',
    '보조 동사': 'v.',
    '형용사': 'adj.',
    '보조 형용사': 'adj.',
    '부사': 'adv.',
    '대명사': 'pron.',
    '수사': 'num.',
    '관형사': 'det.',
    '조사': 'part.',
    '어미': 'suf.',
    '접사': 'affix',
    '감탄사': 'int.',
}
# The Chinese translation's '(无对应词汇)': no word for it, only the explanation.
NO_EQUIVALENT = re.compile(r'^[(（]\s*无对应词汇\s*[)）]$')
PHRASES = {'관용구': 'idiom', '속담': 'proverb', '구': 'phr.', '문법‧표현': 'gram.'}


def clean(text):
    return re.sub(r'\s+', ' ', str(text or '')).replace('\\n', ' ').strip()


def load(path):
    try:
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def senses(tr, homograph):
    """[[equivalent, meaning], …] of one homograph in a translation shard."""
    if not isinstance(tr, list):
        return []
    group = tr[homograph] if homograph < len(tr) else []
    return (
        [s for s in group if isinstance(s, list) and len(s) >= 1] if isinstance(group, list) else []
    )


def main():
    vocab, ko_tsv = sys.argv[1:]
    shards = os.path.join(vocab, 'shards')
    words = {}
    for path in sorted(glob.glob(os.path.join(shards, 'core', '*.json'))):
        key = os.path.basename(path)
        zh = load(os.path.join(shards, 'tr', 'zh', key))
        en = load(os.path.join(shards, 'tr', 'en', key))
        for written, entries in load(path).items():
            word = clean(written)
            if not word or not isinstance(entries, list) or '\t' in word:
                continue
            record = {'reading': '', 'pos': [], 'zh': [], 'en': [], 'level': '', 'forms': []}

            # Homographs a learner meets first come first: 먹다 'eat'
            # (beginner) before 먹다 'be deaf' (no level).
            def rank(item):
                h, entry = item
                return (
                    LEVELS.get(entry.get('lvk', ''), '9') if isinstance(entry, dict) else '9',
                    h,
                )

            for h, entry in sorted(enumerate(entries), key=rank):
                if not isinstance(entry, dict):
                    continue
                pos = POS.get(entry.get('p', ''), '') or PHRASES.get(entry.get('u', ''), '')
                if pos and pos not in record['pos']:
                    record['pos'].append(pos)
                if not record['reading'] and clean(entry.get('pr')) not in ('', word):
                    record['reading'] = clean(entry.get('pr'))
                level = LEVELS.get(entry.get('lvk', ''), '')
                if level and (not record['level'] or level < record['level']):
                    record['level'] = level
                for raw_form in entry.get('fm') or []:
                    form = clean(raw_form)
                    if form and form != word and form not in record['forms']:
                        record['forms'].append(form)
                prefix = f'{pos} ' if pos else ''
                for equivalent, *meaning in senses(zh.get(word), h):
                    line = NO_EQUIVALENT.sub('', clean(equivalent))
                    if meaning and clean(meaning[0]):
                        line = f'{line}：{clean(meaning[0])}' if line else clean(meaning[0])
                    if line and len(record['zh']) < MAX_SENSES:
                        record['zh'].append(prefix + line)
                for equivalent, *_ in senses(en.get(word), h):
                    if clean(equivalent) and len(record['en']) < MAX_SENSES:
                        record['en'].append(prefix + clean(equivalent))
            if record['zh'] or record['en']:
                words[word] = record
    if len(words) < 40000:
        sys.exit(f'only {len(words)} words in the Basic Dictionary')

    lines = []
    seen = set()
    with open(ko_tsv, encoding='utf-8') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            parts += [''] * (9 - len(parts))
            word = parts[0]
            record = words.get(word)
            if record and word not in seen:
                seen.add(word)
                parts[1] = record['reading'] or parts[1]
                parts[3] = '|'.join(record['pos'])
                parts[4] = '\\n'.join(record['zh'])
                parts[5] = '\\n'.join(record['en'])
                parts[7] = record['level']
                parts[8] = 'krdict'
            lines.append(parts[:9])
    for word in sorted(set(words) - seen):
        record = words[word]
        lines.append(
            [
                word,
                record['reading'],
                '',
                '|'.join(record['pos']),
                '\\n'.join(record['zh']),
                '\\n'.join(record['en']),
                '',
                record['level'],
                'krdict',
            ]
        )
    # Its forms (가는, 갑니다) lead to the word; a form only, so no meanings.
    for word, record in sorted(words.items()):
        for form in record['forms'][:12]:
            lines.append([form, '', '', '', '', '', word, '', ''])
    with open(ko_tsv, 'w', encoding='utf-8', newline='\n') as out:
        for parts in lines:
            out.write('\t'.join(parts) + '\n')
    levels = {n: sum(1 for r in words.values() if r['level'] == n) for n in '123'}
    print(
        f'ko: {len(words)} words from the Basic Dictionary ({len(words) - len(seen)} new), '
        f'levels {levels}',
        flush=True,
    )


if __name__ == '__main__':
    main()
