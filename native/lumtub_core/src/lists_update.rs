//! Block list updates: a signed `lists.json` published on the `lists`
//! release replaces the lists built into this library once it is newer.
//!
//! The file is signed like the app's packages (see signing.rs), under the
//! name `lists.json`. Its `version` is the commit time of the lists it was
//! built from; the lists built into this library carry the commit time of
//! the source they were built with, so a downloaded file is used only when
//! it is newer than both those and any file taken before (no rollback).

use std::os::raw::c_char;
use std::path::Path;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::lists::{self, List};
use crate::signing;
use crate::taste::{give_json, text};

/// The name the file is signed under.
pub const NAME: &str = "lists.json";

/// The version of the lists built into this library.
pub fn built_version() -> u64 {
    env!("LUMTUB_LISTS_VERSION").parse().unwrap_or(0)
}

#[derive(Deserialize)]
struct Owned {
    version: u64,
    #[serde(default)]
    built: String,
    lists: Vec<List>,
}

fn sha256(bytes: &[u8]) -> String {
    Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}

/// Reads [json] after checking [signature] against it, and that its lists
/// hang together.
fn read_signed(json: &[u8], signature: &[u8]) -> Result<Owned, String> {
    if !signing::verify_with(signing::PUBLIC_KEYS, NAME, &sha256(json), signature) {
        return Err("the signature does not match".into());
    }
    let owned: Owned = serde_json::from_slice(json).map_err(|e| format!("it does not read: {e}"))?;
    if owned.lists.is_empty() {
        return Err("it has no lists".into());
    }
    let mut problems = lists::check_all(&owned.lists, &Default::default());
    for list in &owned.lists {
        if list.id.is_empty() || list.categories.is_empty() || list.categories.iter().any(|c| lists::tier(c).is_none()) {
            problems.push(format!("the list {} has no known category", list.id));
        }
        if list.records.iter().any(|r| r.slug.is_empty()) {
            problems.push(format!("the list {} has a record without a key", list.id));
        }
    }
    if let Some(first) = problems.first() {
        return Err(first.clone());
    }
    Ok(owned)
}

fn stored(folder: &Path) -> Option<Owned> {
    let json = std::fs::read(folder.join(NAME)).ok()?;
    let signature = std::fs::read(folder.join(format!("{NAME}.sig"))).ok()?;
    read_signed(&json, &signature).ok()
}

/// The lists to use: a downloaded file in [folder] when it is newer than
/// the built-in lists, else those. Answers (version, built, lists,
/// downloaded).
pub fn current(folder: &Path) -> (u64, String, Vec<List>, bool) {
    match stored(folder) {
        Some(owned) if owned.version > built_version() => (owned.version, owned.built, owned.lists, true),
        _ => (built_version(), String::new(), lists::built_in().to_vec(), false),
    }
}

/// What taking a download did.
#[derive(Debug, PartialEq, Serialize)]
pub struct Taken {
    pub version: u64,
    pub lists: usize,
    pub records: usize,
    /// False when the file is not newer than the lists in use.
    pub newer: bool,
}

/// Checks the downloaded [json] and [signature] and, when newer than the
/// lists in use from [folder], writes both there (each to a temporary file
/// first, then renamed over the old one).
pub fn take(json: &[u8], signature: &[u8], folder: &Path) -> Result<Taken, String> {
    let owned = read_signed(json, signature)?;
    let records = owned.lists.iter().map(|l| l.records.len()).sum();
    let taken = Taken { version: owned.version, lists: owned.lists.len(), records, newer: owned.version > current(folder).0 };
    if !taken.newer {
        return Ok(taken);
    }
    std::fs::create_dir_all(folder).map_err(|e| e.to_string())?;
    let write = |name: &str, bytes: &[u8]| -> Result<(), String> {
        let temporary = folder.join(format!("{name}.new"));
        std::fs::write(&temporary, bytes).map_err(|e| format!("{name}: {e}"))?;
        std::fs::rename(&temporary, folder.join(name)).map_err(|e| format!("{name}: {e}"))
    };
    // The signature last: until it is in place the pair does not verify,
    // and the built-in lists are used.
    let _ = std::fs::remove_file(folder.join(format!("{NAME}.sig")));
    write(NAME, json)?;
    write(&format!("{NAME}.sig"), signature)?;
    Ok(taken)
}

