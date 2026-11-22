"""Draws the animated sponsor banner and buttons used in the READMEs.

Text is turned into outlines so the pictures look the same everywhere.

    pip install fonttools uharfbuzz
    python docs/sponsor/make.py

Fonts (Geist and Noto Sans SC, OFL) are downloaded from Google Fonts into
docs/sponsor/.fonts on first run. Brand logos are from Simple Icons (CC0).
"""

import re
import urllib.request
from pathlib import Path

import uharfbuzz as hb
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

HERE = Path(__file__).resolve().parent
CACHE = HERE / ".fonts"

GITHUB = "M17.625 1.499c-2.32 0-4.354 1.203-5.625 3.03-1.271-1.827-3.305-3.03-5.625-3.03C3.129 1.499 0 4.253 0 8.249c0 4.275 3.068 7.847 5.828 10.227a33.14 33.14 0 0 0 5.616 3.876l.028.017.008.003-.001.003c.163.085.342.126.521.125.179.001.358-.041.521-.125l-.001-.003.008-.003.028-.017a33.14 33.14 0 0 0 5.616-3.876C20.932 16.096 24 12.524 24 8.249c0-3.996-3.129-6.75-6.375-6.75zm-.919 15.275a30.766 30.766 0 0 1-4.703 3.316l-.004-.002-.004.002a30.955 30.955 0 0 1-4.703-3.316c-2.677-2.307-5.047-5.298-5.047-8.523 0-2.754 2.121-4.5 4.125-4.5 2.06 0 3.914 1.479 4.544 3.684.143.495.596.797 1.086.796.49.001.943-.302 1.085-.796.63-2.205 2.484-3.684 4.544-3.684 2.004 0 4.125 1.746 4.125 4.5 0 3.225-2.37 6.216-5.048 8.523z"
KOFI = "M11.351 2.715c-2.7 0-4.986.025-6.83.26C2.078 3.285 0 5.154 0 8.61c0 3.506.182 6.13 1.585 8.493 1.584 2.701 4.233 4.182 7.662 4.182h.83c4.209 0 6.494-2.234 7.637-4a9.5 9.5 0 0 0 1.091-2.338C21.792 14.688 24 12.22 24 9.208v-.415c0-3.247-2.13-5.507-5.792-5.87-1.558-.156-2.65-.208-6.857-.208m0 1.947c4.208 0 5.09.052 6.571.182 2.624.311 4.13 1.584 4.13 4v.39c0 2.156-1.792 3.844-3.87 3.844h-.935l-.156.649c-.208 1.013-.597 1.818-1.039 2.546-.909 1.428-2.545 3.064-5.922 3.064h-.805c-2.571 0-4.831-.883-6.078-3.195-1.09-2-1.298-4.155-1.298-7.506 0-2.181.857-3.402 3.012-3.714 1.533-.233 3.559-.26 6.39-.26m6.547 2.287c-.416 0-.65.234-.65.546v2.935c0 .311.234.545.65.545 1.324 0 2.051-.754 2.051-2s-.727-2.026-2.052-2.026m-10.39.182c-1.818 0-3.013 1.48-3.013 3.142 0 1.533.858 2.857 1.949 3.897.727.701 1.87 1.429 2.649 1.896a1.47 1.47 0 0 0 1.507 0c.78-.467 1.922-1.195 2.623-1.896 1.117-1.039 1.974-2.364 1.974-3.897 0-1.662-1.247-3.142-3.039-3.142-1.065 0-1.792.545-2.338 1.298-.493-.753-1.246-1.298-2.312-1.298"
AFDIAN = "M9 14.234a.567.567 0 1 0 0 1.134.567.567 0 0 0 0-1.134m5.351 1.705a.567.567 0 1 0 0 1.135.567.567 0 0 0 0-1.135M24 12.25c0 6.627-5.373 12-12 12s-12-5.373-12-12 5.373-12 12-12 12 5.373 12 12m-5.68-.708c.236-.46.367-.996.367-1.565 0-1.789-1.29-3.239-2.88-3.239-.893 0-1.692.457-2.22 1.175l-.008-.01-.017.025-.006.007-2.373 3.293c-1.53-1.135-3.592-1.598-5.693-1.104-1.95.459-3.519 1.682-4.383 3.247a.57.57 0 0 0 .249.79l.008.003a.58.58 0 0 0 .769-.245c.71-1.282 2.004-2.284 3.613-2.663 1.808-.426 3.578.006 4.837.99.032.03.069.056.11.075a.56.56 0 0 0 .72-.155l.003-.003 2.734-3.796c.312-.425.775-.705 1.288-.705.903 0 1.635.877 1.635 1.958 0 .493-.153.943-.403 1.287a.5.5 0 0 0 .087.672l.016.012a.5.5 0 0 0 .67-.081 3 3 0 0 0 .19-.25 3.4 3.4 0 0 1 .617 1.48c.226 1.648-.958 3.215-2.665 3.63l-.04.01c-.043.012-.088.02-.132.026l-1.168.198a.577.577 0 0 0-.465.656.58.58 0 0 0 .67.454l1.164-.198c.06-.008.12-.02.18-.034l.09-.02c2.293-.556 3.851-2.656 3.552-4.837a4.6 4.6 0 0 0-1.003-2.307z"
HEART = "M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"

