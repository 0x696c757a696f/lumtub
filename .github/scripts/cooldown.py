#!/usr/bin/env python3
"""Holds back packages released less than a week ago from a lockfile refresh.

Run after `flutter pub upgrade` and `cargo update`, before committing. Each
package whose version changed is looked up on crates.io or pub.dev; a
version younger than COOLDOWN_DAYS goes back to the version main had
(`cargo update --precise`). When that is not possible, as for a package
that is new to the lockfile or for pubspec.lock, which has no per-package
downgrade, the whole lockfile stays as it was and the next run tries again.
A poisoned release is usually found and pulled within days; this keeps it
out of main for that long, as Dependabot's cooldown does for direct
dependencies.
"""

import datetime
import json
import os
import re
import subprocess
import sys
import tomllib
import urllib.parse
import urllib.request

COOLDOWN_DAYS = int(os.environ.get("COOLDOWN_DAYS", "7"))
CARGO_MANIFEST = "native/lumtub_core/Cargo.toml"
CARGO_LOCK = "native/lumtub_core/Cargo.lock"
PUB_LOCK = "pubspec.lock"
AGENT = "lumtub-lockfile-cooldown (github.com/0x696c757a696f/lumtub)"


def at_head(path):
    result = subprocess.run(
        ["git", "show", f"HEAD:{path}"], capture_output=True, text=True, check=False
    )
    return result.stdout if result.returncode == 0 else ""


def cargo_versions(text):
    if not text:
        return {}
    packages = tomllib.loads(text).get("package", [])
    found = {}
    for package in packages:
        if package.get("source", "").startswith("registry+"):
            found.setdefault(package["name"], set()).add(package["version"])
    return found


def pub_versions(text):
    found = {}
    name = None
    hosted = False
    for line in text.splitlines():
        if m := re.match(r"^  ([A-Za-z0-9_]+):$", line):
            name, hosted = m.group(1), False
        elif name and re.match(r"^    source: hosted$", line):
            hosted = True
        elif name and (m := re.match(r'^    version: "([^"]+)"$', line)) and hosted:
            found.setdefault(name, set()).add(m.group(1))
    return found


def fetch(url):
    request = urllib.request.Request(
        url, headers={"User-Agent": AGENT, "Accept": "application/json"}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def published(kind, name, version):
    quoted = urllib.parse.quote(name), urllib.parse.quote(version)
    if kind == "cargo":
        stamp = fetch("https://crates.io/api/v1/crates/{}/{}".format(*quoted))["version"][
            "created_at"
        ]
    else:
        stamp = fetch("https://pub.dev/api/packages/{}/versions/{}".format(*quoted))["published"]
    return datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00"))


def too_young(kind, before, after):
    """(name, new version, old versions) of each changed package that is
    younger than the cooldown; unknown ages count as young."""
    limit = datetime.datetime.now(datetime.UTC) - datetime.timedelta(days=COOLDOWN_DAYS)
    young = []
    for name, versions in sorted(after.items()):
        old = before.get(name, set())
        for version in sorted(versions - old):
            try:
                when = published(kind, name, version)
            except Exception as error:
                print(f"{kind} {name} {version}: release time unknown ({error}); held back")
                young.append((name, version, old))
                continue
            if when > limit:
                print(f"{kind} {name} {version}: released {when:%Y-%m-%d}, held back")
                young.append((name, version, old))
    return young


def restore(path):
    subprocess.run(["git", "checkout", "HEAD", "--", path], check=True)
    print(f"{path} stays as main has it.")


def read(path):
    with open(path) as f:
        return f.read()


def cargo():
    before = cargo_versions(at_head(CARGO_LOCK))
    young = too_young("cargo", before, cargo_versions(read(CARGO_LOCK)))
    for name, version, old in young:
        if len(old) != 1:
            restore(CARGO_LOCK)
            return
        (back,) = old
        step = subprocess.run(
            [
                "cargo",
                "update",
                "--manifest-path",
                CARGO_MANIFEST,
                "-p",
                f"{name}@{version}",
                "--precise",
                back,
            ],
            check=False,
        )
        if step.returncode != 0:
            restore(CARGO_LOCK)
            return
    if young and too_young("cargo", before, cargo_versions(read(CARGO_LOCK))):
        restore(CARGO_LOCK)


def pub():
    before = pub_versions(at_head(PUB_LOCK))
    if too_young("pub", before, pub_versions(read(PUB_LOCK))):
        restore(PUB_LOCK)


if __name__ == "__main__":
    pub()
    cargo()
    sys.exit(0)
