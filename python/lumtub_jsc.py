"""yt-dlp plugin: solves YouTube's JavaScript challenges with the QuickJS
inside Lumtub's core library (native/lumtub_core/src/js.rs), in this
process, where no separate JavaScript program can run (iOS) or where
starting one costs time (Android).

It also keeps the preprocessed player that the solver gives back, which
yt-dlp's own providers do not: with it, a video after the first one of a
player takes about a tenth of the time.

Lumtub sets LUMTUB_CORE to the library's path. On Android it passes this
file's folder with --plugin-dirs; on iOS, where every yt-dlp runs in the
app's one Python, the runner imports it once (LUMTUB_JSC).
"""

from __future__ import annotations

import ctypes
import json
import os
import threading

from yt_dlp.extractor.youtube.jsc._builtin.ejs import EJSBaseJCP
from yt_dlp.extractor.youtube.jsc.provider import (
    JsChallengeProvider,
    JsChallengeProviderError,
    JsChallengeRequest,
    register_preference,
    register_provider,
)

_core = None
_core_lock = threading.Lock()
# Preprocessed players kept on disk, newest first; each is about 3 MB.
_KEEP_PLAYERS = 3


def _library():
    global _core
    with _core_lock:
        if _core is None:
            path = os.environ.get('LUMTUB_CORE')
            if not path:
                return None
            core = ctypes.CDLL(path)
            core.lumtub_js_run.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
            core.lumtub_js_run.restype = ctypes.c_void_p
            core.lumtub_string_free.argtypes = [ctypes.c_void_p]
            core.lumtub_string_free.restype = None
            _core = core
        return _core


@register_provider
class LumtubJCP(EJSBaseJCP):
    PROVIDER_NAME = 'lumtub'
    PROVIDER_VERSION = '1.0'
    BUG_REPORT_LOCATION = 'https://github.com/0x696c757a696f/lumtub/issues'
    JS_RUNTIME_NAME = 'lumtub-quickjs'
    _ENABLE_PREPROCESSED_PLAYER_CACHE = True

    def is_available(self, /) -> bool:
        try:
            return _library() is not None and self._available
        except OSError as e:
            self.logger.warning(f'Lumtub core library could not be loaded: {e}')
            return False

    def _run_js_runtime(self, stdin: str, /) -> str:
        core = _library()
        source = stdin.encode('utf-8')
        pointer = core.lumtub_js_run(source, len(source))
        if not pointer:
            raise JsChallengeProviderError('Lumtub core returned nothing')
        try:
            answer = json.loads(ctypes.string_at(pointer).decode('utf-8'))
        finally:
            core.lumtub_string_free(pointer)
        self.logger.debug(f'QuickJS took {answer.get("ms")} ms')
        if answer.get('error'):
            raise JsChallengeProviderError(f'QuickJS in Lumtub core: {answer["error"]}')
        self._prune_players()
        return answer['out']

    def _prune_players(self):
        try:
            folder = os.path.dirname(self.ie.cache._get_cache_fn(self._CACHE_SECTION, 'player', 'json'))
            players = [os.path.join(folder, n) for n in os.listdir(folder) if n.startswith('player')]
        except (OSError, AttributeError):
            return
        players.sort(key=os.path.getmtime, reverse=True)
        for old in players[_KEEP_PLAYERS:]:
            try:
                os.remove(old)
            except OSError:
                pass


@register_preference(LumtubJCP)
def preference(provider: JsChallengeProvider, requests: list[JsChallengeRequest]) -> int:
    # Ahead of the built-in runtimes (Deno 1000 is not used where this is).
    return 1100
