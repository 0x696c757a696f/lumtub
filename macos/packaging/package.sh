#!/usr/bin/env bash
# Finishes Lumtub.app and packs it in a DMG.
#
#   package.sh <Lumtub.app> <liblumtub_core.dylib> <ffmpeg folder> <ffmpeg version> <dmg> [arm64|x86_64]
#
# The app is built for both CPUs; given a CPU, the DMG holds a copy thinned
# to it, about half the size. The ffmpeg folder is an unpacked release of
# dfloresc/ffmpeg-macos-builds for that CPU (bin/, lib/, LICENSES/).
#
# With APPLE_SIGN_IDENTITY set (a Developer ID Application certificate in
# the keychain), the app is signed with the hardened runtime, and with
# APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD it is also notarized and
# stapled. Without them it is signed ad hoc: Apple silicon runs no
# unsigned code, and the first start needs "Open Anyway".
set -euo pipefail

app=$1
core=$2
ffmpeg=$3
ffmpeg_version=$4
dmg=$5
arch=${6:-}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

cp "$core" "$app/Contents/Frameworks/"
printf '%s\n' "$ffmpeg_version" > "$app/Contents/Resources/ffmpeg-version.txt"
cp "$root/LICENSE" "$root/NOTICE" "$app/Contents/Resources/"
if [[ -n "$arch" ]]; then
  thin=$(mktemp -d)/Lumtub.app
  ditto --arch "$arch" "$app" "$thin"
  app=$thin
fi

# ffmpeg and ffprobe load their libraries from @rpath, which points at
# ../lib in the release; here the libraries go in Frameworks, under the
# names the programs ask for, without the symlinks.
rm -f "$app/Contents/MacOS/ffmpeg" "$app/Contents/MacOS/ffprobe" "$app/Contents/Frameworks/"libav*.dylib "$app/Contents/Frameworks/"libsw*.dylib
cp "$ffmpeg/bin/ffmpeg" "$ffmpeg/bin/ffprobe" "$app/Contents/MacOS/"
ffmpeg_libs=()
for tool in ffmpeg ffprobe; do
  while read -r name; do
    ffmpeg_libs+=("$name")
  done < <(otool -L "$app/Contents/MacOS/$tool" | sed -n 's|^[[:space:]]*@rpath/\([^ ]*\) .*|\1|p')
  install_name_tool -delete_rpath @executable_path/../lib "$app/Contents/MacOS/$tool" 2>/dev/null || true
  install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/$tool"
done
for name in $(printf '%s\n' "${ffmpeg_libs[@]}" | sort -u); do
  cp -L "$ffmpeg/lib/$name" "$app/Contents/Frameworks/$name"
done
rm -rf "$app/Contents/Resources/ffmpeg-licenses"
cp -R "$ffmpeg/LICENSES" "$app/Contents/Resources/ffmpeg-licenses"

identity=${APPLE_SIGN_IDENTITY:-}
if [[ -n "$identity" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$root/macos/Runner/Release.entitlements" --sign "$identity" "$app"
else
  codesign --force --deep --sign - "$app"
fi
codesign --verify --deep --strict "$app"
for binary in "$app/Contents/MacOS/"* "$app/Contents/Frameworks/"*.dylib; do
  lipo -info "$binary"
done

stage=$(mktemp -d)
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -volname Lumtub -srcfolder "$stage" -fs HFS+ -format UDZO "$dmg"
rm -rf "$stage"

if [[ -n "$identity" ]]; then
  codesign --force --timestamp --sign "$identity" "$dmg"
  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    xcrun notarytool submit "$dmg" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
    xcrun stapler staple "$dmg"
  fi
fi
ls -l "$dmg"