FONTS = {
    ("latin", 800): "Geist:wght@800",
    ("latin", 500): "Geist:wght@500",
    ("cjk", 800): "Noto+Sans+SC:wght@800",
    ("cjk", 500): "Noto+Sans+SC:wght@500",
}


def font_file(kind, weight):
    CACHE.mkdir(exist_ok=True)
    path = CACHE / f"{kind}-{weight}.ttf"
    if not path.exists():
        css_url = "https://fonts.googleapis.com/css2?family=" + FONTS[(kind, weight)]
        request = urllib.request.Request(css_url, headers={"User-Agent": "Mozilla/5.0"})
        css = urllib.request.urlopen(request).read().decode()
        ttf = re.search(r"url\((https://[^)]+\.ttf)\)", css).group(1)
        path.write_bytes(urllib.request.urlopen(ttf).read())
    return path


class Face:
    def __init__(self, path):
        data = path.read_bytes()
        self.hb = hb.Font(hb.Face(data))
        self.tt = TTFont(path)
        self.glyphs = self.tt.getGlyphSet()
        self.order = self.tt.getGlyphOrder()
        self.upem = self.tt["head"].unitsPerEm


_faces = {}


def face(kind, weight):
    key = (kind, weight)
    if key not in _faces:
        _faces[key] = Face(font_file(kind, weight))
    return _faces[key]


def is_cjk(ch):
    return ord(ch) >= 0x2E80


def runs(text):
    """Splits text into Latin and Chinese runs, dropping spaces between the two."""
    out = []
    for ch in text:
        kind = "cjk" if is_cjk(ch) else "latin"
        if out and out[-1][0] == kind:
            out[-1][1] += ch
        else:
            out.append([kind, ch])
    for i, run in enumerate(out):
        if run[0] == "latin":
            if i > 0:
                run[1] = run[1].lstrip(" ")
            if i < len(out) - 1:
                run[1] = run[1].rstrip(" ")
    return [r for r in out if r[1]]


def _num(v):
    return f"{v:.1f}".rstrip("0").rstrip(".")


