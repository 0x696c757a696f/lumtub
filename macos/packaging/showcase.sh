#!/usr/bin/env bash
# Opens the DMG, starts the app with LUMTUB_SHOWCASE and takes the pictures
# it asks for (see runShowcase in lib/app/smoke_check.dart) of its window.
#
#   showcase.sh <DMG> <output folder>
set -uo pipefail

dmg=$1
out=$2
mkdir -p "$out"
out=$(cd "$out" && pwd)
work=$(mktemp -d)

mount=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$mount" "$dmg" > /dev/null
ditto "$mount/Lumtub.app" "$work/Lumtub.app"
hdiutil detach "$mount" > /dev/null

cat > "$work/window.swift" <<'SWIFT'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where window[kCGWindowOwnerName as String] as? String == "Lumtub" && window[kCGWindowLayer as String] as? Int == 0 {
  print(window[kCGWindowNumber as String]!)
  break
}
SWIFT
swiftc -O -o "$work/window" "$work/window.swift"

rm -rf "$HOME/Library/Application Support/Lumtub"
LUMTUB_SHOWCASE="$out" "$work/Lumtub.app/Contents/MacOS/Lumtub" > "$out/stdout.txt" 2>&1 &
app=$!
end=$((SECONDS + 900))
while kill -0 "$app" 2> /dev/null && [ "$SECONDS" -lt "$end" ]; do
  for want in "$out"/want-*; do
    [ -e "$want" ] || continue
    name=${want##*/want-}
    id=$("$work/window")
    if [ -n "$id" ]; then
      screencapture -x -l "$id" "$out/$name.tmp.png" && mv "$out/$name.tmp.png" "$out/$name.png"
    fi
    rm -f "$want"
  done
  sleep 0.5
done
kill "$app" 2> /dev/null
wait "$app"
cp "$HOME/Library/Application Support/Lumtub/logs/lumtub.log" "$out/" 2> /dev/null || true
rm -rf "$work"
ls -l "$out"
tail -n 40 "$out/lumtub.log" 2> /dev/null
