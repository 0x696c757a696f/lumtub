#!/usr/bin/env bash
# Builds the ffmpeg and ffprobe the macOS app carries, for Apple silicon
# and Intel in one file each: LGPL with FFmpeg's own codecs, filters and
# formats plus VideoToolbox and AudioToolbox, like the LGPL build Windows
# downloads. No external libraries and no network protocols.
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
      --disable-autodetect --enable-videotoolbox --enable-audiotoolbox \
      --disable-network --disable-x86asm --disable-devices \
      --disable-doc --disable-debug --disable-ffplay --enable-ffmpeg --enable-ffprobe \
      --disable-protocols --enable-protocol=file,pipe
    make -j"$jobs" ffmpeg ffprobe
  )
done

for program in ffmpeg ffprobe; do
  lipo -create -output "$out/$program" "$out/build-arm64/$program" "$out/build-x86_64/$program"
  strip -x "$out/$program"
  lipo -info "$out/$program"
done
"$out/ffmpeg" -hide_banner -version | head -1
# Fails the build if the codecs are missing again.
"$out/ffmpeg" -hide_banner -encoders | grep -q ' aac '
"$out/ffmpeg" -hide_banner -decoders | grep -q ' vp9 '
rm -rf "$out/build-arm64" "$out/build-x86_64"
