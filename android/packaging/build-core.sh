#!/usr/bin/env bash
# Builds the Rust core for each Android ABI into the APK's jniLibs.
# Needs cargo-ndk and ANDROID_NDK_HOME (NDK r28 or newer: 16 KB pages).
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/android/app/src/main/jniLibs"
mkdir -p "$out"
cd "$root/native/lumtub_core"
cargo ndk --platform 24 -t arm64-v8a -t armeabi-v7a -t x86_64 -o "$out" build --release --lib
# Every library must load on devices with 16 KB pages.
for so in "$out"/*/*.so; do
  align=$(llvm-readelf -lW "$so" 2>/dev/null | awk '$1 == "LOAD" { print $NF; exit }')
  echo "$(basename "$(dirname "$so")")/$(basename "$so"): $(stat -c %s "$so") bytes, LOAD align $align"
done
