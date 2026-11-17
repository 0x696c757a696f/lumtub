#!/usr/bin/env bash
# The window glass check (docs/specs/window-glass.md): starts the AppImage
# on a virtual X display with a compositor and a magenta window behind it,
# takes the pictures of the screen it asks for (runGlassCheck in
# lib/app/smoke_check.dart) and measures whether the magenta showed
# through (packaging/glass_measure.py).
#
#   glass-check.sh <AppImage> <output folder>
set -uo pipefail

appimage=$(realpath "$1")
out=$2
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out/home"
out=$(cd "$out" && pwd)

cat > "$out/run.sh" <<'RUN'
#!/usr/bin/env bash
out=$1 appimage=$2
# A compositor, so windows with an alpha channel blend with what is behind.
picom --backend xrender --no-fading-openclose --no-use-damage > "$out/picom.txt" 2>&1 &
sleep 2
# What should show through: a magenta window over the whole screen.
display -geometry 1920x1200+0+0 -size 1920x1200 xc:magenta &
sleep 2
HOME="$out/home" LANG=en_US.UTF-8 APPIMAGE_EXTRACT_AND_RUN=1 LUMTUB_SHOWCASE="$out" LUMTUB_GLASS_CHECK=1 timeout 300 "$appimage" > "$out/stdout.txt" 2>&1 &
app=$!
while kill -0 "$app" 2> /dev/null; do
  for want in "$out"/want-*; do
    [ -e "$want" ] || continue
    name=${want##*/want-}
    window=$(xdotool search --onlyvisible --name Lumtub | head -n 1)
    if [ -n "$window" ]; then
      eval "$(xdotool getwindowgeometry --shell "$window")"
      # Something new on the window makes the compositor draw again: the
      # pointer over the side rail items lights them, then leaves them.
      for _ in 1 2; do
        xdotool mousemove $((X + 30)) $((Y + 120)) sleep 1 mousemove $((X + 30)) $((Y + 200)) sleep 1 mousemove 0 0 sleep 1
      done
      # The screen as shown, compositor and all, where the window is.
      import -window root -crop "${WIDTH}x${HEIGHT}+${X}+${Y}" +repage -depth 8 "PNG24:$out/$name.tmp.png" 2> /dev/null && mv "$out/$name.tmp.png" "$out/$name.png"
    fi
    rm -f "$want"
  done
  sleep 0.5
done
RUN
chmod +x "$out/run.sh"
xvfb-run -a -s "-screen 0 1920x1200x24 +extension Composite" "$out/run.sh" "$out" "$appimage"
cp "$out/home/.local/share/lumtub/logs/lumtub.log" "$out/" 2> /dev/null || true
rm -rf "$out/home" "$out/run.sh"
ls -l "$out"
grep -i "glass" "$out/lumtub.log" 2> /dev/null | tail -n 20
python3 "$here/../../packaging/glass_measure.py" "$out"
