#!/bin/bash
# Links MPVKit's static libraries (mpv, FFmpeg, libplacebo, libass and the
# rest, listed in mpvkit.lock) into the one dynamic Mpv.framework that
# media_kit loads, for iPhone and iPad (arm64), and wraps it in
# Mpv.xcframework.
#
#   build_mpv_framework.sh <lock file> <cache folder> <output xcframework>

set -euo pipefail

LOCK="$1"
CACHE="$2"
OUT="$3"
MIN_IOS=15.0

mkdir -p "$CACHE/zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

libs=()
mpv=
while read -r name sum url; do
  case "$name" in ''|'#'*) continue ;; esac
  zip="$CACHE/zip/$name-$sum.zip"
  if [ ! -f "$zip" ]; then
    curl -fsSL --retry 3 -o "$zip.tmp" "$url"
    mv "$zip.tmp" "$zip"
  fi
  if ! echo "$sum  $zip" | shasum -a 256 -c --status; then
    rm -f "$zip"
    echo "Checksum mismatch for $name ($url)" >&2
    exit 1
  fi
  mkdir -p "$WORK/$name"
  unzip -q -o "$zip" -d "$WORK/$name"
  # The device slice: ios-arm64, not the simulator or Mac Catalyst ones.
  slice=$(find "$WORK/$name" -maxdepth 2 -type d -name 'ios-arm64' | head -n1)
  if [ -z "$slice" ]; then
    echo "$name has no iOS device slice:" >&2
    find "$WORK/$name" -maxdepth 2 -type d >&2
    exit 1
  fi
  framework=$(find "$slice" -maxdepth 1 -name '*.framework' | head -n1)
  if [ -n "$framework" ]; then
    lib="$framework/$(basename "$framework" .framework)"
  else
    lib=$(find "$slice" -maxdepth 1 -name '*.a' | head -n1)
  fi
  if [ "$name" = Libmpv ]; then
    mpv="$lib"
    headers="$framework/Headers"
  else
    libs+=("$lib")
  fi
done < "$LOCK"

if [ -z "$mpv" ]; then
  echo "mpvkit.lock has no Libmpv" >&2
  exit 1
fi

# iOS frameworks are flat: no Versions folder.
fw="$WORK/out/Mpv.framework"
mkdir -p "$fw/Headers/mpv"
client=$(find "$headers" -name client.h | head -n1)
[ -n "$client" ] || { echo "Libmpv has no client.h" >&2; exit 1; }
cp "$(dirname "$client")"/*.h "$fw/Headers/mpv/"

sdk=$(xcrun --sdk iphoneos --show-sdk-path)
toolchain=$(dirname "$(dirname "$(xcrun -f swiftc)")")
swift_libs=(-L"$toolchain/lib/swift/iphoneos" -L"$sdk/usr/lib/swift" -Wl,-rpath,/usr/lib/swift)

xcrun --sdk iphoneos clang -dynamiclib \
  -arch arm64 \
  -isysroot "$sdk" \
  -miphoneos-version-min="$MIN_IOS" \
  -install_name @rpath/Mpv.framework/Mpv \
  -o "$fw/Mpv" \
  -Wl,-force_load,"$mpv" \
  "${libs[@]}" \
  -Wl,-exported_symbol,'_mpv_*' \
  -Wl,-dead_strip \
  -framework AVFoundation -framework AudioToolbox -framework CoreAudio \
  -framework CoreFoundation -framework CoreGraphics -framework CoreMedia \
  -framework CoreText -framework CoreVideo -framework Foundation \
  -framework IOSurface -framework Metal -framework OpenGLES \
  -framework QuartzCore -framework Security -framework SystemConfiguration \
  -framework UIKit -framework VideoToolbox \
  -lbz2 -lc++ -liconv -lresolv -lxml2 -lz \
  "${swift_libs[@]}"

cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Mpv</string>
  <key>CFBundleIdentifier</key><string>io.mpv.Mpv</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Mpv</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>$MIN_IOS</string>
</dict>
</plist>
PLIST

lipo -info "$fw/Mpv"
otool -L "$fw/Mpv"
if nm -gU "$fw/Mpv" | grep -v ' _mpv_' | grep -q ' [TDS] '; then
  echo "Mpv exports more than mpv_* symbols:" >&2
  nm -gU "$fw/Mpv" | grep -v ' _mpv_' | head >&2
  exit 1
fi
nm -gU "$fw/Mpv" | grep -c ' _mpv_' | sed 's/^/mpv functions exported: /'

rm -rf "$OUT"
xcodebuild -create-xcframework -framework "$fw" -output "$OUT" > /dev/null
echo "Built $OUT"
