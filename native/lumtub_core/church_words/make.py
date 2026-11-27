"""Writes hans.tsv and hant.tsv from terms.json and extra.json for church_words.rs.

terms.json is the Protestant (和合本) to Catholic (思高本) table of
github.com/0x696c757a696f/thechosen-dualsub, in simplified Chinese (its
Bible names come from github.com/baibanbao/cuv-with-sigao-names).
cases.json is that project's test cases. Each
line of a .tsv is one rule of that direction: Protestant word, Catholic
word, the characters that may not come before it, those that may not come
after it. Traditional forms come from OpenCC's s2tw (pip install opencc),
as Google and Microsoft write zh-TW; a context character is kept in every
traditional form OpenCC's STCharacters.txt gives it (迹: 跡 and 蹟).

    python3 make.py
"""

import json
import pathlib
import urllib.request

import opencc

STCHARACTERS = "https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/STCharacters.txt"

here = pathlib.Path(__file__).parent
terms = [
    *json.loads((here / "terms.json").read_text(encoding="utf-8"))["terms"],
    *json.loads((here / "extra.json").read_text(encoding="utf-8"))["terms"],
]
to_tw = opencc.OpenCC("s2tw")
forms = {}
for line in urllib.request.urlopen(STCHARACTERS).read().decode("utf-8").splitlines():
    simplified, _, traditional = line.partition("\t")
    forms[simplified] = traditional.split()


def rules(convert):
    out = {}
    for t in terms:
        if t.get("only", "p2c") != "p2c" or not t.get("p") or not t.get("c"):
            continue
        p, c = convert(t["p"]), convert(t["c"])

        def chars(s):
            every = {*s, *convert(s)}
            if convert is not same:
                every |= {t for c in s for t in forms.get(c, [])}
            return "".join(sorted(every))

        out[p] = (p, c, chars(t.get("notPrev", "")), chars(t.get("notNext", "")))
    return out.values()


def same(s):
    return s


for name, convert in (("hans", same), ("hant", to_tw.convert)):
    lines = ["\t".join(r) for r in rules(convert)]
    (here / f"{name}.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(name, len(lines))

# The shared test cases in traditional characters, for church_words.rs.
cases = json.loads((here / "cases.json").read_text(encoding="utf-8"))["cases"]
lines = [f"{to_tw.convert(c['in'])}\t{to_tw.convert(c['out'])}" for c in cases if c["dir"] == "p2c"]
(here / "cases-hant.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")
