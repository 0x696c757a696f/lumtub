"""Builds the items of the learning pack's level test, one file a language.

    level_test.py OUT_DIR LEVELS_DIR [lex:LANG=SQLITE ...] [cedict=CEDICT_TXT]
                  [jmdict=JA_TSV] [unihan=UNIHAN_ZIP]

The test is a yes/no vocabulary test: real words, drawn from each level
of LEVELS_DIR/<lang>-levels.tsv.gz (made by levels.py; English from the
exam tags of its dictionary), mixed with made-up words, which catch
learners who say yes to everything. Writes OUT_DIR/<lang>-leveltest.tsv.gz:

    w<TAB>level<TAB>text[<TAB>traditional]     a real word
    n<TAB>level<TAB>text[<TAB>traditional]     a made-up word, shaped like
                                               a real word of that level

No item comes from a published test. The made-up words are our own,
from our own word lists:

- en, es, fr, de, it, pt: Wuggy's idea (Keuleers & Brysbaert 2010), written
  anew: a real word cut into consonant and vowel groups, about half of
  them swapped for groups that follow and precede their neighbours at
  that place in real words.
- ru, ko: a chain of letters (Russian) or of whole syllable blocks
  (Korean, so only blocks real words use) that real words show at each
  place, as UniPseudo does, written anew.
- zh: two characters, the first from those that start real two-character
  words and the second from those that end them, each as common and with
  about as many strokes as the real word's.
- ja: kanji pairs the same way, and hiragana words as a chain of morae;
  no katakana.

Every made-up word is checked against the dictionaries (CC-CEDICT and
JMdict both for Chinese and Japanese) and wordfreq, so it is no word,
word form, or reversed word; Western ones are also not a common word with
one letter changed, nor two words joined.
"""
import gzip
import math
import os
import random
import re
import sqlite3
import sys
import unicodedata
import zipfile
from collections import Counter, defaultdict

from wordfreq import get_frequency_dict, top_n_list

try:
    import opencc
    to_traditional = opencc.OpenCC('s2t').convert
    to_simplified = opencc.OpenCC('t2s').convert
except ImportError:
    to_traditional = to_simplified = None

# Real words kept a level, made-up words made a level.
REAL = 300
MADE = 150
# The English bands: the lowest exam list a word is on, as EnglishLevel.
ENGLISH = [['zk'], ['gk'], ['cet4'], ['cet6'], ['ky'], ['toefl', 'ielts'], ['gre']]
VOWELS = {
    'en': 'aeiouy',
    'es': 'aeiouáéíóúü',
    'fr': 'aeiouyàâäéèêëîïôöùûüÿœæ',
    'de': 'aeiouyäöü',
    'it': 'aeiouàèéìíòóù',
    'pt': 'aeiouáâãàéêíóôõú',
}
LATIN = {'en': 'a-z', 'es': 'a-zñáéíóúü', 'fr': 'a-zàâäçéèêëîïôöùûüÿœæ', 'de': 'a-zäöüß', 'it': 'a-zàèéìíòóù', 'ru': 'а-яё', 'pt': 'a-záâãàçéêíóôõú'}
HAN = re.compile(r'^[一-鿿]+$')
HIRAGANA = re.compile(r'^[ぁ-ゖー]+$')
HANGUL = re.compile(r'^[가-힣]+$')
SMALL = set('ゃゅょぁぃぅぇぉゎ')

rng = random.Random(20261123)


def nfc(s):
    return unicodedata.normalize('NFC', s)


def read_levels(path):
    levels = {}
    with gzip.open(path, 'rt', encoding='utf-8') as f:
        for line in f:
            word, _, level = line.rstrip('\n').partition('\t')
            if level.isdigit():
                levels[word] = int(level)
    return levels


class Lexicon:
    """Every spelling a dictionary knows, and which are headwords."""

    def __init__(self, path):
        self.keys = set()
        self.lower = set()
        self.heads = set()
        con = sqlite3.connect(path)
        for key, form in con.execute('SELECT key, form FROM term'):
            key = nfc(key)
            self.keys.add(key)
            self.lower.add(key.lower())
            if form == 0:
                self.heads.add(key)
        con.close()

    def knows(self, word):
        return word in self.keys or word.lower() in self.lower


