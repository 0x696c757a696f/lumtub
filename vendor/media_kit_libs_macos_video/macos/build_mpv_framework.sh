#!/bin/bash
# Links MPVKit's static libraries (mpv, FFmpeg, libplacebo, libass and the
# rest, listed in mpvkit.lock) into the one dynamic Mpv.framework that
# media_kit loads, for arm64 and x86_64, and wraps it in Mpv.xcframework.
#
#   build_mpv_framework.sh <lock file> <cache folder> <output xcframework>

set -euo pipefail

LOCK="$1"
CACHE="$2"
OUT="$3"
MIN_MACOS=12.0

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
  slice=$(find "$WORK/$name" -maxdepth 2 -type d -name 'macos-*' | head -n1)
  if [ -z "$slice" ]; then
    echo "$name has no macOS slice" >&2
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

fw="$WORK/out/Mpv.framework"
mkdir -p "$fw/Versions/A/Headers/mpv" "$fw/Versions/A/Resources"
# MPVKit keeps them in Headers/mpv; plain Headers also works.
client=$(find "$headers" -name client.h | head -n1)
[ -n "$client" ] || { echo "Libmpv has no client.h" >&2; exit 1; }
cp "$(dirname "$client")"/*.h "$fw/Versions/A/Headers/mpv/"

# mpv's macOS code is partly Swift: link the Swift compatibility shims
# from the toolchain; the Swift runtime itself is part of macOS 12.
toolchain=$(dirname "$(dirname "$(xcrun -f swiftc)")")
swift_libs=(-L"$toolchain/lib/swift/macosx" -L"$(xcrun --show-sdk-path)/usr/lib/swift" -Wl,-rpath,/usr/lib/swift)

xcrun clang -dynamiclib \
  -arch arm64 -arch x86_64 \
  -mmacosx-version-min="$MIN_MACOS" \
  -install_name @rpath/Mpv.framework/Versions/A/Mpv \
  -o "$fw/Versions/A/Mpv" \
  -Wl,-force_load,"$mpv" \
  "${libs[@]}" \
  -Wl,-exported_symbol,'_mpv_*' \
  -Wl,-dead_strip \
  -framework AVFoundation -framework AppKit -framework AudioToolbox \
  -framework CoreAudio -framework CoreFoundation -framework CoreGraphics \
  -framework CoreMedia -framework CoreServices -framework CoreText \
  -framework CoreVideo -framework Foundation -framework IOKit \
  -framework IOSurface -framework Metal -framework OpenGL \
  -framework QuartzCore -framework Security -framework SystemConfiguration \
  -framework VideoToolbox \
  -lbz2 -lc++ -lexpat -liconv -lresolv -lxml2 -lz \
  "${swift_libs[@]}"

cat > "$fw/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Mpv</string>
  <key>CFBundleIdentifier</key><string>io.mpv.Mpv</string>
  <key>CFBundleName</key><string>Mpv</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
</dict>
</plist>
PLIST
ln -s A "$fw/Versions/Current"
ln -s Versions/Current/Mpv "$fw/Mpv"
ln -s Versions/Current/Headers "$fw/Headers"
ln -s Versions/Current/Resources "$fw/Resources"

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
