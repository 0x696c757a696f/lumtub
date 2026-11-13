"""Writes the AltStore / SideStore source for a release: add
https://github.com/0x696c757a696f/lumtub/releases/latest/download/altstore-source.json
in SideStore or AltStore (Sources › +) and it offers each new Lumtub.

    altstore-source.py <ipa> <tag> <notes file or ''> <out>
"""

import datetime
import json
import os
import re
import sys

ipa, tag, notes, out = sys.argv[1:5]
repo = os.environ.get("GITHUB_REPOSITORY", "0x696c757a696f/lumtub")
with open("pubspec.yaml", encoding="utf-8") as f:
    name, build = re.search(r"^version: *([\d.]+)\+(\d+)", f.read(), re.M).groups()
description = ""
if notes and os.path.exists(notes):
    with open(notes, encoding="utf-8") as f:
        description = f.read().strip()
icon = f"https://raw.githubusercontent.com/{repo}/main/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
source = {
    "name": "Lumtub",
    "identifier": "io.github.lumtub.source",
    "subtitle": "A YouTube player without ads or tracking.",
    "website": f"https://github.com/{repo}",
    "iconURL": icon,
    "tintColor": "#55D4BA",
    "apps": [{
        "name": "Lumtub",
        "bundleIdentifier": "io.github.lumtub.lumtub",
        "developerName": "Lumtub",
        "subtitle": "A YouTube player without ads or tracking.",
        "localizedDescription": "Watch YouTube without ads or tracking: subscriptions without an account, downloads, bullet chat, casting and more.",
        "iconURL": icon,
        "tintColor": "#55D4BA",
        "category": "entertainment",
        "versions": [{
            "version": name,
            "buildVersion": build,
            "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "localizedDescription": description or f"Lumtub {name}",
            "downloadURL": f"https://github.com/{repo}/releases/download/{tag}/{os.path.basename(ipa)}",
            "size": os.path.getsize(ipa),
            "minOSVersion": "15.0",
        }],
        "appPermissions": {
            "entitlements": [],
            "privacy": {
                "NSLocalNetworkUsageDescription": "Lumtub looks for TVs and speakers on your network to cast videos to.",
            },
        },
    }],
    "news": [],
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
print(json.dumps(source["apps"][0]["versions"][0], indent=2))