def weighted(counter):
    items = list(counter.items())
    total = sum(c for _, c in items)
    r = rng.random() * total
    for item, c in items:
        r -= c
        if r <= 0:
            return item
    return items[-1][0]


def deletions(word):
    return {word[:i] + word[i + 1:] for i in range(len(word))}


class NearWords:
    """Whether a word is one letter added, dropped, changed or swapped
    away from a common word: a typo, not a new word."""

    def __init__(self, words):
        self.words = set(words)
        self.deleted = set()
        for w in words:
            self.deleted |= deletions(w)

    def near(self, word):
        if word in self.words or word in self.deleted:
            return True
        return any(d in self.words or d in self.deleted for d in deletions(word))


def joined(word, heads, least):
    """Whether [word] is two dictionary words run together, each at least
    [least] long, with a German linking s allowed."""
    for i in range(least, len(word) - least + 1):
        a, b = word[:i], word[i:]
        if b in heads and (a in heads or (a.endswith('s') and a[:-1] in heads)):
            return True
    return False


# Western languages ---------------------------------------------------------

def groups(word, vowels):
    return re.findall(f'[{vowels}]+|[^{vowels}]+', word)


def place(i, n):
    return 'B' if i == 0 else ('E' if i == n - 1 else 'M')


class GroupModel:
    """Which letter groups follow which at the start, middle and end of
    real words."""

    def __init__(self, words, vowels):
        self.vowels = vowels
        self.pairs = Counter()
        self.at = defaultdict(Counter)
        for w in words:
            g = groups(w, vowels)
            prev = '^'
            for i, s in enumerate(g):
                p = place(i, len(g))
                self.pairs[(p, prev, s)] += 1
                self.at[(p, s[0] in vowels)][s] += 1
                prev = s
            self.pairs[('$', prev, '$')] += 1

    def follows(self, p, prev, s):
        return self.pairs[(p, prev, s)] >= 2

    def made_from(self, word):
        g = groups(word, self.vowels)
        n = len(g)
        if n < 2:
            return None
        for _ in range(60):
            swap = set(rng.sample(range(n), max(1, round(n / 2))))
            out = []
            prev = '^'
            ok = True
            for i, s in enumerate(g):
                p = place(i, n)
                if i not in swap:
                    if not self.follows(p, prev, s):
                        ok = False
                        break
                    out.append(s)
                    prev = s
                    continue
                nxt = g[i + 1] if i + 1 < n and i + 1 not in swap else None
                choices = Counter()
                for x, c in self.at[(p, s[0] in self.vowels)].items():
                    if x == s or abs(len(x) - len(s)) > 1 or not self.follows(p, prev, x):
                        continue
                    if nxt is not None and not self.follows(place(i + 1, n), x, nxt):
                        continue
                    if i == n - 1 and not self.follows('$', x, '$'):
                        continue
                    choices[x] = c
                if not choices:
                    ok = False
                    break
                x = weighted(choices)
                out.append(x)
                prev = x
            if ok:
                return ''.join(out)
        return None


class CharModel:
    """Which unit follows the two before it at each place in real words:
    letters for Russian, syllable blocks or morae otherwise."""

    def __init__(self, words, cut=list, before=2):
        # Korean blocks are syllables: one before is enough, and two would
        # mostly give back the real words.
        self.before = before
        self.next = defaultdict(Counter)
        self.ends = set()
        for w in words:
            units = ['^', '^'] + cut(w)
            for i in range(2, len(units)):
                self.next[self._key(i - 2, units[:i])][units[i]] += 1
            self.ends.add(tuple(units[-self.before:]))

    def _key(self, i, units):
        return (min(i, 9), *units[-self.before:])

    def made(self, length):
        for _ in range(200):
            units = ['^', '^']
            for i in range(length):
                choices = self.next.get(self._key(i, units))
                if not choices:
                    break
                if i == length - 1:
                    choices = Counter({u: c for u, c in choices.items() if tuple((units + [u])[-self.before:]) in self.ends})
                    if not choices:
                        break
                units.append(weighted(choices))
            else:
                return units[2:]
        return None


