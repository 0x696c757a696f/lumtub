//! Native helpers Lumtub calls through `dart:ffi` (see lib/native/core.dart).
//!
//! Every export is a plain C function. Lumtub needs the library for its
//! recommendations; the process tree is used when the platform has one.

pub mod airplay;
pub mod backup;
pub mod browser_sign_in;
pub mod cast;
pub mod cast_mkv;
pub mod cast_webm;
pub mod comment_action;
pub mod comments;
pub mod cut;
pub mod danmaku;
pub mod dns;
pub mod downloads;
pub mod embed;
pub mod filter;
pub mod format_policy;
pub mod hashes;
pub mod http;
pub mod hw_decode;
pub mod innertube;
pub mod insights;
pub mod join;
pub mod listing;
pub mod lists;
pub mod lists_update;
pub mod live_chat;
pub mod pac;
pub mod posts;
pub mod process_cpu;
pub mod process_tree;
pub mod quick;
pub mod record;
pub mod redact;
pub mod redirect;
pub mod relay;
pub mod relay_live;
pub mod resolved;
pub mod roots;
pub mod signing;
pub mod socks;
pub mod subtitles;
pub mod system_proxy;
pub mod taste;
pub mod tls;
pub mod tv_account;
pub mod tv_browse;
pub mod tv_history;
pub mod update;
pub mod vault;
pub mod web_account;

/// The version of this library's exports, bumped when one changes.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_core_version() -> u32 {
    47
}
