#!/usr/bin/env bash
# Signs an APK with the release key (APK Signature Scheme v2/v3, for every
# Android version) plus a v3.2 hybrid pair (classical EC + ML-DSA-65, verified
# from Android 17 on). Needs apksigner from build-tools 37 or newer, run on a
# JDK that knows ML-DSA (24 or newer).
#
#   sign-hybrid.sh <apksigner> <in.apk> <out.apk> <release.jks> <keys folder>
# The keystore password comes from $KEYSTORE_PASSWORD; the keys folder holds
# hybrid-classical.pk8/.x509.der and hybrid-pqc.pk8/.x509.der.
set -euo pipefail
apksigner=$1 in=$2 out=$3 ks=$4 keys=$5
work=$(mktemp -d)
# The hybrid signers carry the release key's history, so an update signed
# with them installs over one signed with the release key alone.
"$apksigner" rotate --out "$work/lineage" \
  --old-signer --ks "$ks" --ks-key-alias lumtub --ks-pass env:KEYSTORE_PASSWORD --set-rollback true \
  --new-signer --key "$keys/hybrid-classical.pk8" --cert "$keys/hybrid-classical.x509.der"
"$apksigner" sign --min-sdk-version 24 --v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled true \
  --ks "$ks" --ks-key-alias lumtub --ks-pass env:KEYSTORE_PASSWORD \
  --next-signer --key "$keys/hybrid-classical.pk8" --cert "$keys/hybrid-classical.x509.der" \
    --hybrid-signer-role classical --signer-lineage "$work/lineage" \
  --next-signer --key "$keys/hybrid-pqc.pk8" --cert "$keys/hybrid-pqc.x509.der" \
    --hybrid-signer-role pqc --signer-lineage "$work/lineage" \
  --out "$out" "$in"
rm -rf "$work"
"$apksigner" verify -v --min-sdk-version 24 "$out" | grep -E 'Verified using|Number of signers|WARNING|ERROR' || true
