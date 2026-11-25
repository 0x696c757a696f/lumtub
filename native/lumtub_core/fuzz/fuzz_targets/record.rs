//! A recorded live stream (or any file passed to join) given an index
//! (record.rs).
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let mut input = std::io::Cursor::new(data);
    let _ = lumtub_core::record::unindexed_from(&mut input, data.len() as u64);
});
