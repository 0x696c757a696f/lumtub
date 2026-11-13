#!/usr/bin/env bash
# Puts Python and yt-dlp into Runner.app: yt-dlp runs inside the app (an
# iOS app may not start other programs), see lib/ios_python.dart.
#
#   python.sh <Runner.app> <work folder>
#
# Python is the release pinned in python.lock, checked against its
# SHA-256. yt-dlp is the newest nightly, checked against its release's
# SHA2-256SUMS; the app keeps it current itself afterwards.
set -euo pipefail

app=$1
work=$2
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
mkdir -p "$work"

read -r tag sum url < <(grep -v '^#' "$here/python.lock" | grep .)
archive="$work/python-$tag.tar.gz"
curl -fsSL --retry 5 --retry-all-errors -o "$archive" "$url"
echo "$sum  $archive" | shasum -a 256 -c -
rm -rf "$work/python"
mkdir -p "$work/python"
tar -xzf "$archive" -C "$work/python"
cat "$work/python/VERSIONS"
xcframework="$work/python/Python.xcframework"

# BeeWare's own install steps (Python.xcframework/build/utils.sh), with the
# settings Xcode would give them.
export CODESIGNING_FOLDER_PATH="$app"
export PROJECT_DIR="$work/python"
export EFFECTIVE_PLATFORM_NAME=-iphoneos
export PLATFORM_FAMILY_NAME=iOS
export ARCHS=arm64
export PRODUCT_BUNDLE_IDENTIFIER=io.github.lumtub.lumtub
export EXPANDED_CODE_SIGN_IDENTITY=-
export EXPANDED_CODE_SIGN_IDENTITY_NAME=ad-hoc
# shellcheck source=/dev/null
source "$xcframework/build/utils.sh"
rm -rf "$app/python"
install_stdlib Python.xcframework
version=$(cd "$app/python/lib" && ls -d python3.* | head -1)
stdlib="$app/python/lib/$version"
# What yt-dlp never uses: tests, the IDE, Tk, pip's installer.
rm -rf "$stdlib"/{test,idlelib,tkinter,turtledemo,turtle.py,ensurepip,pydoc_data,__phello__}
find "$stdlib/lib-dynload" \( -name '_test*' -o -name 'xx*' -o -name '_ctypes_test*' -o -name '_xxtestfuzz*' -o -name '_tkinter*' \) -delete
find "$app/python" -name '__pycache__' -prune -exec rm -rf {} +
process_dylibs Python.xcframework "python/lib/$version/lib-dynload"

rm -rf "$app/Frameworks/Python.framework"
mkdir -p "$app/Frameworks"
cp -R "$xcframework/ios-arm64/Python.framework" "$app/Frameworks/"
rm -rf "$app/Frameworks/Python.framework/Headers"

# The certificates Python's OpenSSL trusts: the same Chrome Root Store
# list the core can use (native/lumtub_core/roots).
cp "$root/native/lumtub_core/roots/chrome.pem" "$app/python/cacert.pem"

base=https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download
curl -fsSL --retry 5 --retry-all-errors -o "$work/yt-dlp" "$base/yt-dlp"
curl -fsSL --retry 5 --retry-all-errors -o "$work/SHA2-256SUMS" "$base/SHA2-256SUMS"
expected=$(awk '$2 == "yt-dlp" { print $1 }' "$work/SHA2-256SUMS")
[ -n "$expected" ] || { echo "SHA2-256SUMS has no yt-dlp"; exit 1; }
echo "$expected  $work/yt-dlp" | shasum -a 256 -c -
cp "$work/yt-dlp" "$app/python/yt-dlp"
unzip -p "$app/python/yt-dlp" yt_dlp/version.py 2>/dev/null | grep '^__version__' || true

du -sh "$app/python" "$app/Frameworks/Python.framework"
echo "Python modules as frameworks: $(find "$app/Frameworks" -name '*.origin' | wc -l | tr -d ' ')"
