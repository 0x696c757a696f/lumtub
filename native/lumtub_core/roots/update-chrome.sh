#!/bin/sh
# Writes chrome.pem from the Chrome Root Store: the certificates Chrome
# trusts for TLS, each after its SHA-256 as in Chromium's root_store.certs.
set -eu
url=https://raw.githubusercontent.com/chromium/chromium/main/net/data/ssl/chrome_root_store/root_store.certs
here=$(dirname "$0")
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -sSfL "$url" -o "$tmp"
{
  echo "# Chrome Root Store, from $url"
  echo
  awk '/^# [0-9a-f]+$/ && length($2) == 64 { print; next }
       /-----BEGIN CERTIFICATE-----/ { keep = 1 }
       keep { print }
       /-----END CERTIFICATE-----/ { keep = 0; print "" }' "$tmp"
} > "$tmp.pem"
count=$(grep -c 'BEGIN CERTIFICATE' "$tmp.pem")
if [ "$count" -lt 50 ]; then
  echo "Only $count certificates in the Chrome Root Store; keeping the old list." >&2
  rm -f "$tmp.pem"
  exit 1
fi
mv "$tmp.pem" "$here/chrome.pem"
echo "Chrome Root Store: $count certificates"
