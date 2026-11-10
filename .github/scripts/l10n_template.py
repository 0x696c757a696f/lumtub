"""Writes an English template for a new translation: every key of
assets/l10n/zh-Hans.json with the key itself as its value, in the same order.

Usage: l10n_template.py OUT_FILE      (for example assets/l10n/de.json)
"""

import json
import os
import sys


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    with open(os.path.join(root, "assets", "l10n", "zh-Hans.json"), encoding="utf-8") as f:
        keys = json.load(f)
    with open(sys.argv[1], "w", encoding="utf-8", newline="\n") as f:
        json.dump({key: key for key in keys}, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"Wrote {len(keys)} strings to {sys.argv[1]}")


if __name__ == "__main__":
    main()
