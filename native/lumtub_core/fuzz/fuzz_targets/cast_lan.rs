//! What a device on the local network sends while casting: Chromecast
//! frames, mDNS and SSDP replies, UPnP descriptions and SOAP answers.
#![no_main]
use libfuzzer_sys::fuzz_target;
use lumtub_core::cast_lan;

fuzz_target!(|data: &[u8]| {
    let _ = cast_lan::cast_frames(data);
    let _ = cast_lan::mdns_records(data);
    if let Ok(text) = std::str::from_utf8(data) {
        let _ = cast_lan::ssdp(text);
        let _ = cast_lan::description(text);
        let _ = cast_lan::soap(text);
        let _ = lumtub_core::feed::parse(text);
    }
});
