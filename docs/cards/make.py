"""Render the feature cards in docs/cards/out from docs/screenshots.

Every card is 1600x1000: a short headline, one line of detail, the app in a
window frame, and an optional magnified callout of the detail that matters.

    python docs/cards/make.py [card ids...]
"""

import json
import pathlib
import sys

from PIL import Image
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
SHOTS = HERE.parent
OUT = HERE / "out"
W, H = 1600, 1000

CSS = """
* { box-sizing: border-box; margin: 0; }
html, body { width: %(W)dpx; height: %(H)dpx; overflow: hidden; }
body {
  font-family: 'Inter', 'Noto Sans SC', sans-serif;
  background:
    radial-gradient(1000px 520px at 50%% -12%%, rgba(45, 212, 191, .22), transparent 70%%),
    radial-gradient(700px 500px at 100%% 100%%, rgba(239, 68, 68, .14), transparent 70%%),
    #0a0b0d;
  color: #fafafa;
  position: relative;
}
.head { position: absolute; left: 80px; right: 80px; top: 64px; text-align: center; }
.eyebrow {
  display: inline-flex; align-items: center; gap: 10px; padding: 7px 16px 7px 8px;
  border-radius: 999px; background: rgba(45, 212, 191, .1); border: 1px solid rgba(45, 212, 191, .3);
  font-size: 21px; font-weight: 600; color: #5eead4;
}
.eyebrow img { width: 28px; height: 28px; border-radius: 7px; }
h1 { margin-top: 22px; font-size: 64px; line-height: 1.12; font-weight: 800; letter-spacing: -.015em; }
p { margin: 14px auto 0; font-size: 26px; line-height: 1.45; color: #a1a1aa; max-width: 1100px; }
.win {
  position: absolute; border-radius: 14px 14px 0 0; overflow: hidden;
  border: 1px solid rgba(255, 255, 255, .16); border-bottom: 0;
  box-shadow: 0 -10px 120px rgba(45, 212, 191, .10), 0 40px 120px rgba(0, 0, 0, .7);
  background: #000;
}
.win img { display: block; width: 100%%; }
.mark { position: absolute; border: 3px solid #ef4444; border-radius: 10px; }
.zoom {
  position: absolute; border-radius: 16px; overflow: hidden;
  border: 3px solid #ef4444; background-color: #000;
  box-shadow: 0 30px 80px rgba(0, 0, 0, .75);
  background-repeat: no-repeat;
}
.tag {
  position: absolute; padding: 6px 14px; border-radius: 999px; transform: translateY(-50%%);
  background: #ef4444; color: #fff; font-size: 20px; font-weight: 700; white-space: nowrap;
  box-shadow: 0 8px 24px rgba(0, 0, 0, .5);
}
:lang(zh) h1 { letter-spacing: .02em; }
"""


def card_html(card, lang):
    t = card[lang]
    if "grid" in card:
        return grid_html(card, lang, t)
    src = SHOTS / card["shot"][lang]
    sw, sh = Image.open(src).size
    win = card["window"]
    scale = win["width"] / sw
    parts = [
        f'<div class="head"><div class="eyebrow"><img src="{(HERE / "icon.png").as_uri()}">{t["eyebrow"]}</div>',
        f'<h1>{t["title"]}</h1><p>{t["text"]}</p></div>',
        f'<div class="win" style="left:{win["left"]}px;top:{win["top"]}px;width:{win["width"]}px">',
        f'<img src="{src.as_uri()}">',
    ]
    z = card.get("zoom")
    if z and lang in z:
        z = z[lang]
    if z:
        x, y, w, h = z["crop"]
        parts.append(
            f'<div class="mark" style="left:{x * scale - 6}px;top:{y * scale - 6}px;'
            f'width:{w * scale + 12}px;height:{h * scale + 12}px"></div>'
        )
    parts.append("</div>")
    if z:
        x, y, w, h = z["crop"]
        f = z["factor"]
        parts.append(
            f'<div class="zoom" style="left:{z["left"]}px;top:{z["top"]}px;width:{w * f}px;height:{h * f}px;'
            f"background-image:url('{src.as_uri()}');background-size:{sw * f}px {sh * f}px;"
            f'background-position:{-x * f}px {-y * f}px">'
            + "</div>"
            + (f'<span class="tag" style="left:{z["left"] + 20}px;top:{z["top"]}px">{t["tag"]}</span>' if t.get("tag") else "")
        )
    return page(lang, parts)


def grid_html(card, lang, t):
    g = card["grid"]
    parts = [
        f'<div class="head"><div class="eyebrow"><img src="{(HERE / "icon.png").as_uri()}">{t["eyebrow"]}</div>',
        f'<h1>{t["title"]}</h1><p>{t["text"]}</p></div>',
    ]
    w, gap = g["width"], g["gap"]
    left0 = (W - 2 * w - gap) / 2
    for i, item in enumerate(g["shots"]):
        sw, sh = Image.open(SHOTS / item["shot"]).size
        h = w * sh / sw
        x = left0 + (i % 2) * (w + gap)
        y = g["top"] + (i // 2) * (h + gap)
        parts.append(
            f'<div class="win" style="left:{x}px;top:{y}px;width:{w}px;border-radius:12px;border-bottom:1px solid rgba(255,255,255,.16)">'
            f'<img src="{(SHOTS / item["shot"]).as_uri()}"></div>'
            +
            (f'<span class="tag" style="left:{x + 16}px;top:{y + h - 6}px;transform:translateY(-100%)">{item[lang]}</span>' if item.get(lang) else "")
        )
    return page(lang, parts)


def page(lang, parts):
    font = "https://fonts.googleapis.com/css2?family=Inter:wght@400;600;800&family=Noto+Sans+SC:wght@400;600;800&display=block"
    return (
        f'<!doctype html><html lang="{"zh" if lang == "zh" else "en"}"><head><meta charset="utf-8">'
        f'<link rel="stylesheet" href="{font}"><style>{CSS % {"W": W, "H": H}}</style></head>'
        f'<body>{"".join(parts)}</body></html>'
    )


def main():
    cards = json.loads((HERE / "cards.json").read_text(encoding="utf-8"))
    wanted = set(sys.argv[1:])
    OUT.mkdir(exist_ok=True)
    pages = []
    for card in cards:
        if wanted and card["id"] not in wanted:
            continue
        for lang in ("en", "zh"):
            html = OUT / f".{card['id']}-{lang}.html"
            html.write_text(card_html(card, lang), encoding="utf-8")
            pages.append(html)
    subprocess.run(["node", str(HERE / "shoot.js"), str(W), str(H), *map(str, pages)], check=True)
    for html in pages:
        png = html.with_name(html.name[1:]).with_suffix(".png")
        Image.open(png).convert("RGB").save(png.with_suffix(".jpg"), quality=88, optimize=True)
        png.unlink()
        html.unlink()
        print("wrote", png.with_suffix(".jpg").name)

if __name__ == "__main__":
    main()
