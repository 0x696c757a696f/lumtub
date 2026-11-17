//! An update's `.sig` file and package name: no input may pass for the
//! shipped keys, and none may crash the check.
#![no_main]
use libfuzzer_sys::fuzz_target;
use lumtub_core::signing::{PUBLIC_KEYS, verify_with};

fuzz_target!(|data: &[u8]| {
    let (name, signature) = data.split_at(data.len().min(64));
    let name = String::from_utf8_lossy(name);
    let sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    assert!(!verify_with(PUBLIC_KEYS, &name, sha256, signature));
});
