"""Finds newer versions of the pieces build.yml pins; see upstream.yml.

Pieces CI can judge on its own (libmpv for Linux and Windows, FFmpeg for macOS,
appimagetool) are moved to their newest version in .github/pins.env, which
build.yml reads (the workflow token cannot push changes to workflow files);
libmpv for Android and macOS is moved in its vendor/ copy. Each change is
described in $RUNNER_TEMP/upstream-commit.txt. Pieces that
need reading first (the media_kit copies under vendor/, which carry Lumtub's
own changes) are listed in $RUNNER_TEMP/upstream-notes.md.

With the argument "ios" only the iOS libmpv is looked at: lumtub-media-builds
builds it once a day from main's recipe, and upstream.yml pins it the same
day instead of at the next weekly run.
"""

import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.request

BUILD = ".github/pins.env"
TEMP = os.environ.get("RUNNER_TEMP", ".")


def get(url, raw=False):
    headers = {"User-Agent": "lumtub-upstream"}
    if url.startswith("https://api.github.com/") and os.environ.get("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {os.environ['GH_TOKEN']}"
    with urllib.request.urlopen(
        urllib.request.Request(url, headers=headers), timeout=60
    ) as response:
        data = response.read()
    return data if raw else json.loads(data)


def version(text):
    return tuple(int(p) for p in re.findall(r"\d+", text))


def sha256(asset):
    digest = asset.get("digest") or ""
    if digest.startswith("sha256:"):
        return digest[7:]
    return hashlib.sha256(get(asset["browser_download_url"], raw=True)).hexdigest()


MEDIA_BUILDS = "0x696c757a696f/lumtub-media-builds"
LINUX_MPV = {"X86_64": "x86_64", "X86_64_V3": "x86_64-v3", "AARCH64": "aarch64"}


def mpv_prebuilt(text, changes):
    """Linux libmpv from lumtub-media-builds, pinned by release and checksums."""
    pinned = re.search(r"^MPV_RELEASE=(libmpv-\d{8}-[0-9a-f]+)$", text, re.M)
    if not pinned:
        return text
    releases = get(f"https://api.github.com/repos/{MEDIA_BUILDS}/releases?per_page=20")
    for release in releases:
        tag = release["tag_name"]
        if (
            release["draft"]
            or release["prerelease"]
            or not re.fullmatch(r"libmpv-\d{8}-[0-9a-f]+", tag)
        ):
            continue
        assets = {a["name"]: a for a in release["assets"]}
        names = {key: f"libmpv-linux-{flavor}-{tag}.tar.gz" for key, flavor in LINUX_MPV.items()}
        if all(name in assets for name in names.values()):
            break
    else:
        print("lumtub-media-builds has no release with every Linux libmpv; skipped.")
        return text
    if tag == pinned[1]:
        return text
    text = text.replace(pinned[0], f"MPV_RELEASE={tag}")
    for key, name in names.items():
        text = re.sub(
            rf"^(MPV_SHA256_{key}=)[0-9a-f]{{64}}$",
            rf"\g<1>{sha256(assets[name])}",
            text,
            flags=re.M,
        )
    changes.append(f"Linux libmpv {pinned[1]} -> {tag}")
    return text


def angle_prebuilt(text, changes):
    """ANGLE for Windows on Arm from lumtub-media-builds, the newest release."""
    pinned = re.search(r"^ANGLE_ARM64_RELEASE=(\S+)$", text, re.M)
    if not pinned:
        return text
    for release in get(f"https://api.github.com/repos/{MEDIA_BUILDS}/releases?per_page=30"):
        tag = release["tag_name"]
        if (
            release["draft"]
            or release["prerelease"]
            or not re.fullmatch(r"angle-arm64-windows-[0-9A-Za-z._-]+", tag)
        ):
            continue
        assets = {a["name"]: a for a in release["assets"]}
        if f"{tag}.tar.gz" in assets:
            break
    else:
        print("lumtub-media-builds has no ANGLE for Windows on Arm yet; skipped.")
        return text
    if tag == pinned[1]:
        return text
    text = text.replace(pinned[0], f"ANGLE_ARM64_RELEASE={tag}")
    text = re.sub(
        r"^(ANGLE_ARM64_SHA256=)[0-9a-f]{64}$",
        rf"\g<1>{sha256(assets[f'{tag}.tar.gz'])}",
        text,
        flags=re.M,
    )
    changes.append(f"ANGLE arm64 {pinned[1]} -> {tag}")
    return text


def windows_mpv(text, changes):
    """Windows libmpv from zhongfly/mpv-winbuild (LGPL), pinned by release and checksums."""
    pinned = re.search(r"^WINDOWS_MPV_RELEASE=(\S+)$", text, re.M)
    if not pinned:
        return text
    for release in get("https://api.github.com/repos/zhongfly/mpv-winbuild/releases?per_page=5"):
        if release["draft"] or release["prerelease"]:
            continue
        sums = {}
        for key, arch in LINUX_MPV.items():
            pattern = rf"mpv-dev-lgpl-{re.escape(arch)}-[0-9]{{8}}-.+\.7z"
            for asset in release["assets"]:
                if re.fullmatch(pattern, asset["name"]) and asset.get("state") == "uploaded":
                    digest = asset.get("digest") or ""
                    if re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
                        sums[key] = digest[7:]
                    break
        if len(sums) == len(LINUX_MPV):
            break
    else:
        print("zhongfly/mpv-winbuild has no recent release with every libmpv archive; skipped.")
        return text
    tag = release["tag_name"]
    if tag == pinned[1] or not re.fullmatch(r"[0-9A-Za-z._-]{1,100}", tag):
        return text
    text = text.replace(pinned[0], f"WINDOWS_MPV_RELEASE={tag}")
    for key, digest in sums.items():
        text = re.sub(
            rf"^(WINDOWS_MPV_SHA256_{key}=)(none|[0-9a-f]{{64}})$",
            rf"\g<1>{digest}",
            text,
            flags=re.M,
        )
    changes.append(f"Windows libmpv {pinned[1]} -> {tag}")
    return text


IOS_RECIPE = "vendor/media_kit_libs_ios_video/ios"


def ios_libmpv_tag():
    """The release name lumtub-media-builds gives the iOS libmpv of this recipe."""
    with open(os.path.join(IOS_RECIPE, "mpvkit.lock"), encoding="utf-8") as f:
        lock = f.read()
    release = re.search(r"^Libmpv \S+ \S*/releases/download/([^/]+)/", lock, re.M)
    digest = hashlib.sha256()
    patches = sorted(glob.glob(os.path.join(IOS_RECIPE, "patch", "*.patch")))
    for path in [
        os.path.join(IOS_RECIPE, "mpvkit.lock"),
        os.path.join(IOS_RECIPE, "build_libmpv.sh"),
        *patches,
    ]:
        with open(path, "rb") as f:
            digest.update(f.read())
    return f"libmpv-ios-{release[1]}-{digest.hexdigest()[:10]}"


def ios_libmpv(changes):
    """iOS libmpv (picture in picture), built by lumtub-media-builds from this
    repository's recipe; pinned once that build is released."""
    with open(BUILD, encoding="utf-8") as f:
        text = f.read()
    pinned = re.search(r"^IOS_LIBMPV_RELEASE=(\S+)$", text, re.M)
    if not pinned:
        return
    tag = ios_libmpv_tag()
    if tag == pinned[1]:
        return
    try:
        release = get(f"https://api.github.com/repos/{MEDIA_BUILDS}/releases/tags/{tag}")
    except Exception:  # noqa: BLE001, a missing release skips this check.
        print(f"lumtub-media-builds has not released {tag} yet; skipped.")
        return
    assets = {a["name"]: a for a in release["assets"]}
    if f"{tag}.tar.gz" not in assets:
        print(f"{tag} has no {tag}.tar.gz; skipped.")
        return
    text = text.replace(pinned[0], f"IOS_LIBMPV_RELEASE={tag}")
    text = re.sub(
        r"^(IOS_LIBMPV_SHA256=)[0-9a-f]{64}$",
        rf"\g<1>{sha256(assets[f'{tag}.tar.gz'])}",
        text,
        flags=re.M,
    )
    with open(BUILD, "w", encoding="utf-8") as f:
        f.write(text)
    changes.append(f"iOS libmpv {pinned[1]} -> {tag}")


def ffmpeg(text, changes):
    """macOS FFmpeg, built from a release tag."""
    pinned = re.search(r"^FFMPEG_TAG=(n[\d.]+)$", text, re.M)
    if not pinned:
        return text
    tags = subprocess.run(
        [
            "git",
            "ls-remote",
            "--tags",
            "--refs",
            "https://github.com/FFmpeg/FFmpeg.git",
            "refs/tags/n*",
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    releases = [t for t in re.findall(r"refs/tags/(n\d+\.\d+(?:\.\d+)?)$", tags, re.M)]
    newest = max(releases, key=version)
    if version(newest) <= version(pinned[1]):
        return text
    changes.append(f"macOS FFmpeg {pinned[1]} -> {newest}")
    return text.replace(pinned[0], f"FFMPEG_TAG={newest}")


def ffmpeg_prebuilt(text, changes):
    """macOS FFmpeg for the smoke test, from dfloresc/ffmpeg-macos-builds, pinned by release
    and checksum."""
    pinned = re.search(r"^FFMPEG_RELEASE=(v[\w.-]+)$", text, re.M)
    if not pinned:
        return text
    release = get("https://api.github.com/repos/dfloresc/ffmpeg-macos-builds/releases/latest")
    tag = release["tag_name"]
    if (
        tag == pinned[1]
        or not re.fullmatch(r"v\d+(\.\d+)*(-\d+)?", tag)
        or version(tag) <= version(pinned[1])
    ):
        return text
    sums = {}
    for asset in release["assets"]:
        if asset["name"] == f"ffmpeg-{tag[1:]}-lgpl-macos-arm64.tar.xz":
            sums["arm64"] = sha256(asset)
    if "arm64" not in sums:
        print(f"ffmpeg-macos-builds {tag} lacks the LGPL arm64 archive; skipped.")
        return text
    text = text.replace(pinned[0], f"FFMPEG_RELEASE={tag}")
    text = re.sub(
        r"^(FFMPEG_ARM64_SHA256=)[0-9a-f]{64}$", rf"\g<1>{sums['arm64']}", text, flags=re.M
    )
    changes.append(f"macOS FFmpeg {pinned[1]} -> {tag}")
    return text


def appimagetool(text, changes):
    """appimagetool, pinned by release and checksums."""
    pinned = re.search(r"^APPIMAGETOOL_VERSION=([\d.]+)$", text, re.M)
    if not pinned:
        return text
    releases = get("https://api.github.com/repos/AppImage/appimagetool/releases?per_page=30")
    stable = [
        r
        for r in releases
        if re.fullmatch(r"\d+\.\d+(\.\d+)?", r["tag_name"]) and not r["prerelease"]
    ]
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
    text = text.replace(pinned[0], f"APPIMAGETOOL_VERSION={newest['tag_name']}")
    for arch, digest in sums.items():
        text = re.sub(
            rf"^(APPIMAGETOOL_SHA256_{arch.upper()}=)[0-9a-f]{{64}}$",
            rf"\g<1>{digest}",
            text,
            flags=re.M,
        )
    changes.append(f"appimagetool {pinned[1]} -> {newest['tag_name']}")
    return text


ANDROID_GRADLE = "vendor/media_kit_libs_android_video/android/build.gradle"
MPVKIT_LOCKS = (
    "vendor/media_kit_libs_macos_video/macos/mpvkit.lock",
    "vendor/media_kit_libs_ios_video/ios/mpvkit.lock",
)


def rewrite(path, update):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    new = update(text)
    if new != text:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(new)


def android_libmpv(changes):
    """Android libmpv jars from Predidit/libmpv-android-video-build, pinned by release and MD5."""

    def update(text):
        pinned = re.search(r'def libmpvRelease = "(v[\d.]+)"', text)
        release = get(
            "https://api.github.com/repos/Predidit/libmpv-android-video-build/releases/latest"
        )
        tag = release["tag_name"]
        if not re.fullmatch(r"v\d+(\.\d+)*", tag) or version(tag) <= version(pinned[1]):
            return text
        abis = re.findall(r'^ *"([\w-]+)": "[0-9a-f]{32}",$', text, re.M)
        urls = {a["name"]: a["browser_download_url"] for a in release["assets"]}
        if any(f"default-{abi}.jar" not in urls for abi in abis):
            print(f"libmpv-android-video-build {tag} lacks a jar for {abis}; skipped.")
            return text
        for abi in abis:
            md5 = hashlib.md5(
                get(urls[f"default-{abi}.jar"], raw=True), usedforsecurity=False
            ).hexdigest()
            text = re.sub(
                rf'^( *"{re.escape(abi)}": ")[0-9a-f]{{32}}(",)$',
                rf"\g<1>{md5}\g<2>",
                text,
                flags=re.M,
            )
        changes.append(f"Android libmpv {pinned[1]} -> {tag}")
        return text.replace(pinned[0], f'def libmpvRelease = "{tag}"')

    rewrite(ANDROID_GRADLE, update)


def mpvkit(changes):
    """macOS and iOS libmpv linked from MPVKit's static libraries, pinned by the checksums in
    its Package.swift."""

    def update(text, platform):
        pinned = re.search(r"^# MPVKit release (\S+):", text, re.M)
        tags = subprocess.run(
            ["git", "ls-remote", "--tags", "--refs", "https://github.com/mpvkit/MPVKit.git"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        releases = re.findall(r"refs/tags/(\d+\.\d+\.\d+(?:-n[\d.]+)?)$", tags, re.M)
        newest = max(releases, key=lambda t: version(t.split("-")[0]))
        if version(newest.split("-")[0]) <= version(pinned[1].split("-")[0]):
            return text
        package = get(
            f"https://raw.githubusercontent.com/mpvkit/MPVKit/{newest}/Package.swift", raw=True
        ).decode()
        targets = dict(
            re.findall(
                r'\.binaryTarget\(\s*name: "([^"]+)",\s*url: "([^"]+)",\s*checksum: "[0-9a-f]{64}"',
                package,
            )
        )
        sums = dict(
            re.findall(r'name: "([^"]+)",\s*url: "[^"]+",\s*checksum: "([0-9a-f]{64})"', package)
        )
        lines = []
        for line in text.splitlines():
            m = re.fullmatch(r"(\S+) [0-9a-f]{64} \S+", line)
            if not m:
                lines.append(
                    line.replace(pinned[1], newest) if line.startswith("# MPVKit release") else line
                )
                continue
            if m[1] not in targets:
                print(f"MPVKit {newest} has no {m[1]}; skipped.")
                return text
            lines.append(f"{m[1]} {sums[m[1]]} {targets[m[1]]}")
        changes.append(f"{platform} libmpv (MPVKit) {pinned[1]} -> {newest}")
        return "\n".join(lines) + "\n"

    for lock, platform in zip(MPVKIT_LOCKS, ("macOS", "iOS"), strict=True):
        rewrite(lock, lambda text, platform=platform: update(text, platform))


IOS_PYTHON_LOCK = "ios/packaging/python.lock"


def ios_python(changes, notes):
    """Python for iOS (BeeWare Python-Apple-support): newer builds of the same
    Python are taken; a newer Python is noted, since yt-dlp runs in it."""

    def update(text):
        line = re.search(r"^(\d+)\.(\d+)-b(\d+) [0-9a-f]{64} \S+$", text, re.M)
        if not line:
            return text
        major, minor, build = map(int, line.groups())
        tags = subprocess.run(
            [
                "git",
                "ls-remote",
                "--tags",
                "--refs",
                "https://github.com/beeware/Python-Apple-support.git",
            ],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        stable = [
            tuple(map(int, t)) for t in re.findall(r"refs/tags/(\d+)\.(\d+)-b(\d+)$", tags, re.M)
        ]
        newer_python = sorted({(a, b) for a, b, _ in stable if (a, b) > (major, minor)})
        if newer_python:
            a, b = newer_python[-1]
            notes.append(
                f"- Python for iOS: BeeWare has Python {a}.{b} (ios/packaging/python.lock pins "
                f"{major}.{minor}). "
                "Move to it once yt-dlp supports it, and test on an iPhone."
            )
        same = max(n for a, b, n in stable if (a, b) == (major, minor))
        if same <= build:
            return text
        tag = f"{major}.{minor}-b{same}"
        name = f"Python-{major}.{minor}-iOS-support.b{same}.tar.gz"
        release = get(
            f"https://api.github.com/repos/beeware/Python-Apple-support/releases/tags/{tag}"
        )
        asset = next((a for a in release["assets"] if a["name"] == name), None)
        if asset is None:
            print(f"Python-Apple-support {tag} has no {name}; skipped.")
            return text
        changes.append(f"iOS Python {major}.{minor}-b{build} -> {tag}")
        return text.replace(line[0], f"{tag} {sha256(asset)} {asset['browser_download_url']}")

    rewrite(IOS_PYTHON_LOCK, update)


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
        except Exception as e:  # noqa: BLE001, a missing package skips it.
            print(f"pub.dev has no {name}: {e}")
            continue
        if version(latest) > version(ours):
            notes.append(
                f"- `{name}`: vendor/{folder} is a patched copy of {ours}; pub.dev has {latest} "
                f"([changes](https://pub.dev/packages/{name}/changelog)). Move Lumtub's changes "
                f"onto it."
            )


def ios_only():
    changes = []
    try:
        ios_libmpv(changes)
    except Exception as e:  # noqa: BLE001, one failed check must not stop the others.
        print(f"::warning::ios_libmpv: {e}")
    if changes:
        with open(os.path.join(TEMP, "upstream-commit.txt"), "w", encoding="utf-8") as f:
            f.write("Upstream updates: " + "; ".join(changes) + "\n")
    print("\n".join(changes) or "The iOS libmpv is current.")


def main():
    with open(BUILD, encoding="utf-8") as f:
        text = f.read()
    changes, notes = [], []
    for check in (mpv_prebuilt, angle_prebuilt, windows_mpv, ffmpeg, ffmpeg_prebuilt, appimagetool):
        try:
            text = check(text, changes)
        except Exception as e:  # noqa: BLE001, one failed check must not stop the others.
            print(f"::warning::{check.__name__}: {e}")
    if changes:
        with open(BUILD, "w", encoding="utf-8") as f:
            f.write(text)
    for check in (android_libmpv, mpvkit, ios_libmpv):
        try:
            check(changes)
        except Exception as e:  # noqa: BLE001, one failed check must not stop the others.
            print(f"::warning::{check.__name__}: {e}")
    try:
        ios_python(changes, notes)
    except Exception as e:  # noqa: BLE001, one failed check must not stop the others.
        print(f"::warning::ios_python: {e}")
    vendored(notes)
    if changes:
        with open(os.path.join(TEMP, "upstream-commit.txt"), "w", encoding="utf-8") as f:
            f.write("Upstream updates: " + "; ".join(changes) + "\n")
    with open(os.path.join(TEMP, "upstream-notes.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(notes) + ("\n" if notes else ""))
    print("\n".join(changes + notes) or "Everything is current.")


if sys.argv[1:] == ["ios"]:
    ios_only()
else:
    main()
