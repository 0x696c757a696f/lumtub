#!/usr/bin/env bash
# Builds libmpv for the AppImage. Ubuntu 22.04's own libmpv (0.34) stops
# on an assertion when it has to draw in software, which a machine without
# a working GPU driver does; 0.35.1 is the libmpv the AppImage carried
# before. Only the library, without the mpv player; Lua, JavaScript and
# the manual are left out because their packages are not installed.
#
#   build-mpv.sh <mpv source> <prefix>
set -euo pipefail

source=$(cd "$1" && pwd)
prefix=$2
build="$source/build"

meson setup "$build" "$source" \
  --prefix="$prefix" --libdir=lib --buildtype=release \
  -Dlibmpv=true -Dcplayer=false
meson compile -C "$build"
meson install -C "$build"
PKG_CONFIG_PATH="$prefix/lib/pkgconfig" pkg-config --modversion mpv
