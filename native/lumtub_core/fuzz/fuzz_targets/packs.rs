//! A data pack catalog or an installed pack's entry: nothing read may
//! crash the check, and nothing accepted may name a path outside the pack.
#![no_main]
use libfuzzer_sys::fuzz_target;
use lumtub_core::packs::{parse, read_entry};

fn inside(path: &str) -> bool {
    !path.split('/').any(|part| part.is_empty() || part == "..") && !path.contains(['\\', ':'])
}

fuzz_target!(|data: &[u8]| {
    if let Ok(catalog) = parse(data) {
        assert!(catalog.packs.iter().flat_map(|p| &p.files).all(|f| inside(&f.path)));
    }
    if let Ok(pack) = read_entry(data) {
        assert!(pack.files.iter().all(|f| inside(&f.path)));
    }
});
