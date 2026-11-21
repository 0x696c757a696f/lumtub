#!/usr/bin/env bash
# Builds CPython for 32-bit Arm Android (arm-linux-androideabi), which
# python.org does not publish, with CPython's own Android/android.py: the
# same build python.org's arm64 and x86_64 tarballs come from. Writes
# <tarball> laid out like those (prefix/lib/libpython3.x.so, ...), so
# python.sh treats all three ABIs alike.
#
#   python-arm32.sh <work folder> <tarball>
#
# Needs ANDROID_HOME (android-env.sh installs the NDK it wants when missing)
# and PYTHON_ANDROID_VERSION, PYTHON_ANDROID_SOURCE_COMMIT and
# PYTHON_ANDROID_ARM32_DEPS of .github/pins.env. The source is the pinned
# commit of the version's tag; the libraries are BeeWare's
# cpython-android-source-deps tarballs, checked against their pinned sums and
# unpacked before android.py would download them unchecked.
set -euo pipefail
work=$1
out=$2
host=arm-linux-androideabi
version=$PYTHON_ANDROID_VERSION
: "${ANDROID_HOME:?}"

src="$work/cpython"
rm -rf "$src"
git init -q "$src"
git -C "$src" fetch -q --depth 1 https://github.com/python/cpython.git "refs/tags/v$version"
commit=$(git -C "$src" rev-parse 'FETCH_HEAD^{commit}')
[ "$commit" = "$PYTHON_ANDROID_SOURCE_COMMIT" ] || { echo "CPython v$version is $commit, pinned $PYTHON_ANDROID_SOURCE_COMMIT" >&2; exit 1; }
git -C "$src" checkout -q FETCH_HEAD

# Older android.py lists only the hosts python.org releases; its env script
# and configure still know 32-bit Arm.
if ! grep -q '"arm-linux-androideabi"' "$src/Android/android.py"; then
  sed -i 's/^HOSTS = \["aarch64-linux-android", "x86_64-linux-android"\]$/HOSTS = ["aarch64-linux-android", "arm-linux-androideabi", "x86_64-linux-android"]/' "$src/Android/android.py"
  grep -q '"arm-linux-androideabi"' "$src/Android/android.py" || { echo "android.py: could not add $host to HOSTS" >&2; exit 1; }
fi

prefix="$src/cross-build/$host/prefix"
mkdir -p "$prefix" "$work/deps"
IFS=, read -ra deps <<< "$PYTHON_ANDROID_ARM32_DEPS"
for dep in "${deps[@]}"; do
  name=${dep%%:*} sum=${dep#*:}
  file="$work/deps/$name-$host.tar.gz"
  if ! { [ -f "$file" ] && echo "$sum  $file" | sha256sum -c - > /dev/null 2>&1; }; then
    curl -fsSL --retry 5 --retry-all-errors -o "$file" \
      "https://github.com/beeware/cpython-android-source-deps/releases/download/$name/$name-$host.tar.gz"
    echo "$sum  $file" | sha256sum -c - > /dev/null || { echo "$name: SHA-256 is $(sha256sum "$file" | cut -d' ' -f1), pinned $sum" >&2; exit 1; }
  fi
  tar -xzf "$file" -C "$prefix"
done

cd "$src"
# Newer android.py builds one target at a time: the build machine's Python
# first, then the host's.
if grep -q '^def build_targets' Android/android.py; then
  python3 Android/android.py build build
fi
python3 Android/android.py build "$host"
python3 Android/android.py package "$host"
built=$(ls "$src/cross-build/$host/dist"/python-*-"$host".tar.gz)
mkdir -p "$(dirname "$out")"
cp "$built" "$out"
echo "Built $out from CPython $commit"