def shape(text, weight, size, tracking=0.0, cjk_tracking=0.0):
    """Returns (path data, advance width) for text drawn from x=0, baseline y=0.

    Chinese and Latin runs get a quarter em between them, the way the
    text-autospace rule of CSS spaces them.
    """
    pieces = []
    x = 0.0
    last = None
    for kind, part in runs(text):
        if last is not None and last != kind:
            x += size * 0.25 + tracking
        last = kind
        f = face(kind, weight)
        buf = hb.Buffer()
        buf.add_str(part)
        buf.guess_segment_properties()
        features = {"kern": True, "liga": True}
        if kind == "cjk":
            features["chws"] = True
        hb.shape(f.hb, buf, features)
        scale = size / f.upem
        step = tracking + (cjk_tracking * size if kind == "cjk" else 0.0)
        for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
            name = f.order[info.codepoint]
            pen = SVGPathPen(f.glyphs, ntos=_num)
            gx = x + pos.x_offset * scale
            gy = -pos.y_offset * scale
            f.glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, gx, gy)))
            d = pen.getCommands()
            if d:
                pieces.append(d)
            x += pos.x_advance * scale + step
        x -= step
    return " ".join(pieces), x


def text(s, x, y, weight, size, fill, anchor="start", tracking=0.0, extra="", cjk_tracking=0.0):
    d, width = shape(s, weight, size, tracking, cjk_tracking)
    if anchor == "middle":
        x -= width / 2
    elif anchor == "end":
        x -= width
    return f'<path transform="translate({x:.2f} {y:.2f})" fill="{fill}" {extra}d="{d}"/>', width


def logo(d, x, y, size, fill):
    s = size / 24
    return f'<path transform="translate({x:.2f} {y:.2f}) scale({s:.4f})" fill="{fill}" d="{d}"/>'


def play_icon(x, y, size):
    s = size / 1024
    return (
        f'<g transform="translate({x} {y}) scale({s:.5f})">'
        '<rect x="100" y="100" width="824" height="824" rx="184" fill="#57D5B9"/>'
        '<path d="M374 328 L702 512 L374 695 Z" fill="#111419"/></g>'
    )


