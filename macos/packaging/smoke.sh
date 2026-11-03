#!/usr/bin/env bash
# Opens the DMG, starts the app inside it, lets it play a generated video
# and a YouTube video (see lib/app/smoke_check.dart) and keeps what it
# reports, its log and pictures of the screen in <output>.
#
#   smoke.sh <DMG> <output folder>
set -uo pipefail

dmg=$1
out=$2
mkdir -p "$out"
out=$(cd "$out" && pwd)

mount=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$mount" "$dmg" > /dev/null
ditto "$mount/Lumtub.app" "$out/Lumtub.app"
hdiutil detach "$mount" > /dev/null
ffmpeg="$out/Lumtub.app/Contents/MacOS/ffmpeg"
"$ffmpeg" -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=1280x720:rate=30 -f lavfi -i sine=frequency=440 \
  -t 15 -c:v h264_videotoolbox -b:v 4M -c:a aac -shortest "$out/test.mp4" \
  || "$ffmpeg" -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=1280x720:rate=30 -f lavfi -i sine=frequency=440 \
    -t 15 -c:v mpeg4 -q:v 4 -c:a aac -shortest "$out/test.mp4"

LUMTUB_SMOKE="$out/result.json" LUMTUB_SMOKE_VIDEO="$out/test.mp4" LUMTUB_SMOKE_YOUTUBE=jNQXAC9IVRw \
  "$out/Lumtub.app/Contents/MacOS/Lumtub" > "$out/stdout.txt" 2>&1 &
app=$!
shot=0
for _ in $(seq 42); do
  kill -0 "$app" 2> /dev/null || break
  sleep 10
  shot=$((shot + 1))
  screencapture -x "$out/screen-$(printf %02d "$shot").png" 2> /dev/null || true
done
kill "$app" 2> /dev/null
wait "$app"
code=$?
cp -r "$HOME/Library/Application Support/Lumtub/logs" "$out/logs" 2> /dev/null || true
rm -rf "$out/Lumtub.app"
cat "$out/result.json" 2> /dev/null || echo "No result written."
echo "Exit code $code"
exit "$code"
