//! Answers from servers the core reads: Piped and Invidious stream lists,
//! search suggestions, and the storyboard and heatmap of yt-dlp's answer.
#![no_main]
use libfuzzer_sys::fuzz_target;
use lumtub_core::{relay_video, resolved, suggestions};

fuzz_target!(|data: &[u8]| {
    let _ = suggestions::suggestions(data);
    let Ok(value) = serde_json::from_slice::<serde_json::Value>(data) else {
        return;
    };
    if let Some(json) = value.as_object() {
        let _ = relay_video::piped(json);
        let _ = relay_video::invidious(json);
    }
    if let Some(board) = resolved::storyboard(&value) {
        assert!(board.width > 0 && board.interval > 0 && !board.sheets.is_empty());
    }
    if let Some(heat) = resolved::heatmap(&value) {
        assert!(heat.iter().all(|v| (0.0..=1.0).contains(v)));
    }
});
