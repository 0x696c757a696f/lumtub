#!/usr/bin/env bash
# Starts the AppImage on a virtual X display with a fresh home folder and
# takes the pictures it asks for (see runShowcase in lib/app/smoke_check.dart).
#
#   showcase.sh <AppImage> <output folder>
set -uo pipefail

appimage=$(realpath "$1")
out=$2
mkdir -p "$out/home"
out=$(cd "$out" && pwd)

cat > "$out/run.sh" <<'RUN'
#!/usr/bin/env bash
out=$1 appimage=$2
HOME="$out/home" LANG=en_US.UTF-8 APPIMAGE_EXTRACT_AND_RUN=1 LUMTUB_SHOWCASE="$out" LUMTUB_TOUR=1 timeout 1200 "$appimage" > "$out/stdout.txt" 2>&1 &
app=$!
recorder=
while kill -0 "$app" 2> /dev/null; do
  window=$(xdotool search --onlyvisible --name Lumtub | head -n 1)
  if [ -e "$out/rec-start" ]; then
    eval "$(xdotool getwindowgeometry --shell "$window")"
    ffmpeg -hide_banner -loglevel error -y -f x11grab -draw_mouse 0 -framerate 30 -video_size "${WIDTH}x${HEIGHT}" -i "$DISPLAY+$X,$Y" \
      -c:v libx264 -preset veryfast -crf 16 -pix_fmt yuv420p "$out/$(cat "$out/rec-start")" < /dev/null &
    recorder=$!
    sleep 1
    rm -f "$out/rec-start"
  fi
  for xdo in "$out"/xdo-*; do
    [ -e "$xdo" ] || continue
    # shellcheck disable=SC2046
    xdotool $(sed "s/%W/$window/g" "$xdo")
    rm -f "$xdo"
  done
  if [ -e "$out/rec-stop" ]; then
    [ -n "$recorder" ] && kill -INT "$recorder" && wait "$recorder"
    recorder=
    rm -f "$out/rec-stop"
  fi
  for want in "$out"/want-*; do
    [ -e "$want" ] || continue
    name=${want##*/want-}
    import -window "${window:-root}" "$out/$name.tmp.png" 2> /dev/null && mv "$out/$name.tmp.png" "$out/$name.png"
    rm -f "$want"
  done
  sleep 0.5
done
wait "$app"
[ -n "$recorder" ] && kill -INT "$recorder" && wait "$recorder"
RUN
chmod +x "$out/run.sh"
xvfb-run -a -s "-screen 0 1920x1200x24" "$out/run.sh" "$out" "$appimage"
cp "$out/home/.local/share/lumtub/logs/lumtub.log" "$out/" 2> /dev/null || true
rm -rf "$out/home" "$out/run.sh"
ls -l "$out"
tail -n 40 "$out/stdout.txt"
