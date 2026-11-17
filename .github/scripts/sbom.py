#!/usr/bin/env python3
"""Writes a CycloneDX 1.6 SBOM of a Lumtub release: the Rust crates in the
core's Cargo.lock, the Dart packages in pubspec.lock, the Flutter SDK and
the libmpv build the Linux packages carry. yt-dlp, Deno and FFmpeg are not
in it: the app downloads them on first use, verified by checksum.

Usage: sbom.py <version> <output.json>
"""

import datetime
import json
import re
import sys
import tomllib
import uuid


def cargo(path):
    with open(path, "rb") as file:
        packages = tomllib.load(file).get("package", [])
    for package in packages:
        if not package.get("source", "").startswith("registry+"):
            continue
        name, version = package["name"], package["version"]
        component = {
            "type": "library",
            "name": name,
            "version": version,
            "purl": f"pkg:cargo/{name}@{version}",
        }
        if checksum := package.get("checksum"):
            component["hashes"] = [{"alg": "SHA-256", "content": checksum}]
        yield component


def pub(path):
    name = source = version = digest = None
    entries = []

    def flush():
        if name and source == "hosted" and version:
            component = {"type": "library", "name": name, "version": version, "purl": f"pkg:pub/{name}@{version}"}
            if digest:
                component["hashes"] = [{"alg": "SHA-256", "content": digest}]
            entries.append(component)

    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if m := re.match(r"^  ([A-Za-z0-9_]+):$", line):
            flush()
            name, source, version, digest = m.group(1), None, None, None
        elif m := re.match(r"^    source: (\w+)$", line):
            source = m.group(1)
        elif m := re.match(r'^    version: "([^"]+)"$', line):
            version = m.group(1)
        elif m := re.match(r"^      sha256: ([0-9a-f]{64})$", line):
            digest = m.group(1)
        elif line and not line.startswith(" "):
            flush()
            name = None
    flush()
    return entries


def pins(path):
    values = {}
    for line in open(path, encoding="utf-8"):
        if "=" in line and not line.startswith("#"):
            key, value = line.strip().split("=", 1)
            values[key] = value
    return values


def main(version, output):
    flutter = open(".flutter-version", encoding="utf-8").read().strip()
    pinned = pins(".github/pins.env")
    components = [
        {
            "type": "framework",
            "name": "flutter",
            "version": flutter,
            "purl": f"pkg:github/flutter/flutter@{flutter}",
        }
    ]
    if mpv := pinned.get("MPV_RELEASE"):
        components.append(
            {
                "type": "library",
                "name": "libmpv",
                "version": mpv,
                "description": "libmpv with FFmpeg and libplacebo inside, in the Linux packages",
                "purl": f"pkg:github/0x696c757a696f/lumtub-media-builds@{mpv}",
                "hashes": [
                    {"alg": "SHA-256", "content": pinned[key]}
                    for key in ("MPV_SHA256_X86_64", "MPV_SHA256_X86_64_V3", "MPV_SHA256_AARCH64")
                    if key in pinned
                ],
            }
        )
    components += list(cargo("native/lumtub_core/Cargo.lock"))
    components += pub("pubspec.lock")
    bom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": f"urn:uuid:{uuid.uuid4()}",
        "version": 1,
        "metadata": {
            "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "component": {
                "type": "application",
                "name": "Lumtub",
                "version": version,
                "licenses": [{"license": {"id": "GPL-3.0-or-later"}}],
                "purl": f"pkg:github/0x696c757a696f/lumtub@v{version}",
            },
        },
        "components": components,
    }
    with open(output, "w", encoding="utf-8") as file:
        json.dump(bom, file, indent=1)
        file.write("\n")
    print(f"{output}: {len(components)} components")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
