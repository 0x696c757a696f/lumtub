#!/usr/bin/env bash
# Installs the x86_64 APK on a running emulator, starts it and checks that
# Lumtub opens and stays up; leaves a screenshot and the log in $1.
set -uo pipefail
apk="$1"; out="$2"
mkdir -p "$out"
timeout 240 adb wait-for-device || { echo "::error::The emulator did not come up"; exit 1; }
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

# Pictures and a short video for people to look at: a phone, a tablet and a
# TV sized screen. Nothing here decides whether the test passed.
shot() { adb exec-out screencap -p > "$out/$1.png"; }
# The first run asks about block lists; Back closes that dialog.
adb shell input keyevent KEYCODE_BACK; sleep 3; shot home-ready
adb shell screenrecord --time-limit 30 --bit-rate 6000000 /sdcard/phone.mp4 &
rec=$!
sleep 2
adb shell input swipe 540 1700 540 900 400; sleep 4; shot phone-scrolled
adb shell input swipe 540 900 540 1700 400; sleep 4
adb shell input swipe 540 1700 540 500 300; sleep 5; shot phone-more
adb shell input swipe 540 500 540 1700 300; sleep 4
wait "$rec" 2> /dev/null
adb pull /sdcard/phone.mp4 "$out/phone.mp4" > /dev/null 2>&1

adb shell settings put system accelerometer_rotation 0
for form in "tablet 2560x1600 320" "tv 1920x1080 240"; do
  set -- $form
  adb shell wm size "$2"; adb shell wm density "$3"; sleep 12
  shot "$1-home"
  adb shell input keyevent KEYCODE_DPAD_DOWN; sleep 1
  adb shell input keyevent KEYCODE_DPAD_RIGHT; sleep 2; shot "$1-focus"
done
adb shell screenrecord --time-limit 25 --bit-rate 6000000 /sdcard/tv.mp4 &
rec=$!
sleep 2
for key in DOWN DOWN RIGHT RIGHT RIGHT DOWN LEFT; do adb shell input keyevent "KEYCODE_DPAD_$key"; sleep 2; done
sleep 4
wait "$rec" 2> /dev/null
adb pull /sdcard/tv.mp4 "$out/tv.mp4" > /dev/null 2>&1
adb shell wm size reset; adb shell wm density reset
ls -l "$out"
