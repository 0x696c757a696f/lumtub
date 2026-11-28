"""yt-dlp plugin: yt-dlp's own HTTPS follows Lumtub's certificate authority
and post-quantum encryption settings.

LUMTUB_CA_FILE names a PEM file of the authorities to trust. With
LUMTUB_CA_ONLY=1 they are the only ones (Mozilla's or Google's list);
otherwise they are trusted besides yt-dlp's own (the system's store).

LUMTUB_PQ is prefer, off or require. Python 3.15 sets the key exchange
groups of each connection itself; before it, they come from the OpenSSL
configuration Lumtub points OPENSSL_CONF at. OpenSSL 3.5 and later offer
X25519MLKEM768 first by default; an older one cannot offer it at all, so
with require every HTTPS connection is refused there instead of going out
without it.

The settings are read for every connection: on iOS every yt-dlp run
shares the app's one Python, and the settings may change between runs.
There they come from the runner's SETTINGS, not the environment.
"""

from __future__ import annotations

import os
import ssl
import sys

from yt_dlp.networking import _helper

_GROUPS = {
    'off': 'X25519:secp256r1:X448:secp384r1:secp521r1:ffdhe2048:ffdhe3072',
    'require': 'X25519MLKEM768:SecP256r1MLKEM768',
}
_own = getattr(_helper, 'ssl_load_certs', None)


def _setting(name, default=None):
    """A setting of Lumtub's: from the app's own Python (iOS, where the
    runner holds them) or else from the environment yt-dlp was started
    with."""
    runner = sys.modules.get('_lumtub_runner')
    settings = getattr(runner, 'SETTINGS', None) or {}
    return settings.get(name, os.environ.get(name, default))


def _quantum(context):
    mode = _setting('LUMTUB_PQ', 'prefer')
    if mode == 'require' and ssl.OPENSSL_VERSION_INFO < (3, 5):
        raise ssl.SSLError(f'{ssl.OPENSSL_VERSION} cannot offer X25519MLKEM768, which Lumtub is set to require')
    groups = _GROUPS.get(mode)
    if groups and hasattr(context, 'set_groups'):
        context.set_groups(groups)
    if mode == 'require':
        context.minimum_version = ssl.TLSVersion.TLSv1_3


def ssl_load_certs(context, use_certifi=True):
    _quantum(context)
    path = _setting('LUMTUB_CA_FILE') or None
    only = _setting('LUMTUB_CA_ONLY') == '1'
    if path is None or not only:
        _own(context, use_certifi)
    if path is None:
        return
    if not os.path.isfile(path):
        if only:
            raise ssl.SSLError(f'The certificate list {path} is missing')
        return
    context.load_verify_locations(cafile=path)


if _own is not None:
    _helper.ssl_load_certs = ssl_load_certs
