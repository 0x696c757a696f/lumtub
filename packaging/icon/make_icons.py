"""Draws the three app icons as SVG and exports every file the platforms use.

    python3 packaging/icon/make_icons.py          SVGs only
    python3 packaging/icon/make_icons.py --export SVGs and all PNG/ICO files

Exporting renders the SVGs with Chromium through Playwright for Node
(require('playwright') must work) and needs Pillow.

- classic: mint tile, dark play button (the default)
- tabor:   the light of Tabor, a mandorla darker toward the centre with
           three rays from the play button
- gold:    gold ground, a lapis nimbus and a gold play button
"""

import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
S = 1024
RADIUS = 230
NAMES = ["classic", "tabor", "gold"]


def rounded_poly(pts, r):
    d = ""
    for i in range(len(pts)):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % len(pts)]
        v1 = (p0[0] - p1[0], p0[1] - p1[1])
        v2 = (p2[0] - p1[0], p2[1] - p1[1])
        l1, l2 = math.hypot(*v1), math.hypot(*v2)
        angle = math.acos((v1[0] * v2[0] + v1[1] * v2[1]) / (l1 * l2))
        t = r / math.tan(angle / 2)
        a = (p1[0] + v1[0] / l1 * t, p1[1] + v1[1] / l1 * t)
        b = (p1[0] + v2[0] / l2 * t, p1[1] + v2[1] / l2 * t)
        d += (
            "M" if i == 0 else "L"
        ) + f"{a[0]:.1f},{a[1]:.1f} A{r},{r} 0 0 1 {b[0]:.1f},{b[1]:.1f} "
    return d + "Z"


def play_points(cx, cy, h):
    """A play triangle whose centroid sits on (cx, cy)."""
    w = h * 0.88
    x0 = cx - w / 3
    return [(x0, cy - h / 2), (x0 + w, cy), (x0, cy + h / 2)]


def play(cx, cy, h, r):
    return rounded_poly(play_points(cx, cy, h), r)


def document(body, defs, square):
    radius = 0 if square else RADIUS
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">'
        f'<defs>{defs}<clipPath id="tile"><rect width="{S}" height="{S}" '
        f'rx="{radius}"/></clipPath></defs>'
        f'<g clip-path="url(#tile)">{body}</g></svg>\n'
    )


def classic(square=False):
    shape = play(536, 512, 520, 44)
    body = (
        f'<rect width="{S}" height="{S}" fill="url(#ground)"/>'
        f'<rect width="{S}" height="{S}" fill="url(#sheen)"/>'
        f'<path d="{shape}" fill="#000" opacity=".18" filter="url(#soft)" '
        f'transform="translate(0,22)"/>'
        f'<path d="{shape}" fill="url(#ink)"/>'
    )
    defs = (
        '<linearGradient id="ground" x1="0" y1="0" x2="0.35" y2="1"><stop offset="0" '
        'stop-color="#7DEBC6"/><stop offset="1" stop-color="#25B88E"/></linearGradient>'
        '<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" '
        'stop-opacity=".22"/><stop offset=".45" stop-color="#fff" '
        'stop-opacity="0"/></linearGradient>'
        '<linearGradient id="ink" x1="0" y1="0" x2="0" y2="1"><stop offset="0" '
        'stop-color="#1D2B27"/><stop offset="1" stop-color="#0B1311"/></linearGradient>'
        '<filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur '
        'stdDeviation="22"/></filter>'
    )
    return document(body, defs, square)


def tabor(square=False):
    cx, cy, h = 530, 512, 400
    rings = [
        (430, "#9CC0EE", ".35"),
        (360, "#5E8DD0", "1"),
        (290, "#2E5698", "1"),
        (220, "#13284F", "1"),
    ]
    rays = ""
    for vx, vy in play_points(cx, cy, h):
        dx, dy = vx - cx, vy - cy
        length = math.hypot(dx, dy)
        rays += (
            f'<line x1="{cx}" y1="{cy}" x2="{cx + dx / length * 440:.0f}" '
            f'y2="{cy + dy / length * 440:.0f}" '
            'stroke="#FFF3C8" stroke-width="18" stroke-linecap="round" opacity=".8"/>'
        )
    shape = play(cx, cy, h, 30)
    body = (
        f'<rect width="{S}" height="{S}" fill="url(#ground)"/>'
        + "".join(
            f'<circle cx="512" cy="512" r="{r}" fill="{c}" opacity="{o}"/>' for r, c, o in rings
        )
        + rays
        + f'<path d="{shape}" fill="#FFE7A6" filter="url(#glow)" opacity=".9"/>'
        + f'<path d="{shape}" fill="url(#light)"/>'
    )
    defs = (
        '<linearGradient id="ground" x1="0" y1="0" x2="0" y2="1"><stop offset="0" '
        'stop-color="#E9F1FB"/><stop offset="1" stop-color="#BFD3EE"/></linearGradient>'
        '<linearGradient id="light" x1="0" y1="0" x2="1" y2="1"><stop offset="0" '
        'stop-color="#FFFDF4"/><stop offset="1" stop-color="#F2D27C"/></linearGradient>'
        '<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur '
        'stdDeviation="28"/></filter>'
    )
    return document(body, defs, square)


