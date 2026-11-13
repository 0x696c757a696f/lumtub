"""Solves today's player's challenges with Lumtub's provider and with
yt-dlp's Deno provider, through yt-dlp's provider interface, and fails when
the answers differ. Works where YouTube asks CI to sign in: only the player
file is downloaded.

    python challenge_check.py <cache folder> <lumtub_jsc.py>
"""
import importlib.util
import random
import re
import string
import sys
import time
import urllib.request

from yt_dlp import YoutubeDL
from yt_dlp.extractor.youtube.jsc._builtin.deno import DenoJCP
from yt_dlp.extractor.youtube.jsc.provider import (
    JsChallengeRequest,
    JsChallengeType,
    NChallengeInput,
    SigChallengeInput,
)

spec = importlib.util.spec_from_file_location("lumtub_jsc", sys.argv[2])
lumtub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lumtub)


class Log:
    def trace(self, message):
        pass

    def debug(self, message, *, once=False):
        if "took" in message or "player" in message.lower():
            print(f"  debug: {message}")

    def info(self, message, *, once=False):
        print(f"  info: {message}")

    def warning(self, message, *, once=False):
        print(f"  warning: {message}")

    def error(self, message, cause=None):
        print(f"  error: {message}")


request = urllib.request.Request("https://www.youtube.com/iframe_api", headers={"User-Agent": "Mozilla/5.0"})
with urllib.request.urlopen(request, timeout=30) as reply:
    player_id = re.search(r"player\\?/([0-9a-fA-F]{8})\\?/", reply.read().decode())[1]
player = f"https://www.youtube.com/s/player/{player_id}/player_ias.vflset/en_US/base.js"
print(f"Player {player_id}")

rng = random.Random(7)
alphabet = string.ascii_letters + string.digits + "-_"


def challenges(length):
    return ["".join(rng.choice(alphabet) for _ in range(length)) for _ in range(3)]


requests = [
    JsChallengeRequest(JsChallengeType.N, NChallengeInput(player, challenges(16)), "check"),
    JsChallengeRequest(JsChallengeType.SIG, SigChallengeInput(player, challenges(108)), "check"),
]

answers = {}
for name, provider_class, cache in (
    ("deno", DenoJCP, f"{sys.argv[1]}/deno"),
    ("lumtub", lumtub.LumtubJCP, f"{sys.argv[1]}/lumtub"),
):
    ydl = YoutubeDL({"cachedir": cache, "quiet": True, "js_runtimes": {"deno": {}}})
    provider = provider_class(ydl.get_info_extractor("Youtube"), Log(), {})
    if not provider.is_available():
        sys.exit(f"{name} is not available")
    for attempt in ("first", "second"):
        start = time.perf_counter()
        got = {}
        for response in provider.bulk_solve(requests):
            if response.error:
                sys.exit(f"{name} {attempt}: {response.request.type.value} failed: {response.error}")
            got[response.request.type.value] = response.response.output.results
        print(f"{name:7} {attempt}: {time.perf_counter() - start:.2f} s")
        answers.setdefault(name, got)
        if got != answers[name]:
            sys.exit(f"{name} answered differently the second time")

for kind in ("n", "sig"):
    for challenge, expected in answers["deno"][kind].items():
        actual = answers["lumtub"][kind].get(challenge)
        print(f"{kind:3} {challenge[:16]}… deno {expected[:16]}… lumtub {str(actual)[:16]}…")
if answers["deno"] != answers["lumtub"]:
    sys.exit("Lumtub's answers differ from Deno's")
print("Lumtub's provider gives Deno's answers.")
