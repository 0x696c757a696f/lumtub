"""yt-dlp plugin: solves YouTube's JavaScript challenges with the QuickJS
inside Lumtub's core library (native/lumtub_core/src/js.rs), in this
process, where no separate JavaScript program can run (iOS) or where
starting one costs time (Android).

It also keeps the preprocessed player that the solver gives back, which
yt-dlp's own providers do not: with it, a video after the first one of a
player takes about a tenth of the time. With a preprocessed player the core
answers the challenges itself (lumtub_js_solve), from the player compiled
to QuickJS bytecode once and kept beside it, without parsing the solver's
scripts and the player again.

Lumtub sets LUMTUB_CORE to the library's path. On Android it passes this
file's folder with --plugin-dirs; on iOS, where every yt-dlp runs in the
app's one Python, the runner imports it once (LUMTUB_JSC).
"""

from __future__ import annotations

import ctypes
import json
import os
import sys
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


def _setting(name, default=None):
    """A setting of Lumtub's: from the app's own Python (iOS, where the
    runner holds them) or else from the environment yt-dlp was started
    with."""
    runner = sys.modules.get('_lumtub_runner')
    settings = getattr(runner, 'SETTINGS', None) or {}
    return settings.get(name, os.environ.get(name, default))


def _library():
    global _core
    with _core_lock:
        if _core is None:
            path = _setting('LUMTUB_CORE')
            if not path:
                return None
            core = ctypes.CDLL(path)
            core.lumtub_js_run.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
            core.lumtub_js_run.restype = ctypes.c_void_p
            try:
                core.lumtub_js_solve.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
                core.lumtub_js_solve.restype = ctypes.c_void_p
            except AttributeError:
                # A core from before version 51.
                pass
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

    def _construct_stdin(self, player: str, preprocessed: bool, requests: list[JsChallengeRequest], /) -> str:
        script = super()._construct_stdin(player, preprocessed, requests)
        if preprocessed:
            # Kept for _run_js_runtime: the core answers these against the
            # player's compiled bytecode, without the solver's scripts.
            self._solve = (script, {
                'player': player,
                'requests': [{
                    'type': request.type.value,
                    'challenges': request.input.challenges,
                } for request in requests],
                'cache': self._players_folder(),
            })
        else:
            self._solve = None
        return script

    def _run_js_runtime(self, stdin: str, /) -> str:
        core = _library()
        solve = getattr(self, '_solve', None)
        self._solve = None
        if solve and solve[0] is stdin and hasattr(core, 'lumtub_js_solve'):
            try:
                out = self._call(core.lumtub_js_solve, json.dumps(solve[1]))
                self._prune_players()
                return out
            except JsChallengeProviderError as e:
                self.logger.debug(f'{e}; running the whole solver')
        out = self._call(core.lumtub_js_run, stdin)
        self._prune_players()
        return out

    def _call(self, function, text: str) -> str:
        source = text.encode('utf-8')
        pointer = function(source, len(source))
        if not pointer:
            raise JsChallengeProviderError('Lumtub core returned nothing')
        try:
            answer = json.loads(ctypes.string_at(pointer).decode('utf-8'))
        finally:
            _library().lumtub_string_free(pointer)
        self.logger.debug(f'QuickJS took {answer.get("ms")} ms')
        if answer.get('error'):
            raise JsChallengeProviderError(f'QuickJS in Lumtub core: {answer["error"]}')
        return answer['out']

    def _players_folder(self):
        try:
            return os.path.dirname(self.ie.cache._get_cache_fn(self._CACHE_SECTION, 'player', 'json'))
        except AttributeError:
            return None

    def _prune_players(self):
        folder = self._players_folder()
        try:
            names = os.listdir(folder) if folder else []
        except OSError:
            return
        players = [os.path.join(folder, n) for n in names if n.startswith('player')]
        compiled = [os.path.join(folder, n) for n in names if n.startswith('lumtub-player-') and n.endswith('.qbc')]
        self._remove_oldest(players)
        self._remove_oldest(compiled)

    @staticmethod
    def _remove_oldest(files):
        try:
            files.sort(key=os.path.getmtime, reverse=True)
        except OSError:
            return
        for old in files[_KEEP_PLAYERS:]:
            try:
                os.remove(old)
            except OSError:
                pass


@register_preference(LumtubJCP)
def preference(provider: JsChallengeProvider, requests: list[JsChallengeRequest]) -> int:
    # Ahead of the built-in runtimes (Deno 1000 is not used where this is).
    return 1100
