#!/usr/bin/env python3
"""Which packages a change needs built, from the paths it touches.

Reads changed paths, one per line, on standard input and prints a JSON
list of platforms (windows, linux, macos, ios, android) for build.yml.

- A platform's own folder (windows/, ios/ ...) or a vendored package's
  platform folder (vendor/media_kit_video/ios/, vendor/media_kit_libs_ios_video/)
  builds that platform alone; vendor/**/darwin/ builds macOS and iOS.
- Text that no package carries (release notes, Markdown, docs, the website,
  other workflows and scripts) builds nothing.
- Everything else (lib/, native/, assets, pubspec, build.yml ...) is shared
  and builds every platform.
"""

import json
import sys

PLATFORMS = ["windows", "linux", "macos", "ios", "android"]

# Paths that end up in no package.
NOTHING_PREFIXES = (
    "release-notes/",
    "docs/",
    "website/",
    "packaging/",
    ".github/ISSUE_TEMPLATE/",
    ".github/scripts/",
)
NOTHING_FILES = {
    "LICENSE",
    "NOTICE",
    "PROJECT_NOTES.txt",
    ".github/dependabot.yml",
}


def platforms_of(path):
    """The platforms one path needs built."""
    if path.endswith(".md") or path in NOTHING_FILES or path.startswith(NOTHING_PREFIXES):
        return set()
    if path.startswith(".github/workflows/"):
        return set(PLATFORMS) if path == ".github/workflows/build.yml" else set()
    parts = path.split("/")
    if parts[0] in PLATFORMS:
        return {parts[0]}
    if parts[0] == "vendor" and len(parts) > 2:
        found = set()
        for part in parts[1:-1]:
            if part in PLATFORMS:
                found.add(part)
            elif part == "darwin":
                found |= {"macos", "ios"}
            else:
                # media_kit_libs_ios_video and the like.
                found |= {p for p in PLATFORMS if f"_{p}_" in f"_{part}_"}
        if found:
            return found
    return set(PLATFORMS)


def main():
    wanted = set()
    for line in sys.stdin:
        path = line.strip()
        if path:
            wanted |= platforms_of(path)
    print(json.dumps([p for p in PLATFORMS if p in wanted]))


if __name__ == "__main__":
    main()
