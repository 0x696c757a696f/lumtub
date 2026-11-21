#!/usr/bin/env bash
# Puts CPython's Android build into the APK for yt-dlp (python.org's
# tarballs for arm64-v8a and x86_64, one built by python-arm32.sh for
# armeabi-v7a): per ABI, a launcher (python-launcher.c, Py_BytesMain) as jniLibs/<abi>/libpython.so, CPython's
# libpython3.x.so and the libraries it loads beside it, and the standard
# library as jniLibs/<abi>/libpython.zip.so (usr/lib/python3.x, usr/etc/tls),
# which PythonSetup.kt unpacks. Also res/raw/ytdlp, the yt-dlp zip app.
# See lib/android_python.dart.
#
#   python.sh <work folder>
#
# Needs ANDROID_NDK_HOME and the PYTHON_ANDROID_* and YTDLP_* pins of
# .github/pins.env in the environment. Each download is checked against its
# SHA-256 and kept in <work folder>/downloads.
set -euo pipefail
work=$1
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
jni="$root/android/app/src/main/jniLibs"
clang_bin="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
downloads="$work/downloads"
mkdir -p "$downloads"

fetch() { # url file sha256
  if [ -f "$2" ] && echo "$3  $2" | sha256sum -c - > /dev/null 2>&1; then return; fi
  curl -fsSL --retry 5 --retry-all-errors -o "$2" "$1"
  local sum
  sum=$(sha256sum "$2" | cut -d' ' -f1)
  if [ "$sum" != "$3" ]; then
    echo "$1: SHA-256 is $sum, pinned $3" >&2
    rm -f "$2"
    exit 1
  fi
}

version=$PYTHON_ANDROID_VERSION
unpinned=
minor=${version%.*}
build_abi() { # abi triple clang-triple pin ("built" = made by python-arm32.sh)
  local abi=$1 triple=$2 clang=$3 pin=$4
  local url="https://www.python.org/ftp/python/$version/python-$version-$triple.tar.gz"
  local tarball="$downloads/python-$version-$triple.tar.gz"
  if [ "$pin" = built ]; then
    # From lumtub-media-builds when pins.env pins this recipe's release,
    # else built here (a change to the recipe, before its release exists).
    local name
    name=$("$here/python-arm32.sh" --name)
    tarball="$downloads/$name.tar.gz"
    if [ "$name" = "${PYTHON_ANDROID_ARM32_RELEASE:-}" ]; then
      fetch "https://github.com/0x696c757a696f/lumtub-media-builds/releases/download/$name/$name.tar.gz" "$tarball" "$PYTHON_ANDROID_SHA256_ARM32"
    elif [ ! -f "$tarball" ]; then
      echo "This 32-bit Arm Python recipe is $name; pins.env has ${PYTHON_ANDROID_ARM32_RELEASE:-none}. Building it here." >&2
      "$here/python-arm32.sh" "$work/build-$triple" "$tarball"
    fi
  elif [ "$pin" = unpinned ]; then
    # Goes on, so one run prints every sum, and fails at the end.
    curl -fsSL --retry 5 --retry-all-errors -o "$tarball" "$url"
    echo "$url has SHA-256 $(sha256sum "$tarball" | cut -d' ' -f1); pin it in .github/pins.env" >&2
    unpinned=1
  else
    fetch "$url" "$tarball" "$pin"
  fi
  local src="$work/$abi/src" stage="$work/$abi/stage"
  rm -rf "$work/$abi"
  mkdir -p "$src" "$stage/usr/lib" "$stage/usr/etc/tls" "$jni/$abi"
  tar -xzf "$tarball" -C "$src"
  local prefix="$src/prefix"
  [ -f "$prefix/lib/libpython$minor.so" ] || { echo "$tarball has no prefix/lib/libpython$minor.so" >&2; exit 1; }

  # The interpreter and the libraries it loads, in the library folder.
  rm -f "$jni/$abi"/libpython*.so
  # CPython's modules load the *_python.so builds of OpenSSL and SQLite;
  # the tarballs also carry unsuffixed copies, which nothing loads.
  cp -L "$prefix"/lib/libpython*.so "$prefix"/lib/lib*_python.so "$jni/$abi/"
  "$clang_bin/${clang}24-clang" -O2 -fPIE -pie \
    -I"$prefix/include/python$minor" -L"$prefix/lib" \
    -Wl,-z,max-page-size=16384 \
    -o "$jni/$abi/libpython.so" "$here/python-launcher.c" -lpython"$minor"

  # The standard library, without what yt-dlp never uses.
  cp -a "$prefix/lib/python$minor" "$stage/usr/lib/"
  local stdlib="$stage/usr/lib/python$minor"
  rm -rf "$stdlib"/{test,idlelib,tkinter,turtledemo,turtle.py,ensurepip,pydoc_data,__phello__}
  find "$stdlib/lib-dynload" \( -name '_test*' -o -name 'xx*' -o -name '_ctypes_test*' -o -name '_xxtestfuzz*' -o -name '_tkinter*' \) -delete
  find "$stage" -name '__pycache__' -prune -exec rm -rf {} +
  # The certificates Python's OpenSSL trusts: the Chrome Root Store list
  # the core can use as well (native/lumtub_core/roots).
  cp "$root/native/lumtub_core/roots/chrome.pem" "$stage/usr/etc/tls/cert.pem"
  rm -f "$jni/$abi/libpython.zip.so"
  (cd "$stage" && zip -qry -9 "$jni/$abi/libpython.zip.so" usr)
  ls -l "$jni/$abi"
  llvm-readelf -d "$jni/$abi/libpython.so" | grep NEEDED
}

build_abi arm64-v8a aarch64-linux-android aarch64-linux-android "$PYTHON_ANDROID_SHA256_ARM64"
build_abi armeabi-v7a arm-linux-androideabi armv7a-linux-androideabi built
build_abi x86_64 x86_64-linux-android x86_64-linux-android "$PYTHON_ANDROID_SHA256_X86_64"
[ -z "$unpinned" ] || exit 1

# yt-dlp: the pinned release's zip app, also checked against the
# SHA2-256SUMS that release publishes.
base="https://github.com/yt-dlp/yt-dlp/releases/download/$YTDLP_VERSION"
fetch "$base/yt-dlp" "$downloads/yt-dlp-$YTDLP_VERSION" "$YTDLP_SHA256"
curl -fsSL --retry 5 --retry-all-errors -o "$downloads/SHA2-256SUMS-$YTDLP_VERSION" "$base/SHA2-256SUMS"
listed=$(awk '$2 == "yt-dlp" { print $1 }' "$downloads/SHA2-256SUMS-$YTDLP_VERSION")
[ "$listed" = "$YTDLP_SHA256" ] || { echo "yt-dlp $YTDLP_VERSION: SHA2-256SUMS lists '$listed', pinned $YTDLP_SHA256" >&2; exit 1; }
mkdir -p "$root/android/app/src/main/res/raw"
cp "$downloads/yt-dlp-$YTDLP_VERSION" "$root/android/app/src/main/res/raw/ytdlp"
unzip -p "$root/android/app/src/main/res/raw/ytdlp" yt_dlp/version.py 2> /dev/null | grep '^__version__' || true