def morae(word):
    out = []
    for ch in word:
        if ch in SMALL and out:
            out[-1] += ch
        else:
            out.append(ch)
    return out


def take(items, k):
    items = list(items)
    rng.shuffle(items)
    return items[:k]


def common_words(lang, n):
    return [nfc(w) for w in top_n_list(lang, n, wordlist='best')]


def western(lang, bands, lexicon, english=False):
    """Real words by level, and made-up words like them."""
    letters = re.compile(f'^[{LATIN[lang]}]{{3,12}}$')
    reals = defaultdict(list)
    for word, level in bands.items():
        if not letters.match(word):
            continue
        if word in lexicon.heads:
            reals[level].append(word)
        elif lang == 'de' and word.capitalize() in lexicon.heads:
            reals[level].append(word.capitalize())
    common = common_words(lang, 300000)
    known = set(common) | lexicon.lower
    heads = {h.lower() for h in lexicon.heads if len(h) >= 3}
    near = NearWords([w for w in common[:5000] if len(w) >= 3])
    training = [w for w in common[:60000] if letters.match(w) and (w in lexicon.heads or w.capitalize() in lexicon.heads)]
    if lang == 'ru':
        model = CharModel(training)
        make = lambda w: ''.join(model.made(len(w)) or [])
    else:
        model = GroupModel(training, VOWELS[lang])
        make = lambda w: model.made_from(w.lower())
    made = defaultdict(list)
    seen = set()
    for level, words in reals.items():
        for word in take(words, MADE * 4):
            if len(made[level]) >= MADE:
                break
            x = next((x for x in (make(word) for _ in range(5)) if x and abs(len(x) - len(word)) <= 1), None)
            if not x or x in seen or not letters.match(x) or x in known or near.near(x) or joined(x, heads, 3):
                continue
            seen.add(x)
            made[level].append(x.capitalize() if word[0].isupper() else x)
    return reals, made


def english_bands(path):
    """English headwords at the lowest exam list they are on."""
    bands = {}
    con = sqlite3.connect(path)
    for word, line in con.execute('SELECT t.key, e.line FROM term t JOIN entry e ON e.id = t.entry WHERE t.form = 0'):
        tags = set(line.split('\t')[4].split()) if line.count('\t') >= 4 else set()
        for level, names in enumerate(ENGLISH, start=1):
            if tags & set(names):
                if word not in bands or level < bands[word]:
                    bands[word] = level
                break
    con.close()
    return bands


# Chinese and Japanese ------------------------------------------------------

def strokes_of(path):
    strokes = {}
    if not path:
        return strokes
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if not name.endswith('.txt'):
                continue
            for line in z.read(name).decode('utf-8').splitlines():
                parts = line.split('\t')
                if len(parts) == 3 and parts[1] == 'kTotalStrokes':
                    strokes[chr(int(parts[0][2:], 16))] = int(parts[2].split()[0])
    return strokes


def char_frequency(lang):
    """How often each character is met in running text, as log10."""
    freq = Counter()
    for word, f in get_frequency_dict(lang, wordlist='best').items():
        for ch in word:
            freq[ch] += f
    return {ch: math.log10(f) for ch, f in freq.items() if f > 0}


# Grammar characters, which make a pair read as a phrase or as nonsense.
GRAMMAR = set('的了着过是不没在有之于而以其也和与及或就都再更很最又所被把从对向为给让这那你我他她它们吗呢吧啊么个和乎者矣焉哉')


def han_pairs(words):
    """The characters that start and that end real two-character words."""
    first, second = Counter(), Counter()
    for w in words:
        if len(w) == 2 and HAN.match(w) and not (set(w) & GRAMMAR):
            first[w[0]] += 1
            second[w[1]] += 1
    # Each character only where it is mostly found: 化 ends words, 微 starts them.
    return ({c for c, n in first.items() if n >= 5 and n >= second[c]}, {c for c, n in second.items() if n >= 5 and n >= first[c]})


