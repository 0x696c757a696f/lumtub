#!/usr/bin/env bash
# Usage: .github/scripts/latest-names.sh <folder>
#
# Copies each package Lumtub_<version>_<package>.<ext> in <folder> to
# Lumtub-<package>.<ext>, a name that stays the same from release to
# release, so the README can link releases/latest/download/<that name>.
# The hyphen keeps these copies out of the updater, the website and the
# package manifests, which all look for "_<package>.<ext>".
set -euo pipefail
shopt -s nullglob
folder="${1:?folder}"
for f in "$folder"/Lumtub_*_*{-setup.exe,.zip,.AppImage,.flatpak,.dmg,.apk,.ipa,.tipa}; do
  name="${f##*/}"
  rest="${name#Lumtub_}"
  package="${rest#*_}"
  [[ "$package" != "$rest" && "$package" != *_* ]] || continue
  cp -- "$f" "$folder/Lumtub-$package"
  echo "$name -> Lumtub-$package"
done
