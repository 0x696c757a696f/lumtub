#!/usr/bin/env bash
# Builds the Rust core for each Android ABI into the APK's jniLibs.
# Needs cargo-ndk and ANDROID_NDK_HOME (NDK r28 or newer: 16 KB pages).
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/android/app/src/main/jniLibs"
mkdir -p "$out"
cd "$root/native/lumtub_core"
# The verifier's Kotlin half (android/app/build.gradle.kts) must match the
# crate the core is built with.
crate=$(awk '/^name = "rustls-platform-verifier-android"$/ { getline; gsub(/[^0-9.]/, ""); print }' Cargo.lock)
grep -q "org.rustls:rustls-platform-verifier:$crate\"" "$root/android/app/build.gradle.kts" || {
  echo "android/app/build.gradle.kts must use org.rustls:rustls-platform-verifier:$crate" >&2
  exit 1
}
# bindgen (QuickJS's bindings) needs the API level in the target, as the
# NDK's headers refuse an unversioned one. cargo-ndk sets the underscore
# form of these variables; bindgen reads the hyphenated form first.
sysroot="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
bindgen_args=(
  "BINDGEN_EXTRA_CLANG_ARGS_aarch64-linux-android=--target=aarch64-linux-android24 --sysroot=$sysroot"
  "BINDGEN_EXTRA_CLANG_ARGS_armv7-linux-androideabi=--target=armv7a-linux-androideabi24 --sysroot=$sysroot"
  "BINDGEN_EXTRA_CLANG_ARGS_x86_64-linux-android=--target=x86_64-linux-android24 --sysroot=$sysroot"
)
env "${bindgen_args[@]}" cargo ndk --platform 24 -t arm64-v8a -t armeabi-v7a -t x86_64 -o "$out" build --release --lib
# Every library must load on devices with 16 KB pages.
for so in "$out"/*/*.so; do
  align=$(llvm-readelf -lW "$so" 2>/dev/null | awk '$1 == "LOAD" && !a { a = $NF } END { print a }')
  echo "$(basename "$(dirname "$so")")/$(basename "$so"): $(stat -c %s "$so") bytes, LOAD align $align"
done