def like(ch, pool, freq, strokes):
    """A character from [pool] about as common and as complex as [ch]."""
    f = freq.get(ch)
    if f is None:
        return None
    s = strokes.get(ch)
    choices = [c for c in pool if c != ch and c in freq and abs(freq[c] - f) <= 0.4 and (s is None or c not in strokes or abs(strokes[c] - s) <= 2)]
    return rng.choice(choices) if choices else None


def han_made(reals, pools, freq, strokes, taken):
    made = defaultdict(list)
    seen = set()
    first, second = pools
    for level, words in reals.items():
        for word in take(words, MADE * 6):
            if len(made[level]) >= MADE:
                break
            a, b = like(word[0], first, freq, strokes), like(word[1], second, freq, strokes)
            if not a or not b or a == b:
                continue
            x = a + b
            if x in seen or taken(x) or taken(b + a):
                continue
            seen.add(x)
            made[level].append(x)
    return made


def read_cedict(path):
    words = set()
    with open(path, encoding='utf-8') as f:
        for line in f:
            if line.startswith('#'):
                continue
            parts = line.split(' ', 2)
            if len(parts) == 3:
                words.add(parts[0])
                words.add(parts[1])
    return words


def inside(words):
    """Every two-character run inside a longer word."""
    runs = set()
    for w in words:
        for i in range(len(w) - 1):
            runs.add(w[i:i + 2])
    return runs


def chinese(levels, cedict, strokes):
    reals = defaultdict(list)
    for word, level in levels.items():
        if len(word) == 2 and HAN.match(word) and (to_simplified is None or to_simplified(word) == word):
            reals[level].append(word)
    common = set(common_words('zh', 300000))
    runs = inside(cedict) | inside(common)
    taken = lambda x: x in cedict or x in common or x in runs or x in levels
    pools = han_pairs([w for w in cedict if to_simplified is None or to_simplified(w) == w])
    return reals, han_made(reals, pools, char_frequency('zh'), strokes, taken)


def read_jmdict(path):
    kanji, kana, kana_only = set(), set(), set()
    with open(path, encoding='utf-8') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) < 2:
                continue
            forms = [k for k in parts[0].split('|') if k]
            readings = [k for k in parts[1].split('|') if k]
            kanji.update(forms)
            kana.update(readings)
            if not forms:
                kana_only.update(readings)
    return kanji, kana, kana_only


def japanese(levels, jmdict, cedict, strokes):
    kanji, kana, kana_only = jmdict
    reals = defaultdict(list)
    kana_reals = defaultdict(list)
    for word, level in levels.items():
        if len(word) == 2 and HAN.match(word):
            reals[level].append(word)
        elif HIRAGANA.match(word) and word in kana_only and 2 <= len(morae(word)) <= 6:
            kana_reals[level].append(word)
    common = set(common_words('ja', 300000))
    runs = inside(kanji) | inside(cedict) | inside(common)

    def taken(x):
        if x in kanji or x in cedict or x in common or x in runs or x in levels:
            return True
        return to_simplified is not None and to_simplified(x) in cedict

    made = han_made(reals, han_pairs(kanji), char_frequency('ja'), strokes, taken)
    model = CharModel([k for k in kana if HIRAGANA.match(k)], cut=morae)
    seen = set()
    for level, words in kana_reals.items():
        count = 0
        for word in take(words, MADE * 4):
            if count >= MADE // 3:
                break
            units = model.made(len(morae(word)))
            x = ''.join(units or [])
            if not x or x in seen or x in kana or x in common or x in levels:
                continue
            seen.add(x)
            made[level].append(x)
            count += 1
        reals[level] += kana_reals[level]
    return reals, made


# Korean --------------------------------------------------------------------

