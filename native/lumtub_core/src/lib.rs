//! Native helpers Lumtub calls through `dart:ffi` (see lib/native/core.dart).
//!
//! Every export is a plain C function. Lumtub needs the library for its
//! recommendations; the process tree is used when the platform has one.

pub mod comments;
pub mod filter;
pub mod downloads;
pub mod format_policy;
pub mod process_tree;
pub mod redact;
pub mod relay;
pub mod socks;
pub mod subtitles;
pub mod system_proxy;
pub mod hashes;
pub mod dns;
pub mod http;
pub mod hw_decode;
pub mod posts;
pub mod innertube;
pub mod listing;
pub mod live_chat;
pub mod taste;
pub mod update;

/// The version of this library's exports, bumped when one changes.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_core_version() -> u32 {
    14
}
