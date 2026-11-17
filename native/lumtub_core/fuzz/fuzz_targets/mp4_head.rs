//! The head (ftyp, moov, sidx) of a YouTube MP4 stream, as cast.rs reads it.
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let _ = lumtub_core::cast::read_head(data);
});