def korean(levels, lexicon):
    reals = defaultdict(list)
    for word, level in levels.items():
        # Not verbs and adjectives: their 다 would tell them from made-up
        # words, which a chain of syllables leaves as stems.
        if HANGUL.match(word) and 2 <= len(word) <= 4 and word in lexicon.heads and not word.endswith('다'):
            reals[level].append(word)
    training = [w for w in lexicon.heads if HANGUL.match(w) and 2 <= len(w) <= 5 and not w.endswith('다')]
    model = CharModel(training, before=1)
    common = set(common_words('ko', 300000))
    heads = {h for h in lexicon.heads if HANGUL.match(h) and len(h) >= 2}
    # The start of a longer word (에스토니 of 에스토니아) reads as a word.
    starts = {w[:i] for w in heads | common for i in range(2, len(w))}
    made = defaultdict(list)
    seen = set()
    for level, words in reals.items():
        for word in take(words, MADE * 12):
            if len(made[level]) >= MADE:
                break
            x = ''.join(model.made(len(word)) or [])
            # Nor a word with a syllable added: 결산하 is 결산 and the stem of 하다.
            if not x or x in seen or lexicon.knows(x) or x in common or x in levels or joined(x, heads, 2):
                continue
            if x[:-1] in heads or x[1:] in heads or x.endswith('하') or x in starts:
                continue
            seen.add(x)
            made[level].append(x)
    return reals, made


# Output --------------------------------------------------------------------

def write(out, lang, reals, made, least_levels, traditional=False):
    levels = sorted(set(reals) & set(made))
    short = [lv for lv in levels if len(reals[lv]) < 20 or len(made[lv]) < 10]
    if len(levels) < least_levels or short:
        sys.exit(f'{lang}: too few items: real {dict((k, len(v)) for k, v in sorted(reals.items()))}, made {dict((k, len(v)) for k, v in sorted(made.items()))}')
    path = os.path.join(out, f'{lang}-leveltest.tsv.gz')
    lines = []
    for level in levels:
        for kind, words in (('w', take(reals[level], REAL)), ('n', made[level][:MADE])):
            for word in sorted(words):
                if '\t' in word or '\n' in word:
                    continue
                row = [kind, str(level), word]
                if traditional and to_traditional is not None:
                    row.append(to_traditional(word))
                lines.append('\t'.join(row))
    with gzip.GzipFile(path, 'wb', compresslevel=9, mtime=0) as f:
        f.write(('# lumtub level test v1\n' + '\n'.join(lines) + '\n').encode('utf-8'))
    counts = {lv: f'{min(len(reals[lv]), REAL)}+{min(len(made[lv]), MADE)}' for lv in levels}
    samples = ' '.join(made[levels[len(levels) // 2]][:8])
    print(f'{lang} level test: real+made by level {counts}; made-up words such as {samples}', flush=True)


def main():
    out, levels_dir, *args = sys.argv[1:]
    given = dict(a.split('=', 1) for a in args)
    strokes = strokes_of(given.get('unihan'))
    if 'unihan' in given and len(strokes) < 50000:
        sys.exit(f'only {len(strokes)} stroke counts')
    level_file = lambda lang: os.path.join(levels_dir, f'{lang}-levels.tsv.gz')
    cedict = read_cedict(given['cedict']) if 'cedict' in given else set()
    if 'cedict' in given:
        write(out, 'zh', *chinese(read_levels(level_file('zh')), cedict, strokes), 6, traditional=True)
    if 'jmdict' in given:
        write(out, 'ja', *japanese(read_levels(level_file('ja')), read_jmdict(given['jmdict']), cedict, strokes), 5)
    for key, path in given.items():
        if not key.startswith('lex:'):
            continue
        lang = key[4:]
        lexicon = Lexicon(path)
        if lang == 'en':
            write(out, 'en', *western('en', english_bands(path), lexicon), 6)
        elif lang == 'ko':
            write(out, 'ko', *korean(read_levels(level_file('ko')), lexicon), 3)
        else:
            write(out, lang, *western(lang, read_levels(level_file(lang)), lexicon), 6)


if __name__ == '__main__':
    main()
