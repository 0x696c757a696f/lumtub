"""Writes the tables church_words.rs compiles in.

hans.tsv, hant.tsv and hk.tsv (Latin rite) and the same with -byzantine
come from terms.json and extra.json; sourced-hans.tsv, sourced-hant.tsv
and sourced-hk.tsv from sourced.json.

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

STCHARACTERS = (
    "https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/STCharacters.txt"
)

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


def rules(convert, region, byzantine):
    out = {}
    for t in terms:
        if t.get("only", "p2c") != "p2c" or not t.get("p") or not t.get("c"):
            continue
        if byzantine and t.get("rite") == "latin":
            out.pop(convert(t["p"]), None)
            continue
        p, c = convert(t["p"]), convert(t.get(region) or t["c"])

        def chars(s):
            every = {*s, *convert(s)}
            if convert is not same:
                every |= {t for c in s for t in forms.get(c, [])}
            return "".join(sorted(every))

        out[p] = (p, c, chars(t.get("notPrev", "")), chars(t.get("notNext", "")))
    return out.values()


def same(s):
    return s


variants = (("hans", same, "cn"), ("hant", to_tw.convert, "tw"), ("hk", to_tw.convert, "hk"))
for name, convert, region in variants:
    for byzantine in (False, True):
        lines = ["\t".join(r) for r in rules(convert, region, byzantine)]
        file = f"{name}-byzantine.tsv" if byzantine else f"{name}.tsv"
        (here / file).write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(file, len(lines))

# The shared test cases in traditional characters, for church_words.rs.
cases = json.loads((here / "cases.json").read_text(encoding="utf-8"))["cases"]
lines = [f"{to_tw.convert(c['in'])}\t{to_tw.convert(c['out'])}" for c in cases if c["dir"] == "p2c"]
(here / "cases-hant.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")

# Rules that need the original: words of the original (| between them),
# words that rule it out, the Chinese words, what they become.
sourced = json.loads((here / "sourced.json").read_text(encoding="utf-8"))["rules"]
for name, convert, region in variants:
    lines = [
        "\t".join(
            (
                "|".join(w.lower() for w in r["src"]),
                "|".join(w.lower() for w in r.get("unless", [])),
                "|".join(convert(z) for z in r["zh"]),
                convert(r.get(region) or r["c"]),
            )
        )
        for r in sourced
    ]
    (here / f"sourced-{name}.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")
