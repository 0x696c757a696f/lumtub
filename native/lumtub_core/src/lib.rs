//! Native helpers Lumtub calls through `dart:ffi` (see lib/native/core.dart).
//!
//! Every export is a plain C function. Lumtub needs the library for its
//! recommendations; the process tree is used when the platform has one.

pub mod format_policy;
pub mod process_tree;
pub mod taste;

/// The version of this library's exports, bumped when one changes.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_core_version() -> u32 {
    3
}
