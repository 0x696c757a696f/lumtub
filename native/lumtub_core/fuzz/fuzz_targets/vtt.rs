//! A subtitle track to translate, and a translation to cut like its cues.
#![no_main]
use libfuzzer_sys::fuzz_target;
use lumtub_core::vtt;

fuzz_target!(|data: &[u8]| {
    let Ok(source) = std::str::from_utf8(data) else {
        return;
    };
    let plan = vtt::plan(source);
    let _ = vtt::sentences(&vtt::cues(source), 7_000_000, 90);
    // The first bytes as weights, the rest as the translation.
    let weights: Vec<i64> = data.iter().take(6).map(|b| i64::from(*b) - 16).collect();
    let parts = vtt::split_like(source, &weights);
    assert!(!parts.is_empty());
    for piece in plan.pieces {
        assert!(!piece.is_empty());
    }
});
