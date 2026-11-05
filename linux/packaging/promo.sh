#!/usr/bin/env bash
# Cuts the recorded tour (tour.mp4 and scenes.txt from showcase.sh) into a
# short promo video with captions, in English and Chinese, and a GIF of the
# palettes and languages for the README.
#
#   promo.sh <showcase output folder>
set -euo pipefail

out=$(cd "$1" && pwd)
tour="$out/tour.mp4"
work=$(mktemp -d)
latin=$(fc-match -f '%{file}' 'Noto Sans:bold')
cjk=$(fc-match -f '%{file}' 'Noto Sans CJK SC:bold')
# Recording starts about a second before the app's clock.
lead=1.0

start_of() { awk -v s="$1" -v lead="$lead" '$1 == s { printf "%.2f", $2 / 1000 + lead }' "$out/scenes.txt"; }

# scene, longest it may run (seconds), English caption, Chinese caption
cat > "$work/plan.txt" <<'PLAN'
home|5|A For you feed worked out on your own PC|“为你推荐”在你自己的电脑上算出来
explore|4.5|Explore by category, region and the language people speak|按分区、地区和视频里真正说的语言来发现
watch|6|mpv with hardware decoding: smooth 4K, no browser inside|mpv 硬件解码：4K 流畅，不靠浏览器
palettes|14|Calm palettes with character, light and dark|克制又各有性格的配色，浅色深色都有
languages|20|72 interface languages, right to left included|72 种界面语言，从右到左的也排得好
PLAN

build() {
  local lang=$1 font=$2 result=$3
  local inputs=() filters="" labels="" n=0 count=0
  card() {
    local title=$1 line=$2 more=$3 duration=$4
    printf '%s' "$title" > "$work/card$n-a.txt"
    printf '%s' "$line" > "$work/card$n-b.txt"
    printf '%s' "$more" > "$work/card$n-c.txt"
    inputs+=(-f lavfi -t "$duration" -i "color=c=0x111114:s=1280x720:r=30")
    local index=$count
    count=$((count + 1))
    filters+="[$index:v]drawtext=fontfile='$font':textfile='$work/card$n-a.txt':fontcolor=white:fontsize=88:x=(w-tw)/2:y=(h/2)-110,"
    filters+="drawtext=fontfile='$font':textfile='$work/card$n-b.txt':fontcolor=0xD8D8E0:fontsize=36:x=(w-tw)/2:y=(h/2)+30,"
    filters+="drawtext=fontfile='$font':textfile='$work/card$n-c.txt':fontcolor=0x9A9AA6:fontsize=30:x=(w-tw)/2:y=(h/2)+96,"
    filters+="fade=in:st=0:d=0.5,fade=out:st=$(echo "$duration - 0.5" | bc):d=0.5,format=yuv420p[v$n];"
    labels+="[v$n]"
    n=$((n + 1))
  }
  if [ "$lang" = en ]; then
    card "Lumtub" "The YouTube app your desktop deserves" " " 3
  else
    card "Lumtub" "桌面上本该有的 YouTube 客户端" " " 3
  fi
  inputs+=(-i "$tour")
  local tour_index=$count
  count=$((count + 1))
  while IFS='|' read -r scene longest english chinese; do
    local from next to
    from=$(start_of "$scene")
    [ -n "$from" ] || continue
    next=$(awk -v s="$scene" -v lead="$lead" 'f { printf "%.2f", $2 / 1000 + lead; exit } $1 == s { f = 1 }' "$out/scenes.txt")
    to=$(echo "if ($next - $from > $longest) $from + $longest else $next" | bc)
    local duration
    duration=$(echo "$to - $from" | bc)
    if [ "$lang" = en ]; then printf '%s' "$english" > "$work/$scene.txt"; else printf '%s' "$chinese" > "$work/$scene.txt"; fi
    filters+="[$tour_index:v]trim=start=$from:end=$to,setpts=PTS-STARTPTS,fps=30,scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=0x111114,"
    filters+="drawbox=y=ih-104:h=104:w=iw:color=black@0.62:t=fill,"
    filters+="drawtext=fontfile='$font':textfile='$work/$scene.txt':fontcolor=white:fontsize=36:x=(w-tw)/2:y=h-70,"
    filters+="fade=in:st=0:d=0.35,fade=out:st=$(echo "$duration - 0.35" | bc):d=0.35,format=yuv420p,setsar=1[v$n];"
    labels+="[v$n]"
    n=$((n + 1))
  done < "$work/plan.txt"
  if [ "$lang" = en ]; then
    card "Free. Open source. No ads." "Windows · Linux · macOS" "github.com/0x696c757a696f/lumtub" 4.5
  else
    card "免费 · 开源 · 无广告" "Windows · Linux · macOS" "github.com/0x696c757a696f/lumtub" 4.5
  fi
  filters+="${labels}concat=n=$n:v=1:a=0[out]"
  ffmpeg -hide_banner -loglevel error -y "${inputs[@]}" -filter_complex "$filters" -map '[out]' \
    -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart "$result"
}

build en "$latin" "$out/promo-en.mp4"
build zh "$cjk" "$out/promo-zh.mp4"

# The palettes and languages, as a small GIF.
from=$(start_of palettes)
if [ -n "$from" ]; then
  ffmpeg -hide_banner -loglevel error -y -ss "$from" -t 12 -i "$tour" \
    -vf "fps=10,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" "$out/tour.gif"
fi
rm -rf "$work"
ls -l "$out"/promo-*.mp4 "$out"/tour.gif
