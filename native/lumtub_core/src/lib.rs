//! Native helpers Lumtub calls through `dart:ffi` (see lib/native/core.dart).
//!
//! Every export is a plain C function. Lumtub needs the library for its
//! recommendations; the process tree is used when the platform has one.

pub mod airplay;
pub mod anki;
pub mod ass;
pub mod backup;
pub mod browser_sign_in;
pub mod caption_lines;
pub mod cast;
pub mod cast_lan;
pub mod cast_mkv;
pub mod cast_webm;
pub mod comment_action;
pub mod comments;
pub mod counts;
pub mod cut;
pub mod danmaku;
pub mod dns;
pub mod downloads;
mod edge_drm;
pub mod edge_tts;
pub mod embed;
pub mod feed;
pub mod filter;
pub mod format_policy;
pub mod hashes;
pub mod http;
pub mod hw_decode;
pub mod innertube;
pub mod insights;
pub mod join;
pub mod js;
pub mod lexicon;
pub mod listing;
pub mod lists;
pub mod lists_update;
pub mod live_chat;
pub mod loopback;
pub mod mic;
pub mod netwatch;
pub mod pac;
pub mod packs;
pub mod playlist_sync;
pub mod posts;
pub mod process_cpu;
pub mod process_tree;
#[cfg(unix)]
pub mod python;
pub mod quick;
pub mod record;
pub mod redact;
pub mod redirect;
pub mod relay;
pub mod relay_hls;
pub mod relay_live;
pub mod relay_video;
pub mod resolved;
pub mod review;
pub mod roots;
pub mod signing;
pub mod socks;
pub mod speech;
pub mod store;
pub mod store_texts;
pub mod subtitles;
pub mod system_proxy;
pub mod taste;
pub mod tls;
pub mod tv_account;
pub mod tv_browse;
pub mod tv_history;
pub mod update;
pub mod vault;
pub mod vtt;
pub mod web_account;
pub mod words;
pub mod ytdlp_signature;

/// The version of this library's exports, bumped when one changes.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_core_version() -> u32 {
    65
}