def banner(lang):
    w, h = 1280, 400
    if lang == "en":
        eyebrow = "SUPPORT LUMTUB"
        head = "Keep Lumtub free."
        sub = "No ads, no tracking, no subscriptions. One developer, in the open."
        sub2 = "Sponsors pay for the time it takes, and decide what comes next."
        chips = ["Year-long iOS installs", "Test devices", "Sponsor requests first"]
        chip_label = "Up next"
    else:
        eyebrow = "支持 LUMTUB"
        head = "让 Lumtub 一直免费下去"
        sub = "没有广告，没有追踪，没有订阅。一个人开发，完全开源。"
        sub2 = "赞助支付开发它的时间，也决定下一步做什么。"
        chips = ["iOS 安装一年有效", "测试设备", "赞助者需求优先"]
        chip_label = "下一步"

    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">',
        "<defs>",
        '<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0" stop-color="#0E2A26"/><stop offset=".45" stop-color="#0B0E14"/>'
        '<stop offset="1" stop-color="#1A1840"/></linearGradient>',
        '<radialGradient id="g1"><stop offset="0" stop-color="#57D5B9" stop-opacity=".55"/>'
        '<stop offset="1" stop-color="#57D5B9" stop-opacity="0"/></radialGradient>',
        '<radialGradient id="g2"><stop offset="0" stop-color="#EA4AAA" stop-opacity=".5"/>'
        '<stop offset="1" stop-color="#EA4AAA" stop-opacity="0"/></radialGradient>',
        '<radialGradient id="g3"><stop offset="0" stop-color="#946CE6" stop-opacity=".5"/>'
        '<stop offset="1" stop-color="#946CE6" stop-opacity="0"/></radialGradient>',
        '<linearGradient id="sweep" x1="0" y1="0" x2="1" y2="0">'
        '<stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".5" stop-color="#fff" stop-opacity=".09"/>'
        '<stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>',
        '<linearGradient id="headfill" x1="0" y1="0" x2="1" y2="0">'
        '<stop offset="0" stop-color="#FFFFFF"/><stop offset=".55" stop-color="#C8FFF1"/>'
        '<stop offset="1" stop-color="#FFC4E6"/></linearGradient>',
        '<linearGradient id="border" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0" stop-color="#57D5B9" stop-opacity=".7"/><stop offset=".5" stop-color="#ffffff" stop-opacity=".08"/>'
        '<stop offset="1" stop-color="#EA4AAA" stop-opacity=".7"/></linearGradient>',
        f'<clipPath id="card"><rect width="{w}" height="{h}" rx="28"/></clipPath>',
        "</defs>",
        "<style>"
        "@keyframes drift1{0%,100%{transform:translate(0,0)}50%{transform:translate(160px,60px)}}"
        "@keyframes drift2{0%,100%{transform:translate(0,0)}50%{transform:translate(-200px,-40px)}}"
        "@keyframes drift3{0%,100%{transform:translate(0,0)}50%{transform:translate(-120px,70px)}}"
        ".b1{animation:drift1 14s ease-in-out infinite}"
        ".b2{animation:drift2 18s ease-in-out infinite}"
        ".b3{animation:drift3 16s ease-in-out infinite}"
        "@keyframes sweep{0%{transform:translateX(-500px) skewX(-20deg)}60%,100%{transform:translateX(1500px) skewX(-20deg)}}"
        ".sw{animation:sweep 7s ease-in-out infinite}"
        "@keyframes rise{0%{transform:translateY(0) scale(.6);opacity:0}15%{opacity:.9}100%{transform:translateY(-420px) scale(1.1);opacity:0}}"
        ".hr{animation:rise linear infinite;transform-box:fill-box;transform-origin:center}"
        "@keyframes beat{0%,40%,100%{transform:scale(1)}10%{transform:scale(1.22)}20%{transform:scale(.96)}30%{transform:scale(1.12)}}"
        ".beat{animation:beat 1.6s ease-in-out infinite;transform-box:fill-box;transform-origin:center}"
        "@keyframes glow{0%,100%{opacity:.35}50%{opacity:.85}}"
        ".glow{animation:glow 3.2s ease-in-out infinite}"
        "@keyframes dot{0%,100%{opacity:.3}50%{opacity:1}}"
        ".dot{animation:dot 2s ease-in-out infinite}"
        "@media (prefers-reduced-motion:reduce){*{animation:none!important}}"
        "</style>",
        '<g clip-path="url(#card)">',
        f'<rect width="{w}" height="{h}" fill="url(#bg)"/>',
        '<g class="b1"><circle cx="160" cy="80" r="300" fill="url(#g1)"/></g>',
        '<g class="b2"><circle cx="1150" cy="330" r="320" fill="url(#g2)"/></g>',
        '<g class="b3"><circle cx="760" cy="40" r="260" fill="url(#g3)"/></g>',
    ]

    hearts = [
        (90, 3.0, 0.0, 14, "#EA4AAA"), (250, 4.6, 1.2, 10, "#57D5B9"), (420, 5.4, 2.6, 16, "#FF5E5B"),
        (600, 4.0, 0.7, 9, "#946CE6"), (770, 5.8, 3.4, 13, "#EA4AAA"), (930, 4.4, 1.9, 11, "#57D5B9"),
        (1060, 5.0, 0.3, 15, "#FF5E5B"), (1200, 4.2, 2.2, 10, "#946CE6"), (340, 6.2, 4.1, 8, "#EA4AAA"),
        (1130, 6.6, 4.8, 9, "#57D5B9"),
    ]
    for x, dur, delay, size, color in hearts:
        out.append(
            f'<g class="hr" style="animation-duration:{dur}s;animation-delay:-{delay}s">'
            + logo(HEART, x, h + 4, size, color)
            + "</g>"
        )

    ix, iy, isz = 64, 104, 192
    out.append(f'<circle class="glow" cx="{ix + isz / 2}" cy="{iy + isz / 2}" r="120" fill="url(#g1)"/>')
    out.append(play_icon(ix, iy, isz))
    out.append('<g class="beat">' + '<circle cx="232" cy="276" r="34" fill="#0B0E14"/>'
               + '<circle cx="232" cy="276" r="29" fill="#EA4AAA"/>'
               + logo(HEART, 216, 261, 32, "#fff") + "</g>")

    tx = 310
    out.append(f'<circle class="dot" cx="{tx + 6}" cy="86" r="6" fill="#EA4AAA"/>')
    el, _ = text(eyebrow, tx + 22, 93, 800, 20, "#EA8BC8", tracking=3.2)
    out.append(el)
    el, _ = text(head, tx, 162, 800, 64 if lang == "en" else 58, "url(#headfill)", tracking=-1.0 if lang == "en" else 0, cjk_tracking=0.02)
    out.append(el)
    el, _ = text(sub, tx, 212, 500, 25, "#D5DCE4", cjk_tracking=0.04)
    out.append(el)
    el, _ = text(sub2, tx, 248, 500, 25, "#9AA6B2", cjk_tracking=0.04)
    out.append(el)

    cx = tx
    el, lw = text(chip_label, cx, 318, 800, 18, "#57D5B9", tracking=1.0, cjk_tracking=0.04)
    out.append(el)
    cx += lw + 18
    for chip in chips:
        _, cw = shape(chip, 500, 19, cjk_tracking=0.03)
        out.append(f'<rect x="{cx}" y="292" width="{cw + 36:.1f}" height="38" rx="19" fill="#57D5B9" fill-opacity=".08" stroke="#57D5B9" stroke-opacity=".55" stroke-width="1.5"/>')
        el, _ = text(chip, cx + 18, 318, 500, 19, "#BFF5E7", cjk_tracking=0.03)
        out.append(el)
        cx += cw + 36 + 12

    out.append('<rect class="sw" x="0" y="-40" width="260" height="480" fill="url(#sweep)"/>')
    out.append("</g>")
    out.append(f'<rect x="1" y="1" width="{w - 2}" height="{h - 2}" rx="27" fill="none" stroke="url(#border)" stroke-width="2"/>')
    out.append("</svg>")
    return "\n".join(out)


