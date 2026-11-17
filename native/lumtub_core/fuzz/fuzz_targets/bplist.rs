//! A binary property list from an AirPlay receiver.
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let _ = lumtub_core::airplay::bplist::read(data);
});
