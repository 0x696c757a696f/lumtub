#!/usr/bin/env bash
# Installs the x86_64 APK on a running emulator, starts it and checks that
# Lumtub opens and stays up; leaves a screenshot and the log in $1.
set -uo pipefail
apk="$1"; out="$2"
mkdir -p "$out"
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 2; done
adb shell settings put global window_animation_scale 0
adb install -r "$apk" || exit 1
adb logcat -c
adb shell am start -W -n io.github.lumtub.lumtub/.MainActivity
sleep 45
adb exec-out screencap -p > "$out/home.png"
adb logcat -d > "$out/logcat.txt"
pid=$(adb shell pidof io.github.lumtub.lumtub | tr -d '\r')
grep -E 'flutter|Lumtub|AndroidRuntime|DEBUG' "$out/logcat.txt" | tail -80
if [ -z "$pid" ]; then echo "::error::Lumtub is not running 45 s after start"; exit 1; fi
if grep -q 'FATAL EXCEPTION\|Fatal signal' "$out/logcat.txt"; then echo "::error::Lumtub crashed"; exit 1; fi
echo "Lumtub is running (pid $pid)"
