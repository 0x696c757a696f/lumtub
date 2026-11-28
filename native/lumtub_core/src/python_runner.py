"""yt-dlp run inside the app's own process, one Python thread per run.

The core (python.rs) starts the interpreter once, runs this file as the
module ``_lumtub_runner`` and calls ``start`` and ``kill``. What a run
prints goes back to the core through ``lumtub_py_emit``, which posts it to
the run's Dart port; its exit code through ``lumtub_py_exit``.
"""

import os
import sys

# The app's settings (LUMTUB_CORE, SSL_CERT_FILE, and each run's TLS
# settings), which the core puts here before this file runs. They stay out
# of os.environ: changing the process environment while another thread of
# the app reads it is undefined behavior in C.
SETTINGS = globals().get("SETTINGS") or {}
_STARTUP = dict(SETTINGS)

# Python finds its compiled modules (Frameworks/*.framework, named in .fwork
# files) beside the executable; embedded, it is told which that is.
if SETTINGS.get("LUMTUB_EXECUTABLE"):
    sys.executable = SETTINGS["LUMTUB_EXECUTABLE"]

import contextlib  # noqa: E402
import ctypes  # noqa: E402
import io  # noqa: E402
import json  # noqa: E402
import threading  # noqa: E402
import zipfile  # noqa: E402

_core = ctypes.CDLL(SETTINGS["LUMTUB_CORE"])
_core.lumtub_py_emit.argtypes = (ctypes.c_int64, ctypes.c_int32, ctypes.c_char_p, ctypes.c_size_t)
_core.lumtub_py_emit.restype = None
_core.lumtub_py_exit.argtypes = (ctypes.c_int64, ctypes.c_int32)
_core.lumtub_py_exit.restype = None

_STDOUT = 1
_STDERR = 2

_lock = threading.Lock()
_runs = {}
_local = threading.local()
_loaded = None


class _Run:
    def __init__(self, port):
        self.port = port
        self.thread = None
        self.done = False

    def emit(self, fd, data):
        if data and not self.done:
            _core.lumtub_py_emit(self.port, fd, data, len(data))

    def finish(self, code):
        with _lock:
            if self.done:
                return
            self.done = True
            _runs.pop(self.port, None)
        _core.lumtub_py_exit(self.port, code)


def _current():
    return getattr(_local, "run", None)


class _Bytes(io.RawIOBase):
    def __init__(self, fd, fallback):
        self.fd = fd
        self.fallback = fallback

    def writable(self):
        return True

    def write(self, data):
        data = bytes(data)
        run = _current()
        if run is None:
            self.fallback.buffer.write(data)
        else:
            run.emit(self.fd, data)
        return len(data)

    def flush(self):
        pass


class _Text(io.TextIOBase):
    """sys.stdout or sys.stderr: each thread writes to its own run."""

    def __init__(self, fd, fallback):
        self.fd = fd
        self.fallback = fallback
        self.buffer = _Bytes(fd, fallback)

    @property
    def encoding(self):
        return "utf-8"

    @property
    def errors(self):
        return "replace"

    def writable(self):
        return True

    def isatty(self):
        return False

    def write(self, text):
        run = _current()
        if run is None:
            return self.fallback.write(text)
        run.emit(self.fd, text.encode("utf-8", "replace"))
        return len(text)

    def flush(self):
        if _current() is None:
            self.fallback.flush()


class _Nothing(io.RawIOBase):
    def readable(self):
        return True

    def readinto(self, buffer):
        return 0


def _inherit():
    """Threads a run starts (fragment downloads) write to that run too."""
    start = threading.Thread.start

    def started(self, *args, **kwargs):
        parent = _current()
        if parent is not None:
            run = self.run

            def run_in(*a, **k):
                _local.run = parent
                return run(*a, **k)

            self.run = run_in
        return start(self, *args, **kwargs)

    threading.Thread.start = started


def _challenges():
    """Registers Lumtub's challenge solver (LUMTUB_JSC, lumtub_jsc.py) once,
    for every run: through --plugin-dirs a second run would register it
    again, which yt-dlp refuses."""
    path = SETTINGS.get("LUMTUB_JSC")
    if not path or not os.path.exists(path):
        return
    try:
        import importlib.util

        spec = importlib.util.spec_from_file_location("lumtub_jsc", path)
        module = importlib.util.module_from_spec(spec)
        sys.modules["lumtub_jsc"] = module
        spec.loader.exec_module(module)
    except Exception:  # noqa: BLE001, the plugin is optional; its error is printed.
        import traceback

        traceback.print_exc()


