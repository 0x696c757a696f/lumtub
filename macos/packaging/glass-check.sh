#!/usr/bin/env bash
# The window glass check (docs/specs/window-glass.md): opens the DMG, puts
# a magenta window behind the app, takes the pictures of the screen it asks
# for (runGlassCheck in lib/app/smoke_check.dart) and measures whether the
# magenta showed through (packaging/glass_measure.py).
#
#   glass-check.sh <DMG> <output folder>
set -uo pipefail

dmg=$1
out=$2
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"
out=$(cd "$out" && pwd)
work=$(mktemp -d)

mount=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$mount" "$dmg" > /dev/null
ditto "$mount/Lumtub.app" "$work/Lumtub.app"
hdiutil detach "$mount" > /dev/null

# The window's place on the screen, in points from the top left.
cat > "$work/bounds.swift" <<'SWIFT'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where window[kCGWindowOwnerName as String] as? String == "Lumtub" && window[kCGWindowLayer as String] as? Int == 0 {
  let b = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
  print("\(b["X"]!),\(b["Y"]!),\(b["Width"]!),\(b["Height"]!)")
  break
}
SWIFT
swiftc -O -o "$work/bounds" "$work/bounds.swift"

# What should show through: a magenta window over the whole screen.
cat > "$work/backdrop.swift" <<'SWIFT'
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let frame = NSScreen.main!.frame
let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
window.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
window.level = .normal
window.orderFrontRegardless()
app.run()
SWIFT
swiftc -O -o "$work/backdrop" "$work/backdrop.swift"
"$work/backdrop" &
backdrop=$!
sleep 2

rm -rf "$HOME/Library/Application Support/Lumtub"
LUMTUB_SHOWCASE="$out" LUMTUB_GLASS_CHECK=1 "$work/Lumtub.app/Contents/MacOS/Lumtub" > "$out/stdout.txt" 2>&1 &
app=$!
end=$((SECONDS + 300))
while kill -0 "$app" 2> /dev/null && [ "$SECONDS" -lt "$end" ]; do
  for want in "$out"/want-*; do
    [ -e "$want" ] || continue
    name=${want##*/want-}
    bounds=$("$work/bounds")
    if [ -n "$bounds" ]; then
      # The screen as shown where the window is, at one pixel per point.
      screencapture -x -R "$bounds" "$out/$name.tmp.png" && sips -s format png -s formatOptions default --resampleHeightWidth "$(echo "$bounds" | cut -d, -f4)" "$(echo "$bounds" | cut -d, -f3)" "$out/$name.tmp.png" --out "$out/$name.tmp.png" > /dev/null
      mv "$out/$name.tmp.png" "$out/$name.png"
    fi
    rm -f "$want"
  done
  sleep 0.5
done
kill "$app" "$backdrop" 2> /dev/null
wait "$app"
cp "$HOME/Library/Application Support/Lumtub/logs/lumtub.log" "$out/" 2> /dev/null || true
rm -rf "$work"
ls -l "$out"
grep -i "glass" "$out/lumtub.log" 2> /dev/null | tail -n 20
python3 "$here/../../packaging/glass_measure.py" "$out"
