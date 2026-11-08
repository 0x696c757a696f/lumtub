#!/usr/bin/env bash
# Fills version, URLs and SHA-256 values into the WinGet, Scoop and AUR manifests.
# Usage: packaging/update-manifests.sh <tag> [folder-with-release-assets]
#   tag      the release tag, for example v0.2.29-1a2b3c4
#   folder   optional folder holding the downloaded release assets; without it
#            the script downloads them from the GitHub release with curl
set -euo pipefail

repo=0x696c757a696f/lumtub
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

tag=${1:-}
dir=${2:-}
if [[ ! $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-([0-9a-f]{7})$ ]]; then
  echo "Usage: $0 <tag like v0.2.29-1a2b3c4> [asset-folder]" >&2
  exit 1
fi
base=${BASH_REMATCH[1]}
commit=${BASH_REMATCH[2]}
full=${tag#v}

files=(
  "Lumtub_${full}_windows-x64-setup.exe"
  "Lumtub_${full}_windows-arm64-setup.exe"
  "Lumtub_${full}_windows-x64.zip"
  "Lumtub_${full}_windows-arm64.zip"
  "Lumtub_${full}_linux-x64.AppImage"
  "Lumtub_${full}_linux-arm64.AppImage"
)

if [[ -z $dir ]]; then
  dir=$(mktemp -d)
  trap 'rm -rf "$dir"' EXIT
  for f in "${files[@]}"; do
    echo "Downloading $f"
    curl -fL --retry 3 -o "$dir/$f" "https://github.com/$repo/releases/download/$tag/$f"
  done
fi

declare -A sha
for f in "${files[@]}"; do
  [[ -f $dir/$f ]] || { echo "Missing $dir/$f" >&2; exit 1; }
  sha[$f]=$(sha256sum "$dir/$f" | cut -d' ' -f1)
done
sha[lumtub.png]=$(sha256sum "$here/aur/lumtub.png" | cut -d' ' -f1)
sha[desktop]=$(sha256sum "$here/aur/io.github.lumtub.lumtub.desktop" | cut -d' ' -f1)

sums=$(mktemp)
trap 'rm -f "$sums"' EXIT
for k in "${!sha[@]}"; do printf '%s %s\n' "$k" "${sha[$k]}" >> "$sums"; done
export HERE=$here BASE=$base COMMIT=$commit FULL=$full TAG=$tag REPO=$repo SUMS=$sums
python3 -I - <<'PY'
import os, re, sys, json
here, base, commit, full, tag, repo = (os.environ[k] for k in ("HERE", "BASE", "COMMIT", "FULL", "TAG", "REPO"))
with open(os.environ["SUMS"]) as fh:
    sha = dict(line.split() for line in fh if line.strip())
rel = f"https://github.com/{repo}/releases/download/{tag}"

def edit(path, fn):
    with open(path, encoding="utf-8", newline="") as fh:
        text = fh.read()
    new = fn(text)
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(new)

# WinGet: version, locale and installer manifests
for name in ("Lumtub.Lumtub.yaml", "Lumtub.Lumtub.locale.en-US.yaml", "Lumtub.Lumtub.installer.yaml"):
    def winget(t):
        t = re.sub(r"(?m)^PackageVersion: .*$", f"PackageVersion: {base}", t)
        t = re.sub(r"(?m)^ReleaseNotesUrl: .*$", f"ReleaseNotesUrl: https://github.com/{repo}/releases/tag/{tag}", t)
        t = re.sub(r"(?m)^(\s*- DisplayVersion: ).*$", lambda m: m.group(1) + full, t)
        for arch in ("x64", "arm64"):
            f = f"Lumtub_{full}_windows-{arch}-setup.exe"
            t = re.sub(
                rf"(- Architecture: {arch}\n  InstallerUrl: ).*\n(  InstallerSha256: ).*",
                lambda m: f"{m.group(1)}{rel}/{f}\n{m.group(2)}{sha[f].upper()}",
                t,
            )
        return t
    edit(os.path.join(here, "winget", name), winget)

# Scoop
path = os.path.join(here, "scoop", "lumtub.json")
with open(path, encoding="utf-8") as fh:
    doc = json.load(fh)
doc["version"] = full
for key, arch in (("64bit", "x64"), ("arm64", "arm64")):
    f = f"Lumtub_{full}_windows-{arch}.zip"
    doc["architecture"][key]["url"] = f"{rel}/{f}"
    doc["architecture"][key]["hash"] = sha[f]
with open(path, "w", encoding="utf-8", newline="\n") as fh:
    json.dump(doc, fh, indent=4, ensure_ascii=False)
    fh.write("\n")

# AUR
def pkgbuild(t):
    t = re.sub(r"(?m)^pkgver=.*$", f"pkgver={base}", t)
    t = re.sub(r"(?m)^_commit=.*$", f"_commit={commit}", t)
    t = re.sub(r"(?m)^pkgrel=.*$", "pkgrel=1", t)
    t = re.sub(r"(?m)^sha256sums=\('[0-9a-f]*'\n\s+'[0-9a-f]*'\)$",
               f"sha256sums=('{sha['lumtub.png']}'\n            '{sha['desktop']}')", t)
    for arch, pk in (("x86_64", "x64"), ("aarch64", "arm64")):
        t = re.sub(rf"(?m)^sha256sums_{arch}=\('[0-9a-f]*'\)$",
                   f"sha256sums_{arch}=('{sha[f'Lumtub_{full}_linux-{pk}.AppImage']}')", t)
    return t
edit(os.path.join(here, "aur", "PKGBUILD"), pkgbuild)

def srcinfo(t):
    t = re.sub(r"(?m)^(\tpkgver = ).*$", lambda m: m.group(1) + base, t)
    t = re.sub(r"Lumtub_[0-9.]+-[0-9a-f]{7}_linux", f"Lumtub_{full}_linux", t)
    t = re.sub(r"releases/download/v[0-9.]+-[0-9a-f]{7}/", f"releases/download/{tag}/", t)
    lines = t.split("\n")
    out, icon_done = [], 0
    for line in lines:
        if line.startswith("\tsha256sums = "):
            line = "\tsha256sums = " + (sha["lumtub.png"] if icon_done == 0 else sha["desktop"])
            icon_done += 1
        for arch, pk in (("x86_64", "x64"), ("aarch64", "arm64")):
            if line.startswith(f"\tsha256sums_{arch} = "):
                line = f"\tsha256sums_{arch} = " + sha[f"Lumtub_{full}_linux-{pk}.AppImage"]
        out.append(line)
    return "\n".join(out)
edit(os.path.join(here, "aur", ".SRCINFO"), srcinfo)
PY
echo "Updated manifests for $tag (version $base)."
