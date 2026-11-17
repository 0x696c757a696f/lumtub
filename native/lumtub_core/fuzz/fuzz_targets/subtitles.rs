//! A subtitle file (WebVTT, SRT or YouTube's JSON) from a video.
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(source) = std::str::from_utf8(data) {
        let _ = lumtub_core::subtitles::cues(source);
    }
});
