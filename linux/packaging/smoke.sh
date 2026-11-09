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
  LUMTUB_SMOKE_YOUTUBE=jNQXAC9IVRw timeout 720 "$appimage" > "$out/stdout.txt" 2>&1 &
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
if [[ $code -ne 0 ]] && command -v gdb > /dev/null; then
  # Once more under gdb, for where it stopped.
  echo "--- once more under gdb"
  (
    cd "$out" && "$appimage" --appimage-extract > /dev/null
    mkdir -p "$out/home"
    # gdb starts the program itself, not AppRun: give it every fallback library.
    spares=$(find "$out/squashfs-root/usr/bin/lib/fallback" -mindepth 1 -maxdepth 1 -type d 2> /dev/null | paste -sd: -)
    no_pw=; ldconfig -p | grep -q libpipewire-0.3.so.0 || no_pw=1
    LUMTUB_NO_PIPEWIRE=$no_pw LD_LIBRARY_PATH="$spares${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" HOME="$out/home" LUMTUB_SMOKE="$out/result-gdb.json" LUMTUB_SMOKE_VIDEO="$out/test.mp4" LUMTUB_SMOKE_YOUTUBE=jNQXAC9IVRw \
      timeout 300 xvfb-run -a -s "-screen 0 1600x1000x24" gdb -q -batch -ex 'handle SIGPIPE nostop noprint' -ex run -ex bt -ex 'thread apply all bt 25' \
      --args "$out/squashfs-root/usr/bin/lumtub" > "$out/gdb.txt" 2>&1
    grep -v '^\[New Thread\|^\[Thread .* exited\|^\[Detaching' "$out/gdb.txt" | grep -B5 -A60 -m1 'received signal\|exited with code' || tail -n 80 "$out/gdb.txt"
    rm -rf "$out/squashfs-root" "$out/home"
  )
fi
echo "Exit code $code"
exit "$code"
