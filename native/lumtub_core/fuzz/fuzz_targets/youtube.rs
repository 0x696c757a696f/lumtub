//! What YouTube, yt-dlp, SponsorBlock, DeArrow and a transcription server
//! answer, and the text inside: every parser of the JSON pages and of the
//! titles, counts, times and tokens in them.
#![no_main]
use libfuzzer_sys::fuzz_target;
use lumtub_core::{
    ass, comment_action, comments, counts, downloads, filter, hashes, innertube, insights,
    listing, lists, live_chat, posts, quick, resolved, taste, tv_browse,
};
use serde_json::Value;

/// Calls an FFI parser on [text] and frees what it gives.
fn ffi(text: &str, call: impl Fn(*const u8, usize) -> *mut std::ffi::c_char) {
    let answer = call(text.as_ptr(), text.len());
    // SAFETY: the answer is null or a string the core gave.
    unsafe { taste::lumtub_string_free(answer) };
}

fuzz_target!(|data: &[u8]| {
    let Ok(text) = std::str::from_utf8(data) else {
        return;
    };
    let _ = posts::initial_data(text);
    let _ = live_chat::lines(text);
    let _ = listing::ago(text);
    let _ = listing::count(text);
    let _ = counts::count_in(text, "en");
    let _ = counts::count_in(text, "de");
    let _ = innertube::listed_channel_ids(text);
    let _ = insights::transcript(text, 2000, 20);
    let _ = ass::parse(text);
    let _ = filter::title_language(text);
    let _ = lists::parse(text, "fuzz");
    let mut lines = text.splitn(3, '\n');
    if let (Some(action), Some(from), Some(to)) = (lines.next(), lines.next(), lines.next()) {
        let _ = comment_action::action_for(action, from, to);
    }
    // SAFETY: each call gets the bytes of [text].
    ffi(text, |p, n| unsafe { innertube::lumtub_youtube_next(p, n) });
    ffi(text, |p, n| unsafe { quick::lumtub_quick_info(p, n, b"{}".as_ptr(), 2) });
    let Ok(value) = serde_json::from_str::<Value>(text) else {
        return;
    };
    let _ = innertube::spoken_language(&value);
    let _ = innertube::ai_label(&value);
    let _ = innertube::ai_channels(&value);
    let _ = listing::page(&value);
    let _ = comments::page(&value);
    let _ = posts::page(&value);
    let _ = posts::section_token(&value);
    let _ = live_chat::composer(&value);
    let _ = tv_browse::page(&value, false);
    let _ = tv_browse::page(&value, true);
    let _ = resolved::summary(&value, &resolved::Ask::default());
    let _ = downloads::Formats::parse(&value);
    let _ = hashes::segments(&value, "dQw4w9WgXcQ", &["sponsor".into()]);
    let _ = hashes::branding(&value, "dQw4w9WgXcQ");
    let _ = insights::speech_vtt(&value);
    let _ = insights::overview_check("WEBVTT\n\n00:00.000 --> 00:05.000\nhello\n", &value);
});
