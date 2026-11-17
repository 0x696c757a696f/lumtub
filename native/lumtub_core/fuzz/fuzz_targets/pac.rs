//! A proxy auto-configuration script from the network.
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(script) = std::str::from_utf8(data) {
        let _ = lumtub_core::pac::proxy_in(script);
    }
});