BUTTONS = {
    "github": ("#EA4AAA", "#BF3989", GITHUB),
    "kofi": ("#FF5E5B", "#E0403D", KOFI),
    "afdian": ("#946CE6", "#7450C8", AFDIAN),
}

LABELS = {
    ("github", "en"): ("GitHub Sponsors", "Monthly or one-time"),
    ("kofi", "en"): ("Ko-fi", "PayPal or card, no account"),
    ("afdian", "en"): ("Afdian", "Alipay · WeChat Pay"),
    ("github", "zh"): ("GitHub Sponsors", "按月或一次性"),
    ("kofi", "zh"): ("Ko-fi", "PayPal 或银行卡"),
    ("afdian", "zh"): ("爱发电", "支付宝 · 微信支付"),
}


def button(kind, lang):
    top, bottom, mark = BUTTONS[kind]
    title, note = LABELS[(kind, lang)]
    w, h = 300, 76
    _, tw = shape(title, 800, 23, cjk_tracking=0.06)
    _, nw = shape(note, 500, 15, cjk_tracking=0.05)
    content = 40 + 14 + max(tw, nw)
    x0 = (w - content) / 2
    t1, _ = text(title, x0 + 54, 36, 800, 23, "#fff", cjk_tracking=0.06)
    t2, _ = text(note, x0 + 54, 58, 500, 15, "#fff", extra='fill-opacity=".82" ', cjk_tracking=0.05)
    return "\n".join([
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">',
        "<defs>",
        f'<linearGradient id="f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>',
        '<linearGradient id="s" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#fff" stop-opacity="0"/>'
        '<stop offset=".5" stop-color="#fff" stop-opacity=".38"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>',
        '<linearGradient id="t" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".28"/>'
        '<stop offset=".5" stop-color="#fff" stop-opacity="0"/></linearGradient>',
        f'<clipPath id="c"><rect x="2" y="2" width="{w - 4}" height="{h - 4}" rx="18"/></clipPath>',
        "</defs>",
        "<style>"
        "@keyframes sh{0%{transform:translateX(-140px) skewX(-22deg)}55%,100%{transform:translateX(440px) skewX(-22deg)}}"
        ".sh{animation:sh 3.6s ease-in-out infinite}"
        "@keyframes beat{0%,50%,100%{transform:scale(1)}12%{transform:scale(1.18)}24%{transform:scale(.95)}36%{transform:scale(1.1)}}"
        ".m{animation:beat 1.8s ease-in-out infinite;transform-box:fill-box;transform-origin:center}"
        "@media (prefers-reduced-motion:reduce){*{animation:none!important}}"
        "</style>",
        f'<rect x="2" y="2" width="{w - 4}" height="{h - 4}" rx="18" fill="url(#f)"/>',
        '<g clip-path="url(#c)">',
        f'<rect x="2" y="2" width="{w - 4}" height="{(h - 4) / 2}" fill="url(#t)"/>',
        f'<rect class="sh" x="0" y="0" width="90" height="{h}" fill="url(#s)"/>',
        "</g>",
        f'<rect x="2.75" y="2.75" width="{w - 5.5}" height="{h - 5.5}" rx="17.25" fill="none" stroke="#fff" stroke-opacity=".35" stroke-width="1.5"/>',
        '<g class="m">' + logo(mark, x0, (h - 40) / 2, 40, "#fff") + "</g>",
        t1,
        t2,
        "</svg>",
    ])


