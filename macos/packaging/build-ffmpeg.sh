#!/usr/bin/env bash
# Builds the ffmpeg and ffprobe the macOS app carries, for Apple silicon
# and Intel in one file each. LGPL, with container formats only and no
# codecs: Lumtub uses ffmpeg to copy streams into MP4 or MKV and to cut
# audio for speech recognition, never to re-encode.
#
#   build-ffmpeg.sh <ffmpeg source> <output folder>
set -euo pipefail

source=$(cd "$1" && pwd)
out=$2
mkdir -p "$out"
out=$(cd "$out" && pwd)
jobs=$(sysctl -n hw.ncpu)

for arch in arm64 x86_64; do
  build="$out/build-$arch"
  rm -rf "$build"
  mkdir -p "$build"
  (
    cd "$build"
    "$source/configure" \
      --arch="$arch" --target-os=darwin --enable-cross-compile \
      --cc="clang -arch $arch" \
      --extra-cflags="-mmacosx-version-min=12.0" --extra-ldflags="-mmacosx-version-min=12.0" \
      --disable-everything --disable-autodetect --disable-network --disable-x86asm \
      --disable-doc --disable-debug --disable-ffplay --enable-ffmpeg --enable-ffprobe \
      --enable-demuxers --enable-muxers --enable-parsers --enable-bsfs \
      --enable-protocol=file,pipe
    make -j"$jobs" ffmpeg ffprobe
  )
done

for program in ffmpeg ffprobe; do
  lipo -create -output "$out/$program" "$out/build-arm64/$program" "$out/build-x86_64/$program"
  strip -x "$out/$program"
  lipo -info "$out/$program"
done
"$out/ffmpeg" -hide_banner -version | head -1
rm -rf "$out/build-arm64" "$out/build-x86_64"
