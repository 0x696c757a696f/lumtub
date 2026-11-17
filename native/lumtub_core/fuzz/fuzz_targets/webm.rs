//! A WebM head with its Cues, and one cluster's frames (cast_webm.rs).
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if lumtub_core::cast_webm::is_webm(data) {
        let _ = lumtub_core::cast_webm::read_head(data, data.len() as u64);
    }
    for track in 0..3 {
        let _ = lumtub_core::cast_webm::frames(data, track);
    }
});
