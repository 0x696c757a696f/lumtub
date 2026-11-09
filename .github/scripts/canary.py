"""Plays a few videos the way Lumtub does; see .github/workflows/canary.yml.

canary.py CHECKER TOOLS ID...: CHECKER is lumtub-canary, TOOLS the folder
holding yt-dlp and deno. Exits 1 when anything is broken; being turned away
by YouTube's bot check only warns.
"""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

BLOCKED_WORDS = ("not a bot", "sign in to confirm", "http error 429", "too many requests")


def quick(checker, video):
    body = subprocess.run([checker, "body", video], check=True, capture_output=True, text=True).stdout
    headers = {"Content-Type": "application/json"}
    for line in subprocess.run([checker, "headers"], check=True, capture_output=True, text=True).stdout.splitlines():
        name, _, value = line.partition(": ")
        headers[name] = value
    request = urllib.request.Request(
        "https://www.youtube.com/youtubei/v1/player?prettyPrint=false", data=body.encode(), headers=headers, method="POST"
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            answer = response.read()
    except urllib.error.HTTPError as e:
        return ("blocked" if e.code == 429 else "broken"), f"/player answered HTTP {e.code}"
    except OSError as e:
        return "blocked", f"no answer: {e}"
    path = os.path.join(os.environ.get("RUNNER_TEMP", "."), f"player-{video}.json")
    with open(path, "wb") as f:
        f.write(answer)
    result = subprocess.run([checker, "check", path], capture_output=True, text=True)
    line = result.stdout.strip()
    state = {0: "ok", 2: "blocked"}.get(result.returncode, "broken")
    return state, line.partition(": ")[2] or line


def ytdlp(tools, video):
    yt = os.path.join(tools, "yt-dlp")
    deno = os.path.join(tools, "deno")
    result = subprocess.run(
        [yt, "-J", "--no-warnings", "--no-playlist", "--js-runtimes", f"deno:{deno}", "--", video],
        capture_output=True,
        text=True,
        timeout=300,
    )
    if result.returncode != 0:
        error = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else f"exit {result.returncode}"
        return ("blocked" if any(w in error.lower() for w in BLOCKED_WORDS) else "broken"), error
    info = json.loads(result.stdout)
    formats = [f for f in info.get("formats", []) if f.get("url")]
    video_formats = [f for f in formats if f.get("vcodec") not in (None, "none")]
    audio_formats = [f for f in formats if f.get("acodec") not in (None, "none") and f.get("vcodec") == "none"]
    if not video_formats or not audio_formats:
        return "broken", f"{len(video_formats)} video and {len(audio_formats)} audio formats with addresses"
    tallest = max(f.get("height") or 0 for f in video_formats)
    return "ok", f"{len(formats)} formats, up to {tallest}p"


def main():
    checker, tools, videos = sys.argv[1], sys.argv[2], sys.argv[3:]
    rows = []
    for video in videos:
        for way, check in (("quick start", lambda: quick(checker, video)), ("yt-dlp", lambda: ytdlp(tools, video))):
            try:
                state, note = check()
            except Exception as e:  # a crash in the check is a broken check
                state, note = "broken", f"{type(e).__name__}: {e}"
            rows.append((video, way, state, note))
            print(f"{video} {way}: {state}: {note}", flush=True)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("| Video | Way | Result | Detail |\n|---|---|---|---|\n")
            for video, way, state, note in rows:
                f.write(f"| {video} | {way} | {state} | {note.replace('|', '/')} |\n")
    broken = [r for r in rows if r[2] == "broken"]
    blocked = [r for r in rows if r[2] == "blocked"]
    for video, way, _, note in blocked:
        print(f"::warning::{video} {way}: YouTube turned this machine away ({note}); nothing learnt.")
    for video, way, _, note in broken:
        print(f"::error::{video} {way}: {note}")
    sys.exit(1 if broken else 0)


main()
