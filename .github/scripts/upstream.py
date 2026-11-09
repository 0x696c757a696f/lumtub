"""Finds newer versions of the pieces build.yml pins; see upstream.yml.

Pieces CI can judge on its own (libmpv for Linux, FFmpeg for macOS,
appimagetool) are moved to their newest version in build.yml directly, and
the change is described in $RUNNER_TEMP/upstream-commit.txt. Pieces that
need reading first (the media_kit copies under vendor/, which carry Lumtub's
own changes) are listed in $RUNNER_TEMP/upstream-notes.md.
"""

import hashlib
import json
import os
import re
import subprocess
import urllib.request

BUILD = ".github/workflows/build.yml"
TEMP = os.environ.get("RUNNER_TEMP", ".")


def get(url, raw=False):
    headers = {"User-Agent": "lumtub-upstream"}
    if url.startswith("https://api.github.com/") and os.environ.get("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {os.environ['GH_TOKEN']}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as response:
        data = response.read()
    return data if raw else json.loads(data)


def version(text):
    return tuple(int(p) for p in re.findall(r"\d+", text))


def sha256(asset):
    digest = asset.get("digest") or ""
    if digest.startswith("sha256:"):
        return digest[7:]
    return hashlib.sha256(get(asset["browser_download_url"], raw=True)).hexdigest()


def mpv_prebuilt(text, changes):
    """Linux libmpv from jason-yau/mpv-prebuilt, pinned by release and checksums."""
    pinned = re.search(r'MPV_RELEASE: "(\d+)"', text)
    if not pinned:
        return text
    release = get("https://api.github.com/repos/jason-yau/mpv-prebuilt/releases/latest")
    if release["tag_name"] == pinned[1] or not release["tag_name"].isdigit():
        return text
    assets = {}
    for asset in release["assets"]:
        m = re.fullmatch(r"libmpv-([\d.]+)-linux-(x86_64|arm64)-gpl-\d+\.tar\.gz", asset["name"])
        if m:
            assets[m[2]] = (m[1], sha256(asset))
    if set(assets) != {"x86_64", "arm64"} or assets["x86_64"][0] != assets["arm64"][0]:
        print(f"mpv-prebuilt {release['tag_name']} lacks the GPL x86_64 and arm64 archives; skipped.")
        return text
    mpv = assets["x86_64"][0]
    old = re.search(r'name="libmpv-([\d.]+)-linux-', text)[1]
    text = text.replace(pinned[0], f'MPV_RELEASE: "{release["tag_name"]}"')
    text = text.replace(f'name="libmpv-{old}-linux-', f'name="libmpv-{mpv}-linux-')
    text = re.sub(r"libmpv [\d.]+ with", f"libmpv {mpv} with", text, count=1)
    for arch in ("x86_64", "arm64"):
        text = re.sub(rf"(arch={arch}; sum=)[0-9a-f]{{64}}", rf"\g<1>{assets[arch][1]}", text)
    changes.append(f"Linux libmpv {old} ({pinned[1]}) -> {mpv} ({release['tag_name']})")
    return text


def ffmpeg(text, changes):
    """macOS FFmpeg, built from a release tag."""
    pinned = re.search(r"FFMPEG_TAG: (n[\d.]+)", text)
    if not pinned:
        return text
    tags = subprocess.run(
        ["git", "ls-remote", "--tags", "--refs", "https://github.com/FFmpeg/FFmpeg.git", "refs/tags/n*"],
        check=True, capture_output=True, text=True,
    ).stdout
    releases = [t for t in re.findall(r"refs/tags/(n\d+\.\d+(?:\.\d+)?)$", tags, re.M)]
    newest = max(releases, key=version)
    if version(newest) <= version(pinned[1]):
        return text
    changes.append(f"macOS FFmpeg {pinned[1]} -> {newest}")
    return text.replace(pinned[0], f"FFMPEG_TAG: {newest}")


def appimagetool(text, changes):
    """appimagetool, pinned by release and checksums."""
    pinned = re.search(r"appimagetool/releases/download/([\d.]+)/", text)
    if not pinned:
        return text
    releases = get("https://api.github.com/repos/AppImage/appimagetool/releases?per_page=30")
    stable = [r for r in releases if re.fullmatch(r"\d+\.\d+(\.\d+)?", r["tag_name"]) and not r["prerelease"]]
    if not stable:
        return text
    newest = max(stable, key=lambda r: version(r["tag_name"]))
    if version(newest["tag_name"]) <= version(pinned[1]):
        return text
    sums = {}
    for asset in newest["assets"]:
        m = re.fullmatch(r"appimagetool-(x86_64|aarch64)\.AppImage", asset["name"])
        if m:
            sums[m[1]] = sha256(asset)
    if set(sums) != {"x86_64", "aarch64"}:
        print(f"appimagetool {newest['tag_name']} lacks x86_64 and aarch64 builds; skipped.")
        return text
    text = text.replace(pinned[0], f"appimagetool/releases/download/{newest['tag_name']}/")
    for arch, digest in sums.items():
        text = re.sub(
            rf"(appimage_arch: {arch}\n\s+appimagetool_sha256: )[0-9a-f]{{64}}", rf"\g<1>{digest}", text
        )
    changes.append(f"appimagetool {pinned[1]} -> {newest['tag_name']}")
    return text


def vendored(notes):
    """The media_kit packages copied under vendor/ with Lumtub's changes."""
    for folder in sorted(os.listdir("vendor")):
        pubspec = os.path.join("vendor", folder, "pubspec.yaml")
        if not os.path.exists(pubspec):
            continue
        with open(pubspec, encoding="utf-8") as f:
            text = f.read()
        name = re.search(r"^name: *(\S+)", text, re.M)[1]
        ours = re.search(r"^version: *([\d.]+)", text, re.M)[1]
        try:
            latest = get(f"https://pub.dev/api/packages/{name}")["latest"]["version"]
        except Exception as e:
            print(f"pub.dev has no {name}: {e}")
            continue
        if version(latest) > version(ours):
            notes.append(
                f"- `{name}`: vendor/{folder} is a patched copy of {ours}; pub.dev has {latest} "
                f"([changes](https://pub.dev/packages/{name}/changelog)). Move Lumtub's changes onto it."
            )


def main():
    with open(BUILD, encoding="utf-8") as f:
        text = f.read()
    changes, notes = [], []
    for check in (mpv_prebuilt, ffmpeg, appimagetool):
        try:
            text = check(text, changes)
        except Exception as e:
            print(f"::warning::{check.__name__}: {e}")
    vendored(notes)
    if changes:
        with open(BUILD, "w", encoding="utf-8") as f:
            f.write(text)
        with open(os.path.join(TEMP, "upstream-commit.txt"), "w", encoding="utf-8") as f:
            f.write("Upstream updates: " + "; ".join(changes) + "\n")
    with open(os.path.join(TEMP, "upstream-notes.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(notes) + ("\n" if notes else ""))
    print("\n".join(changes + notes) or "Everything is current.")


main()