def gold(square=False):
    body = (
        f'<rect width="{S}" height="{S}" fill="url(#ground)"/>'
        f'<rect width="{S}" height="{S}" fill="url(#leaf)" opacity=".5"/>'
        '<circle cx="512" cy="512" r="352" fill="none" stroke="#8A6414" stroke-width="6" '
        'opacity=".55"/>'
        '<circle cx="512" cy="512" r="330" fill="url(#lapis)"/>'
        '<circle cx="512" cy="512" r="300" fill="none" stroke="#E7C25E" stroke-width="8" '
        'opacity=".85"/>'
        f'<path d="{play(536, 512, 330, 30)}" fill="url(#gilt)"/>'
    )
    defs = (
        '<linearGradient id="ground" x1="0" y1="0" x2="1" y2="1"><stop offset="0" '
        'stop-color="#F6DD8E"/><stop offset=".5" stop-color="#E0B24A"/><stop offset="1" '
        'stop-color="#B9861F"/></linearGradient>'
        '<radialGradient id="leaf" cx=".3" cy=".25" r=".8"><stop offset="0" stop-color="#fff" '
        'stop-opacity=".8"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/></radialGradient>'
        '<radialGradient id="lapis" cx=".4" cy=".35" r=".8"><stop offset="0" '
        'stop-color="#2F57A8"/><stop offset="1" stop-color="#11265A"/></radialGradient>'
        '<linearGradient id="gilt" x1="0" y1="0" x2="1" y2="1"><stop offset="0" '
        'stop-color="#FFF1BE"/><stop offset="1" stop-color="#E2AE3C"/></linearGradient>'
    )
    return document(body, defs, square)


DRAW = {"classic": classic, "tabor": tabor, "gold": gold}

# Where each icon goes: (path, size, inset as a fraction of the size, drop shadow).
# The macOS shape is 824/1024 of the canvas with a soft shadow, as Apple's template has.
ICO_SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]
ANDROID = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
MAC = 100 / 1024


def jobs(work):
    out = []
    for name in NAMES:
        suffix = "" if name == "classic" else "_" + name
        out.append((name, f"assets/app_icons/{name}.png", 128, 0, False))
        for density, size in ANDROID.items():
            out.append(
                (
                    name,
                    f"android/app/src/main/res/mipmap-{density}/ic_launcher{suffix}.png",
                    size,
                    0,
                    False,
                )
            )
        out.append(
            (
                name,
                f"linux/runner/resources/{'lumtub' if name == 'classic' else 'lumtub-' + name}.png",
                256,
                0,
                False,
            )
        )
        out.append((name, os.path.join(work, f"banner-{name}.png"), 96, 0, False))
        for size in ICO_SIZES:
            out.append((name, os.path.join(work, f"ico-{name}-{size}.png"), size, 0, False))
        if name != "classic":
            out.append((name, f"assets/app_icons/{name}-mac.png", 512, MAC, True))
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        out.append(
            (
                "classic",
                f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png",
                size,
                MAC,
                True,
            )
        )
    out += [
        ("classic", "packaging/aur/lumtub.png", 256, 12 / 256, False),
        ("classic", "docs/cards/icon.png", 128, 13 / 128, False),
        ("classic", "website/public/icon.png", 256, 25 / 256, False),
        ("classic", "website/public/favicon.png", 64, 6 / 64, False),
        (
            "classic-square",
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png",
            1024,
            0,
            False,
        ),
    ]
    return out


