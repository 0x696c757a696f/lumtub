//! One segment of a YouTube stream as cast.rs reads it: the boxes of an
//! MP4 fragment (moof, traf, tfhd, tfdt, trun) and a WebM cluster.
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let _ = lumtub_core::cast::read_fragment(data, 0);
});
