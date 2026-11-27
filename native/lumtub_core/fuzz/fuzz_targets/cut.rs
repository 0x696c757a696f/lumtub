//! A downloaded WebM or MP4 sound file cut into parts (cut.rs).
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let mut input = std::io::Cursor::new(data);
    let _ = lumtub_core::cut::cut_from(&mut input, data.len() as u64, 2.0, |_| Ok(std::io::sink()));
});
