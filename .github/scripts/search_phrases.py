#!/usr/bin/env python3
"""Translates Explore's built-in search phrases into every language the
language filter offers, for assets/search_phrases.json.

The phrases (.github/search_phrases/phrases.txt) are what the zones search
for once their Chinese keywords are put into English (lib/explore_pivots.dart);
the app asks a translator only for phrases this file lacks. Phrases already
translated are kept, so a run only asks for new phrases and languages.
"""
import json
import sys
import time
import urllib.parse
import urllib.request

HERE = '.github/search_phrases'
OUT = 'assets/search_phrases.json'
# The app's codes Google spells otherwise.
GOOGLE = {'jv': 'jw', 'he': 'iw'}
LINES = 40


def ask(lines, target):
    query = urllib.parse.urlencode({'client': 'gtx', 'sl': 'en', 'tl': GOOGLE.get(target, target), 'dt': 't', 'q': '\n'.join(lines)})
    for attempt in range(6):
        try:
            with urllib.request.urlopen('https://translate.googleapis.com/translate_a/single?' + query, timeout=30) as reply:
                data = json.loads(reply.read().decode('utf-8'))
            text = ''.join(part[0] for part in data[0] if part and isinstance(part[0], str))
            out = [line.strip() for line in text.split('\n')]
            if len(out) != len(lines):
                raise ValueError(f'{len(out)} lines for {len(lines)}')
            return out
        except Exception as error:  # noqa: BLE001 - every failure is retried the same way
            wait = 5 * 2 ** attempt
            print(f'{target}: {error}; again in {wait} s', file=sys.stderr)
            time.sleep(wait)
    return None


def main():
    phrases = [p for p in open(f'{HERE}/phrases.txt', encoding='utf-8').read().splitlines() if p.strip()]
    languages = [l for l in open(f'{HERE}/languages.txt', encoding='utf-8').read().splitlines() if l.strip()]
    try:
        known = json.load(open(OUT, encoding='utf-8'))
    except FileNotFoundError:
        known = {}
    failed = []
    for target in languages:
        have = known.setdefault(target, {})
        missing = [p for p in phrases if p not in have]
        for i in range(0, len(missing), LINES):
            batch = missing[i:i + LINES]
            lines = ask(batch, target)
            if lines is None:
                failed.append(target)
                break
            for phrase, line in zip(batch, lines):
                if line:
                    have[phrase] = line
            time.sleep(1)
        print(f'{target}: {len(have)} of {len(phrases)}')
    # Phrases no zone searches any more are dropped.
    wanted = set(phrases)
    known = {lang: {p: t for p, t in sorted(known[lang].items()) if p in wanted} for lang in languages if lang in known}
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(known, f, ensure_ascii=False, indent=0, sort_keys=True)
        f.write('\n')
    if failed:
        print('Not finished: ' + ' '.join(failed), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
