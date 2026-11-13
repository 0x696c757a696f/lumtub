#!/usr/bin/env bash
# Finishes Runner.app and packs it in an IPA for sideloading.
#
#   package.sh <Runner.app> <liblumtub_core.dylib> <ipa>
#
# Without an Apple developer account the app is signed ad hoc only:
# SideStore, AltStore, Sideloadly and TrollStore sign it again with the
# user's own Apple ID (or, in TrollStore's case, install it as it is).
set -euo pipefail

app=$1
core=$2
ipa=$3
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
min_ios=$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist")

# The Rust core as a framework, the only form of dynamic library iOS
# accepts inside an app.
framework="$app/Frameworks/LumtubCore.framework"
rm -rf "$framework"
mkdir -p "$framework"
cp "$core" "$framework/LumtubCore"
install_name_tool -id @rpath/LumtubCore.framework/LumtubCore "$framework/LumtubCore"
cat > "$framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>LumtubCore</string>
  <key>CFBundleIdentifier</key><string>io.github.lumtub.LumtubCore</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>LumtubCore</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>$min_ios</string>
</dict>
</plist>
PLIST

cp "$root/LICENSE" "$root/NOTICE" "$app/"

for binary in "$app/Frameworks/"*.framework; do
  name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$binary/Info.plist")
  lipo -info "$binary/$name"
  codesign --force --sign - "$binary"
done
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

stage=$(mktemp -d)
mkdir "$stage/Payload"
cp -R "$app" "$stage/Payload/Lumtub.app"
rm -f "$ipa"
ipa_path=$(cd "$(dirname "$ipa")" && pwd)/$(basename "$ipa")
(cd "$stage" && zip -qry "$ipa_path" Payload)
rm -rf "$stage"
ls -l "$ipa"
