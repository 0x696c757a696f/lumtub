#!/usr/bin/env bash
# Finishes Lumtub.app and packs it in a DMG.
#
#   package.sh <Lumtub.app> <liblumtub_core.dylib> <dmg> [arm64|x86_64]
#
# The app is built for both CPUs; given a CPU, the DMG holds a copy thinned
# to it, about half the size.
#
# With APPLE_SIGN_IDENTITY set (a Developer ID Application certificate in
# the keychain), the app is signed with the hardened runtime, and with
# APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD it is also notarized and
# stapled. Without them it is signed ad hoc: Apple silicon runs no
# unsigned code, and the first start needs "Open Anyway".
set -euo pipefail

app=$1
core=$2
dmg=$3
arch=${4:-}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

cp "$core" "$app/Contents/Frameworks/"
cp "$root/LICENSE" "$root/NOTICE" "$app/Contents/Resources/"
if [[ -n "$arch" ]]; then
  thin=$(mktemp -d)/Lumtub.app
  ditto --arch "$arch" "$app" "$thin"
  app=$thin
fi

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