def _bundled_roots():
    """yt-dlp's HTTPS also trusts the certificate list Python carries
    (SSL_CERT_FILE): iOS gives OpenSSL none of the system's. Loaded before
    the TLS plugin, which leaves it out when Lumtub is set to trust only
    Mozilla's or Google's list."""
    path = SETTINGS.get("SSL_CERT_FILE")
    if not path:
        return
    from yt_dlp.networking import _helper

    own = _helper.ssl_load_certs

    def ssl_load_certs(context, use_certifi=True):
        own(context, use_certifi)
        if os.path.isfile(path):
            context.load_verify_locations(cafile=path)

    _helper.ssl_load_certs = ssl_load_certs


def _tls(path):
    """Loads Lumtub's TLS plugin (lumtub_tls.py) once: yt-dlp's HTTPS then
    follows the app's certificate and post-quantum settings, which each
    run passes in its settings."""
    if not path or "lumtub_tls" in sys.modules or not os.path.exists(path):
        return
    try:
        import importlib.util

        spec = importlib.util.spec_from_file_location("lumtub_tls", path)
        module = importlib.util.module_from_spec(spec)
        sys.modules["lumtub_tls"] = module
        spec.loader.exec_module(module)
    except Exception:  # noqa: BLE001, the plugin is optional; its error is printed.
        import traceback

        traceback.print_exc()


def _version_of(app):
    with zipfile.ZipFile(app) as archive:
        source = archive.read("yt_dlp/version.py").decode()
    names = {}
    exec(compile(source, "yt_dlp/version.py", "exec"), names)  # noqa: S102, this yt-dlp runs next anyway.
    return names["__version__"]


def _main(run, app, argv, environment=None):
    global _loaded, SETTINGS  # noqa: PLW0603, both are module state shared across runs.
    _local.run = run
    # The settings in force for this run: the app's, then the run's own.
    # A new dict replaces the old in one step, so a reader on another
    # run's thread sees either the old settings or the new, never half.
    SETTINGS = {**_STARTUP, **(environment or {})}
    code = 0
    try:
        if _loaded not in (None, app) and argv == ["--version"]:
            # A newly downloaded yt-dlp checking itself, while the one
            # loaded earlier keeps running until the app restarts.
            print(_version_of(app))
        else:
            with _lock:
                if _loaded is None:
                    sys.path.insert(0, app)
                    import yt_dlp

                    _bundled_roots()
                    _challenges()
                    _loaded = app
                _tls(SETTINGS.get("LUMTUB_TLS_PLUGIN"))
            import yt_dlp

            yt_dlp.main(argv)
    except SystemExit as stop:
        if stop.code is None:
            code = 0
        elif isinstance(stop.code, int):
            code = stop.code
        else:
            sys.stderr.write(f"{stop.code}\n")
            code = 1
    except KeyboardInterrupt:
        code = 130
    except BaseException as error:  # noqa: BLE001, every failure of a run becomes its exit code.
        import traceback

        traceback.print_exception(error)
        code = 1
    finally:
        with contextlib.suppress(Exception):
            sys.stdout.flush()
        run.finish(code)
        _local.run = None


def start(port, request):
    """Starts yt-dlp ``request["app"]`` with ``request["argv"]``."""
    request = json.loads(request)
    run = _Run(port)
    with _lock:
        _runs[port] = run
    thread = threading.Thread(
        target=_main,
        args=(run, request["app"], request["argv"], request.get("environment")),
        name=f"yt-dlp {port}",
        daemon=True,
    )
    run.thread = thread
    thread.start()


def kill(port):
    """Interrupts a run: its exit is posted at once; the thread stops at
    its next Python line (a blocked read waits for its timeout)."""
    with _lock:
        run = _runs.get(port)
    if run is None:
        return
    thread = run.thread
    if thread is not None and thread.ident is not None:
        ctypes.pythonapi.PyThreadState_SetAsyncExc(
            ctypes.c_ulong(thread.ident), ctypes.py_object(KeyboardInterrupt)
        )
    run.finish(-9)


sys.stdout = _Text(_STDOUT, sys.__stdout__ or open(os.devnull, "w"))  # noqa: SIM115, the stream stays open for the process lifetime.
sys.stderr = _Text(_STDERR, sys.__stderr__ or open(os.devnull, "w"))  # noqa: SIM115, the stream stays open for the process lifetime.
sys.stdin = io.TextIOWrapper(io.BufferedReader(_Nothing()))
sys.argv = ["yt-dlp"]
_inherit()
