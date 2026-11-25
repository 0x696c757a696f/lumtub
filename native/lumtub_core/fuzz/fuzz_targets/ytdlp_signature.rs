//! yt-dlp's `SHA2-256SUMS.sig` read by the core: no input may crash the
//! OpenPGP parsing, and none may pass for yt-dlp's key over these sums.
#![no_main]
use libfuzzer_sys::fuzz_target;
use lumtub_core::ytdlp_signature::verify;

fuzz_target!(|data: &[u8]| {
    assert!(verify(b"0000  yt-dlp\n", data, Some("2026.11.24.000000")).is_err());
});
