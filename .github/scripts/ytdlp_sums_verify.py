"""Checks yt-dlp's SHA2-256SUMS against its OpenPGP signature (SHA2-256SUMS.sig)
with the key the core pins (native/lumtub_core/keys/yt-dlp.pub, fingerprint
below), the same check the app makes before installing a yt-dlp update
(native/lumtub_core/src/ytdlp_signature.rs). Standard library only.

Usage: ytdlp_sums_verify.py SHA2-256SUMS SHA2-256SUMS.sig
"""

import hashlib
import os
import struct
import sys

FINGERPRINT = "AC0CBBE6848D6A873464AF4E57CF65933B5A7581"
KEY = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..",
    "..",
    "native",
    "lumtub_core",
    "keys",
    "yt-dlp.pub",
)
# DER prefixes of the DigestInfo for EMSA-PKCS1-v1_5 (RFC 8017, 9.2).
HASHES = {
    8: ("sha256", bytes.fromhex("3031300d060960864801650304020105000420")),
    9: ("sha384", bytes.fromhex("3041300d060960864801650304020205000430")),
    10: ("sha512", bytes.fromhex("3051300d060960864801650304020305000440")),
}


def packet(data):
    first = data[0]
    if not first & 0x80:
        raise ValueError("not an OpenPGP packet")
    if first & 0x40:
        tag, b = first & 0x3F, data[1]
        if b < 192:
            length, start = b, 2
        elif b < 224:
            length, start = ((b - 192) << 8) + data[2] + 192, 3
        elif b == 255:
            length, start = struct.unpack(">I", data[2:6])[0], 6
        else:
            raise ValueError("partial lengths are not supported")
    else:
        tag, kind = (first >> 2) & 0x0F, first & 3
        if kind == 0:
            length, start = data[1], 2
        elif kind == 1:
            length, start = struct.unpack(">H", data[1:3])[0], 3
        elif kind == 2:
            length, start = struct.unpack(">I", data[1:5])[0], 5
        else:
            raise ValueError("indeterminate lengths are not supported")
    body = data[start : start + length]
    if len(body) != length:
        raise ValueError("truncated packet")
    return tag, body, data[start + length :]


def mpi(data):
    length = (struct.unpack(">H", data[:2])[0] + 7) // 8
    if len(data) < 2 + length:
        raise ValueError("truncated number")
    return int.from_bytes(data[2 : 2 + length], "big"), data[2 + length :]


def public_key():
    with open(KEY, "rb") as f:
        tag, body, rest = packet(f.read())
    if tag != 6 or rest or body[0] != 4 or body[5] != 1:
        raise ValueError("the key file is not a v4 RSA public key")
    fingerprint = hashlib.sha1(b"\x99" + struct.pack(">H", len(body)) + body).hexdigest().upper()
    if fingerprint != FINGERPRINT:
        raise ValueError(f"the key file has fingerprint {fingerprint}")
    n, rest = mpi(body[6:])
    e, rest = mpi(rest)
    if rest:
        raise ValueError("the key file has extra data")
    return n, e


def verify(sums, signature):
    tag, body, rest = packet(signature)
    if tag != 2 or rest:
        raise ValueError("the signature file holds no single signature")
    version, kind, algorithm, hash_id = body[0], body[1], body[2], body[3]
    if version != 4 or kind != 0 or algorithm != 1 or hash_id not in HASHES:
        raise ValueError("not a v4 RSA signature over a binary document")
    hashed_end = 6 + struct.unpack(">H", body[4:6])[0]
    unhashed_end = hashed_end + 2 + struct.unpack(">H", body[hashed_end : hashed_end + 2])[0]
    value, rest = mpi(body[unhashed_end + 2 :])
    if rest:
        raise ValueError("the signature has extra data")
    name, prefix = HASHES[hash_id]
    signed = body[:hashed_end]
    digest = hashlib.new(
        name, sums + signed + b"\x04\xff" + struct.pack(">I", len(signed))
    ).digest()
    n, e = public_key()
    size = (n.bit_length() + 7) // 8
    if value >= n:
        raise ValueError("the signature value is out of range")
    encoded = pow(value, e, n).to_bytes(size, "big")
    expected = (
        b"\x00\x01" + b"\xff" * (size - 3 - len(prefix) - len(digest)) + b"\x00" + prefix + digest
    )
    if encoded != expected:
        raise ValueError("the signature does not match")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1], "rb") as f:
        sums = f.read()
    with open(sys.argv[2], "rb") as f:
        signature = f.read()
    try:
        verify(sums, signature)
    except (ValueError, IndexError, struct.error) as e:
        sys.exit(f"yt-dlp checksums: {e}")
    print("yt-dlp checksums: good signature from", FINGERPRINT)


if __name__ == "__main__":
    main()
