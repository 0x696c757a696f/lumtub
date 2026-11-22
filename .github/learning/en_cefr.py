"""Adds CEFR levels to the English pack's word list.

    en_cefr.py EN_TSV CEFRJ_CSV OCTANOVE_CSV

CEFRJ_CSV is the CEFR-J Wordlist 1.5 (A1–B2; free for research and
commercial use with citation, (c) Tono Laboratory, Tokyo University of
Foreign Studies) and OCTANOVE_CSV the Octanove Vocabulary Profile C1/C2
1.0 (CC BY-SA 4.0), both from github.com/openlanguageprofiles/olp-en-cefrj.
The word list gets a ninth column: the lowest level a word is listed at
(any part of speech), empty for words neither lists. Rewritten in place.
"""
import csv
import sys

ORDER = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2']


def main():
    tsv, *lists = sys.argv[1:]
    levels = {}
    for path in lists:
        with open(path, newline='', encoding='utf-8') as f:
            for row in csv.DictReader(f):
                level = (row.get('CEFR') or '').strip().upper()
                if level not in ORDER:
                    continue
                # "a.m./A.M./am/AM": every spelling.
                for word in (row.get('headword') or '').split('/'):
                    word = word.strip().lower()
                    if word and (word not in levels or ORDER.index(level) < ORDER.index(levels[word])):
                        levels[word] = level
    with open(tsv, encoding='utf-8') as f:
        rows = [line.rstrip('\n').split('\t') for line in f]
    found = 0
    with open(tsv, 'w', encoding='utf-8', newline='\n') as out:
        for row in rows:
            while len(row) < 9:
                row.append('')
            row[8] = levels.get(row[0].lower(), '')
            found += bool(row[8])
            out.write('\t'.join(row) + '\n')
    print(f'CEFR levels: {len(levels)} listed, {found} of {len(rows)} words placed', flush=True)
    if found < 5000:
        sys.exit('too few CEFR levels')


if __name__ == '__main__':
    main()
