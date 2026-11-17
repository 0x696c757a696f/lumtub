"""Rebuilds public/fonts/noto-sans-sc-*.woff2 with only the Chinese characters the site uses.

Run after changing Chinese text in src/:

    pip install fonttools brotli
    python website/subset_cjk.py
"""

import re
import subprocess
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
CACHE = HERE / ".fonts"
OUT = HERE / "public" / "fonts"
WEIGHTS = (400, 600, 800)
PUNCTUATION = "，。、：；！？（）《》「」“”‘’…—·"


def font(weight):
    CACHE.mkdir(exist_ok=True)
    path = CACHE / f"noto-sans-sc-{weight}.ttf"
    if not path.exists():
        url = f"https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@{weight}"
        css = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})).read().decode()
        path.write_bytes(urllib.request.urlopen(re.search(r"url\((https://[^)]+\.ttf)\)", css).group(1)).read())
    return path


def main():
    sources = list((HERE / "src").glob("*.rs")) + [HERE / "index.html"]
    text = "".join(p.read_text(encoding="utf-8") for p in sources)
    chars = sorted({c for c in text if ord(c) >= 0x2E80} | set(PUNCTUATION))
    listing = CACHE / "chars.txt"
    CACHE.mkdir(exist_ok=True)
    listing.write_text("".join(chars), encoding="utf-8")
    for weight in WEIGHTS:
        subprocess.run([
            "pyftsubset", str(font(weight)),
            f"--text-file={listing}",
            "--flavor=woff2",
            "--layout-features=*",
            f"--output-file={OUT / f'noto-sans-sc-{weight}.woff2'}",
        ], check=True)
    print(f"{len(chars)} characters")


if __name__ == "__main__":
    main()
