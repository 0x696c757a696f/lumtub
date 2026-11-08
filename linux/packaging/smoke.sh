#!/usr/bin/env bash
# Starts the AppImage on a virtual X display with a fresh home folder, lets
# it play a generated video and a YouTube video (see lib/app/smoke_check.dart)
# and keeps what it reports, its log and pictures of the window in <output>.
#
#   smoke.sh <AppImage> <output folder>
set -uo pipefail

appimage=$(realpath "$1")
out=$2
mkdir -p "$out/home"
out=$(cd "$out" && pwd)

ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=1280x720:rate=30 -f lavfi -i sine=frequency=440 \
  -t 15 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$out/test.mp4"

cat > "$out/run.sh" <<'RUN'
#!/usr/bin/env bash
out=$1 appimage=$2
HOME="$out/home" APPIMAGE_EXTRACT_AND_RUN=1 LUMTUB_SMOKE="$out/result.json" LUMTUB_SMOKE_VIDEO="$out/test.mp4" \
  LUMTUB_SMOKE_YOUTUBE=jNQXAC9IVRw timeout 420 "$appimage" > "$out/stdout.txt" 2>&1 &
app=$!
shot=0
while kill -0 "$app" 2> /dev/null; do
  sleep 10
  shot=$((shot + 1))
  import -window root "$out/window-$(printf %02d "$shot").png" 2> /dev/null || true
done
wait "$app"
RUN
chmod +x "$out/run.sh"
xvfb-run -a -s "-screen 0 1600x1000x24" "$out/run.sh" "$out" "$appimage"
code=$?
cp -r "$out/home/.local/share/lumtub/logs" "$out/logs" 2> /dev/null || true
rm -rf "$out/home"
cat "$out/result.json" 2> /dev/null || echo "No result written."
if [[ $code -ne 0 ]]; then
  echo "--- end of the app's output"
  tail -n 40 "$out/stdout.txt" 2> /dev/null
  echo "--- end of its log"
  tail -n 60 "$out"/logs/*.log 2> /dev/null
fi
echo "Exit code $code"
exit "$code"