def pill(lang):
    label = "SPONSOR" if lang == "en" else "赞助"
    size = 13 if lang == "en" else 14
    _, lw = shape(label, 800, size, tracking=1.2 if lang == "en" else 2)
    w = int(28 + 22 + lw + 14)
    h = 28
    t, _ = text(label, 50, 19 if lang == "en" else 19.5, 800, size, "#fff", tracking=1.2 if lang == "en" else 2)
    return "\n".join([
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">',
        '<defs><linearGradient id="f" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#EA4AAA"/>'
        '<stop offset="1" stop-color="#946CE6"/></linearGradient>'
        '<linearGradient id="s" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#fff" stop-opacity="0"/>'
        '<stop offset=".5" stop-color="#fff" stop-opacity=".45"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>'
        f'<clipPath id="c"><rect width="{w}" height="{h}" rx="4"/></clipPath></defs>',
        "<style>"
        f"@keyframes sh{{0%{{transform:translateX(-60px) skewX(-22deg)}}50%,100%{{transform:translateX({w + 40}px) skewX(-22deg)}}}}"
        ".sh{animation:sh 3s ease-in-out infinite}"
        "@keyframes beat{0%,50%,100%{transform:scale(1)}12%{transform:scale(1.25)}24%{transform:scale(.95)}36%{transform:scale(1.15)}}"
        ".m{animation:beat 1.6s ease-in-out infinite;transform-box:fill-box;transform-origin:center}"
        "@media (prefers-reduced-motion:reduce){*{animation:none!important}}"
        "</style>",
        '<g clip-path="url(#c)">',
        f'<rect width="{w}" height="{h}" fill="url(#f)"/>',
        f'<rect width="40" height="{h}" fill="#000" fill-opacity=".14"/>',
        f'<rect class="sh" x="0" y="0" width="36" height="{h}" fill="url(#s)"/>',
        "</g>",
        '<g class="m">' + logo(HEART, 11, 5.5, 18, "#fff") + "</g>",
        t,
        "</svg>",
    ])


def main():
    for lang in ("en", "zh"):
        (HERE / f"banner-{lang}.svg").write_text(banner(lang) + "\n")
        (HERE / f"sponsor-{lang}.svg").write_text(pill(lang) + "\n")
        for kind in BUTTONS:
            (HERE / f"{kind}-{lang}.svg").write_text(button(kind, lang) + "\n")


if __name__ == "__main__":
    main()
