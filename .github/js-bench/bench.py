"""Times yt-dlp's JS challenge solver (yt-dlp-ejs) on today's YouTube player
with several JavaScript engines.

    python bench.py <work folder> <name>=<command with {} for the script> ...
"""
import json
import random
import re
import string
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import yt_dlp_ejs.yt.solver as solver

work = Path(sys.argv[1])
work.mkdir(parents=True, exist_ok=True)
runtimes = dict(arg.split("=", 1) for arg in sys.argv[2:])


def get(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=30) as reply:
        return reply.read().decode()


api = get("https://www.youtube.com/iframe_api")
player_id = re.search(r"player\\?/([0-9a-fA-F]{8})\\?/", api)[1]
player = get(f"https://www.youtube.com/s/player/{player_id}/player_ias.vflset/en_US/base.js")
print(f"Player {player_id}: {len(player) // 1024} KiB")

rng = random.Random(1)
alphabet = string.ascii_letters + string.digits + "-_"
requests = [
    {"type": "n", "challenges": ["".join(rng.choice(alphabet) for _ in range(16)) for _ in range(3)]},
    {"type": "sig", "challenges": ["".join(rng.choice(alphabet) for _ in range(108)) for _ in range(3)]},
]


def script(data):
    return f"""{solver.lib()}
Object.assign(globalThis, lib);
{solver.core()}
console.log(JSON.stringify(jsc({json.dumps(data)})));
"""


cold = work / "cold.js"
cold.write_text(script({"type": "player", "player": player, "requests": requests, "output_preprocessed": True}))


def run(command, path):
    start = time.perf_counter()
    done = subprocess.run(command.replace("{}", str(path)), shell=True, capture_output=True, text=True)
    took = time.perf_counter() - start
    if done.returncode:
        return took, None, done.stderr.strip()[-400:]
    return took, done.stdout, None


warm = None
results = {}
for name, command in runtimes.items():
    for kind in ("cold", "warm"):
        if kind == "warm" and warm is None:
            continue
        times, answer, error = [], None, None
        for _ in range(3):
            took, out, error = run(command, cold if kind == "cold" else warm)
            if out is None:
                break
            times.append(took)
            answer = json.loads(out.strip().splitlines()[-1])
        if error:
            print(f"{name} {kind}: failed: {error}")
            continue
        if kind == "cold" and warm is None and answer.get("preprocessed_player"):
            warm = work / "warm.js"
            warm.write_text(script({"type": "preprocessed", "preprocessed_player": answer["preprocessed_player"], "requests": requests}))
        solved = [r.get("type") for r in answer.get("responses", [])]
        results[f"{name} {kind}"] = (min(times), sum(times) / len(times), solved)
        print(f"{name:10} {kind}: best {min(times):6.2f} s, mean {sum(times) / len(times):6.2f} s, responses {solved}")
    # Warm runs need the preprocessed player, made by the first runtime.
    if warm is not None and f"{name} warm" not in results:
        for _ in [0]:
            times = [run(command, warm)[0] for _ in range(3)]
            print(f"{name:10} warm: best {min(times):6.2f} s, mean {sum(times) / len(times):6.2f} s")

summary = ["| Runtime | Best (s) | Mean (s) |", "| --- | --- | --- |"]
summary += [f"| {k} | {v[0]:.2f} | {v[1]:.2f} |" for k, v in results.items()]
print("\n".join(summary))
(work / "summary.md").write_text(f"Player `{player_id}`\n\n" + "\n".join(summary) + "\n")
