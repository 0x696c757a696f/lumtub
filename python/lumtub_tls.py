"""yt-dlp plugin: yt-dlp's own HTTPS follows Lumtub's settings 证书来源
(certificate authorities) and 抗量子加密 (post-quantum encryption).

LUMTUB_CA_FILE names a PEM file of the authorities to trust. With
LUMTUB_CA_ONLY=1 they are the only ones (Mozilla's or Google's list);
otherwise they are trusted besides yt-dlp's own (the system's store).

The key exchange groups and TLS versions come from the OpenSSL
configuration Lumtub points OPENSSL_CONF at. OpenSSL 3.5 and later offer
X25519MLKEM768 first by default; an older one cannot offer it at all, so
with LUMTUB_PQ=require every HTTPS connection is refused there instead
of going out without it.
"""

from __future__ import annotations

import os
import ssl

from yt_dlp.networking import _helper

_FILE = os.environ.get('LUMTUB_CA_FILE') or None
_ONLY = os.environ.get('LUMTUB_CA_ONLY') == '1'
_REQUIRE = os.environ.get('LUMTUB_PQ') == 'require'
_own = getattr(_helper, 'ssl_load_certs', None)


def ssl_load_certs(context, use_certifi=True):
    if _REQUIRE and ssl.OPENSSL_VERSION_INFO < (3, 5):
        raise ssl.SSLError(f'{ssl.OPENSSL_VERSION} cannot offer X25519MLKEM768, which Lumtub is set to require')
    if _FILE is None:
        _own(context, use_certifi)
        return
    if not _ONLY:
        _own(context, use_certifi)
    if not os.path.isfile(_FILE):
        if _ONLY:
            raise ssl.SSLError(f'The certificate list {_FILE} is missing')
        return
    context.load_verify_locations(cafile=_FILE)


if _own is not None:
    _helper.ssl_load_certs = ssl_load_certs