#[derive(Serialize)]
struct Bundle<'a> {
    version: u64,
    built: &'a str,
    downloaded: bool,
    lists: &'a [List],
}

/// The lists in use with their version, `{version, built, downloaded,
/// lists}`, [json] being `{"folder": "..."}`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_lists_in(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        folder: String,
    }
    let folder = serde_json::from_str::<Ask>(unsafe { text(json, length) }).map(|a| a.folder).unwrap_or_default();
    let (version, built, lists, downloaded) = if folder.is_empty() {
        (built_version(), String::new(), lists::built_in().to_vec(), false)
    } else {
        current(Path::new(&folder))
    };
    give_json(&Bundle { version, built: &built, downloaded, lists: &lists })
}

/// Takes a downloaded update, [json] being `{file, signature, folder}`
/// (paths). Answers [Taken] or `{"error": "..."}`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_lists_take(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        file: String,
        signature: String,
        folder: String,
    }
    #[derive(Serialize)]
    struct Failed {
        error: String,
    }
    let answer = serde_json::from_str::<Ask>(unsafe { text(json, length) }).map_err(|e| e.to_string()).and_then(|ask| {
        let file = std::fs::read(&ask.file).map_err(|e| format!("{}: {e}", ask.file))?;
        let signature = std::fs::read(&ask.signature).map_err(|e| format!("{}: {e}", ask.signature))?;
        take(&file, &signature, Path::new(&ask.folder))
    });
    match answer {
        Ok(taken) => give_json(&taken),
        Err(error) => give_json(&Failed { error }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SECRET: [u8; 64] = [7; 64];

    fn bundle(version: u64) -> Vec<u8> {
        serde_json::to_vec(&lists::Bundle { version, built: "2026-11-09T00:00:00Z", lists: lists::built_in() }).unwrap()
    }

    fn signed(json: &[u8]) -> Vec<u8> {
        signing::sign(&SECRET, NAME, &sha256(json))
    }

    fn folder(name: &str) -> std::path::PathBuf {
        let folder = std::env::temp_dir().join(format!("lumtub-lists-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&folder);
        folder
    }

    #[test]
    fn the_compiled_lists_read_back_as_built() {
        let owned: Owned = serde_json::from_slice(&bundle(5)).unwrap();
        assert_eq!(owned.version, 5);
        assert_eq!(owned.lists, lists::built_in());
    }

    #[test]
    fn signatures_and_content_are_checked() {
        let json = bundle(u64::MAX);
        let keys = signing::public_keys(&SECRET);
        assert!(signing::verify_with(&keys, NAME, &sha256(&json), &signed(&json)));
        // The shipped keys are not the test key: a test signature is refused.
        assert_eq!(read_signed(&json, &signed(&json)).err().as_deref(), Some("the signature does not match"));
        assert!(read_signed(&json, &[0; signing::SIGNATURE_LENGTH]).is_err());
    }

    #[test]
    fn a_folder_without_a_download_uses_the_built_in_lists() {
        let dir = folder("none");
        let (version, _, lists, downloaded) = current(&dir);
        assert_eq!(version, built_version());
        assert_eq!(lists, lists::built_in());
        assert!(!downloaded);
        // A file whose signature does not hold is ignored.
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join(NAME), bundle(u64::MAX)).unwrap();
        std::fs::write(dir.join(format!("{NAME}.sig")), vec![0; signing::SIGNATURE_LENGTH]).unwrap();
        assert!(!current(&dir).3);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_wrongly_signed_download_is_refused_and_nothing_written() {
        let dir = folder("refused");
        let json = bundle(u64::MAX);
        assert!(take(&json, &signed(&json), &dir).is_err());
        assert!(!dir.join(NAME).exists());
    }
}
