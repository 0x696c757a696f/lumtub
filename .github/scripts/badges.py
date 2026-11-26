"""Draws the release and download count badges shown in the READMEs.

shields.io often fails to fetch these two numbers from GitHub, so the
badges are drawn here in the same flat style and kept on the badges branch.

    GITHUB_TOKEN=... python .github/scripts/badges.py OUT_DIR
"""

import json
import os
import sys
import urllib.request
from pathlib import Path

REPO = os.environ.get("GITHUB_REPOSITORY", "0x696c757a696f/lumtub")

# Verdana 11 px advance widths, as shields.io measures text.
WIDTHS = {
    " ": 3.87, "-": 4.58, ".": 3.5, "0": 7.0, "1": 7.0, "2": 7.0, "3": 7.0,
    "4": 7.0, "5": 7.0, "6": 7.0, "7": 7.0, "8": 7.0, "9": 7.0, "a": 6.66,
    "b": 6.83, "c": 5.73, "d": 6.83, "e": 6.56, "f": 3.87, "g": 6.83,
    "h": 6.98, "i": 3.0, "k": 6.5, "l": 3.0, "m": 10.7, "n": 6.98,
    "o": 6.67, "p": 6.83, "r": 4.69, "s": 5.73, "t": 4.33, "u": 6.98,
    "v": 6.5, "w": 9.0, "M": 9.88, "B": 7.55,
}


def text_width(text):
    return sum(WIDTHS.get(c, 11.0 if ord(c) > 0x2E80 else 7.0) for c in text)


def dark_text(color):
    r, g, b = (int(color[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.299 * r + 0.587 * g + 0.114 * b > 0.69


def badge(label, value, color):
    lw = round(text_width(label)) + 10
    vw = round(text_width(value)) + 10
    w = lw + vw
    fill, shadow = ("#333", "#ccc") if dark_text(color) else ("#fff", "#010101")
    def text(x, s, f, sh):
        return (
            f'<text x="{x * 10}" y="150" fill="{sh}" fill-opacity=".3" '
            f'transform="scale(.1)" textLength="{round(text_width(s)) * 10}">{s}</text>'
            f'<text x="{x * 10}" y="140" fill="{f}" transform="scale(.1)" '
            f'textLength="{round(text_width(s)) * 10}">{s}</text>'
        )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="20" '
        f'role="img" aria-label="{label}: {value}"><title>{label}: {value}</title>'
        '<linearGradient id="s" x2="0" y2="100%"><stop offset="0" '
        'stop-color="#bbb" stop-opacity=".1"/><stop offset="1" '
        'stop-opacity=".1"/></linearGradient><clipPath id="r"><rect '
        f'width="{w}" height="20" rx="3" fill="#fff"/></clipPath>'
        f'<g clip-path="url(#r)"><rect width="{lw}" height="20" fill="#555"/>'
        f'<rect x="{lw}" width="{vw}" height="20" fill="#{color}"/>'
        f'<rect width="{w}" height="20" fill="url(#s)"/></g>'
        '<g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,'
        'DejaVu Sans,sans-serif" text-rendering="geometricPrecision" '
        'font-size="110">'
        + text(lw / 2, label, "#fff", "#010101")
        + text(lw + vw / 2, value, fill, shadow)
        + "</g></svg>\n"
    )


def releases():
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    page = 1
    while True:
        req = urllib.request.Request(
            f"https://api.github.com/repos/{REPO}/releases?per_page=100&page={page}",
            headers={"Accept": "application/vnd.github+json",
                     **({"Authorization": f"Bearer {token}"} if token else {})},
        )
        with urllib.request.urlopen(req, timeout=60) as reply:
            batch = json.load(reply)
        if not batch:
            return
        yield from batch
        page += 1


def metric(n):
    for size, suffix in ((1_000_000, "M"), (1_000, "k")):
        if n >= size:
            v = n / size
            return (f"{v:.1f}".rstrip("0").rstrip(".") if v < 100 else f"{v:.0f}") + suffix
    return str(n)


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    published = [r for r in releases() if not r["draft"]]
    newest = max(published, key=lambda r: r["published_at"] or "")
    version = newest["tag_name"].split("-")[0]
    total = sum(a["download_count"] for r in published for a in r["assets"])
    downloads = metric(total)
    for name, label, value, color in (
        ("release-en", "release", version, "E53935"),
        ("downloads-en", "downloads", downloads, "2DD4BF"),
        ("release-zh", "版本", version, "E53935"),
        ("downloads-zh", "下载量", downloads, "2DD4BF"),
    ):
        (out / f"{name}.svg").write_text(badge(label, value, color), encoding="utf-8")
    print(f"{version}, {total} downloads")


if __name__ == "__main__":
    main()
