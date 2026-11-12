#!/usr/bin/env bash
# Builds an AppDir for appimagetool from the Flutter bundle: Lumtub with
# libmpv and the libraries libmpv needs that a desktop does not already
# have. glibc, the graphics and audio stacks, GTK and the X11 and Wayland
# libraries stay the system's, so drivers and themes match it. Libraries
# many desktops have but some lack (VA-API, VDPAU, Vulkan's loader, JACK,
# sndio, PipeWire, OpenSSL, a few X11 extensions) are carried as a
# fallback: AppRun uses the system's copy and only adds ours when it has
# none, so a newer driver still finds the libva it was built for.
#
#   make-appdir.sh <flutter bundle> <liblumtub_core.so> <AppDir>
set -euo pipefail

bundle=$1
core=$2
appdir=$3
here=$(cd "$(dirname "$0")" && pwd)

rm -rf "$appdir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" "$appdir/usr/share/icons/hicolor/256x256/apps"
cp -a "$bundle/." "$appdir/usr/bin/"
lib="$appdir/usr/bin/lib"
cp "$core" "$lib/"

# Never bundled: the system's own, or tied to its drivers and services.
system='^(ld-linux.*|libc|libm|libdl|libpthread|librt|libresolv|libutil|libnsl|libanl|libgcc_s|libstdc\+\+'\
'|libGL|libGLX|libGLdispatch|libEGL|libGLES.*|libOpenGL|libgbm|libdrm.*|libnvidia.*|libcuda'\
'|libX.*|libxcb.*|libxkbcommon.*|libwayland.*|libdecor.*'\
'|libasound|libpulse.*'\
'|libgtk-3|libgdk-3|libgdk_pixbuf.*|libglib-2\.0|libgobject-2\.0|libgio-2\.0|libgmodule-2\.0|libgthread-2\.0'\
'|libcairo.*|libpango.*|libharfbuzz.*|libfontconfig|libfreetype|libatk.*|libatspi|libepoxy'\
'|libdbus-1|libsystemd|libudev|libselinux|libmount|libblkid|libuuid|libz|libexpat|libffi|libpcre2.*)\.so'

# The system's when it has them, else ours (see AppRun).
fallback='^(libva|libva-drm|libva-x11|libva-wayland|libvdpau|libvulkan|libjack|libsndio|libpipewire-0\.3'\
'|libssl|libcrypto|libXss|libXv|libXinerama|libXpresent|libXrandr)\.so'
mkdir -p "$lib/fallback"

needed() {
  ldd "$1" | awk '/=> \//{print $3}'
}

mpv=$(ldd "$lib/libmedia_kit_video_plugin.so" | awk '/libmpv\.so/{print $3}')
if [[ -z "$mpv" ]]; then
  echo "The video plugin does not link libmpv." >&2
  exit 1
fi
count=0
spare=0
for path in "$mpv" $(needed "$mpv") $(needed "$core"); do
  name=$(basename "$path")
  if [[ "$name" =~ $fallback ]]; then
    [[ -e "$lib/fallback/$name/$name" ]] && continue
    mkdir -p "$lib/fallback/$name"
    cp -L "$path" "$lib/fallback/$name/$name"
    patchelf --set-rpath '$ORIGIN/../..' "$lib/fallback/$name/$name"
    spare=$((spare + 1))
    continue
  fi
  [[ "$name" =~ $system ]] && continue
  [[ -e "$lib/$name" ]] && continue
  cp -L "$path" "$lib/$name"
  count=$((count + 1))
done
echo "Bundled $count libraries with $(basename "$mpv"), and $spare as a fallback."

# A libwayland-client newer than the system's, when libmpv came with one
# (see AppRun).
if [[ -e "$(dirname "$mpv")/libwayland-client.so.0" ]]; then
  mkdir -p "$lib/wayland"
  cp -L "$(dirname "$mpv")/libwayland-client.so.0" "$lib/wayland/"
  echo "Carrying libwayland-client from libmpv's package for older systems."
fi

# Bundled libraries and the plugins find each other next to themselves.
# libapp.so is the compiled Dart program and is left as Flutter built it.
for file in "$lib"/*.so*; do
  [[ "$(basename "$file")" == libapp.so ]] && continue
  patchelf --set-rpath '$ORIGIN' "$file"
done

# Every library the program needs must be found: bundled or the system's.
# (libdartjni.so is Android's Java bridge, never loaded here.)
spares=$(find "$lib/fallback" -mindepth 1 -maxdepth 1 -type d | paste -sd: -)
missing=$(for file in "$appdir/usr/bin/lumtub" "$lib"/*.so* "$lib"/fallback/*/*.so*; do
  [[ -e "$file" ]] || continue
  [[ "$(basename "$file")" == libdartjni.so ]] && continue
  LD_LIBRARY_PATH="$lib${spares:+:$spares}" ldd "$file" | grep 'not found' || true
done | sort -u)
if [[ -n "$missing" ]]; then
  echo "Missing libraries:" >&2
  echo "$missing" >&2
  exit 1
fi

cp "$here/io.github.lumtub.lumtub.desktop" "$appdir/io.github.lumtub.lumtub.desktop"
cp "$here/io.github.lumtub.lumtub.desktop" "$appdir/usr/share/applications/"
cp "$here/../runner/resources/lumtub.png" "$appdir/io.github.lumtub.lumtub.png"
cp "$here/../runner/resources/lumtub.png" "$appdir/usr/share/icons/hicolor/256x256/apps/io.github.lumtub.lumtub.png"
install -m 755 "$here/AppRun" "$appdir/AppRun"