RENDER_JS = r"""
const {chromium} = require('playwright');
const fs = require('fs');
(async () => {
  const jobs = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const browser = await chromium.launch();
  const page = await browser.newPage({deviceScaleFactor: 1});
  for (const j of jobs) {
    await page.setViewportSize({width: j.size, height: j.size});
    const inner = j.size - 2 * Math.round(j.size * j.inset);
    const shadow = j.shadow ? `filter: drop-shadow(0 ${j.size * 0.01}px ${j.size * 0.015}px rgba(0,0,0,.3));` : '';
    fs.writeFileSync('page.html', `<html><body style="margin:0;background:transparent;display:flex;align-items:center;justify-content:center;width:${j.size}px;height:${j.size}px"><img src="${j.svg}" style="width:${inner}px;height:${inner}px;${shadow}"></body></html>`);
    await page.goto('file://' + process.cwd() + '/page.html');
    await page.waitForFunction(() => document.images[0].complete);
    await page.screenshot({path: j.out, omitBackground: true});
  }
  await browser.close();
})();
"""  # noqa: E501, the embedded script lines stay as written.


def write_svgs(folder):
    paths = {}
    for name in NAMES:
        paths[name] = os.path.join(folder, f"lumtub-{name}.svg")
        with open(paths[name], "w", encoding="utf-8", newline="\n") as f:
            f.write(DRAW[name]())
    return paths


def export():
    from PIL import Image

    svgs = write_svgs(HERE)
    work = tempfile.mkdtemp()
    square = os.path.join(work, "classic-square.svg")
    with open(square, "w", encoding="utf-8") as f:
        f.write(classic(square=True))
    svgs["classic-square"] = square
    listed = []
    for name, path, size, inset, shadow in jobs(work):
        out = path if os.path.isabs(path) else os.path.join(ROOT, path)
        listed.append(
            {
                "svg": "file://" + svgs[name],
                "out": out,
                "size": size,
                "inset": inset,
                "shadow": shadow,
            }
        )
    with open(os.path.join(work, "jobs.json"), "w") as f:
        json.dump(listed, f)
    with open(os.path.join(work, "render.js"), "w") as f:
        f.write(RENDER_JS)
    subprocess.run(
        ["node", os.path.join(work, "render.js"), os.path.join(work, "jobs.json")],
        check=True,
        cwd=work,
    )

    # iOS wants no alpha channel.
    ios = os.path.join(
        ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
    )
    Image.open(ios).convert("RGB").save(ios, optimize=True)

    banner_text = text_strip(work)
    for name in NAMES:
        suffix = "" if name == "classic" else "_" + name
        images = [
            Image.open(os.path.join(work, f"ico-{name}-{size}.png")).convert("RGBA")
            for size in ICO_SIZES
        ]
        ico = os.path.join(ROOT, f"windows/runner/resources/app_icon{suffix}.ico")
        images[-1].save(
            ico, format="ICO", sizes=[(s, s) for s in ICO_SIZES], append_images=images[:-1]
        )
        banner = Image.new("RGB", (320, 180), (20, 20, 23))
        icon = Image.open(os.path.join(work, f"banner-{name}.png")).convert("RGBA")
        banner.paste(icon, (21, 42), icon)
        banner.paste(banner_text, (0, 0), banner_text)
        banner.save(
            os.path.join(ROOT, f"android/app/src/main/res/drawable-xhdpi/banner{suffix}.png"),
            optimize=True,
        )
    shutil.rmtree(work)


def text_strip(work):
    """The 'Lumtub' word of the Android TV banner, on a transparent strip."""
    from PIL import Image

    html = os.path.join(work, "banner.html")
    with open(html, "w", encoding="utf-8") as f:
        f.write(
            '<html><body style="margin:0;width:320px;height:180px;background:transparent">'
            '<div style="position:absolute;left:138px;top:0;height:180px;display:flex;align-items:c'
            'enter;'
            'font:400 47px \'Noto Sans\',\'Open Sans\',\'DejaVu '
            'Sans\',sans-serif;color:#fff">Lumtub</div></body></html>'
        )
    js = os.path.join(work, "text.js")
    with open(js, "w") as f:
        f.write(
            "const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();"
            "const p=await b.newPage({viewport:{width:320,height:180}});"
            f"await p.goto('file://{html}');await p.screenshot({{path:'{work}/text.png',omitBackgro"
            f"und:true}});await b.close();}})();"
        )
    subprocess.run(["node", js], check=True, cwd=work)
    return Image.open(os.path.join(work, "text.png")).convert("RGBA")


if __name__ == "__main__":
    if "--export" in sys.argv:
        export()
    else:
        write_svgs(HERE)
