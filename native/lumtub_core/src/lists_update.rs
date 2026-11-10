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
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// Reads [json] after checking [signature] against it with [keys], and that
/// its lists hang together.
fn read_signed(keys: &[u8], json: &[u8], signature: &[u8]) -> Result<Owned, String> {
    if !signing::verify_with(keys, NAME, &sha256(json), signature) {
        return Err("the signature does not match".into());
    }
    let owned: Owned =
        serde_json::from_slice(json).map_err(|e| format!("it does not read: {e}"))?;
    if owned.lists.is_empty() {
        return Err("it has no lists".into());
    }
    let mut problems = lists::check_all(&owned.lists, &Default::default());
    for list in &owned.lists {
        if list.id.is_empty()
            || list.categories.is_empty()
            || list.categories.iter().any(|c| lists::tier(c).is_none())
        {
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

/// The file a download is kept in: the signature's length (4 bytes, little
/// endian), the signature, then the json. One file, so it is replaced
/// whole or not at all.
pub const KEPT: &str = "lists.signed";

fn join(json: &[u8], signature: &[u8]) -> Vec<u8> {
    let mut kept = Vec::with_capacity(4 + signature.len() + json.len());
    kept.extend_from_slice(&(signature.len() as u32).to_le_bytes());
    kept.extend_from_slice(signature);
    kept.extend_from_slice(json);
    kept
}

fn split(kept: &[u8]) -> Option<(&[u8], &[u8])> {
    let length = u32::from_le_bytes(kept.get(..4)?.try_into().ok()?) as usize;
    let signature = kept.get(4..4usize.checked_add(length)?)?;
    Some((&kept[4 + length..], signature))
}

/// The download kept in [folder] and its signature, when the pair verifies.
fn stored(keys: &[u8], folder: &Path) -> Option<(Owned, Vec<u8>)> {
    let kept = std::fs::read(folder.join(KEPT)).ok()?;
    let (json, signature) = split(&kept)?;
    Some((read_signed(keys, json, signature).ok()?, signature.to_vec()))
}

/// What is in use from [folder].
struct InUse {
    version: u64,
    built: String,
    lists: Vec<List>,
    downloaded: bool,
    /// The signature of the verified download kept there, newer or not, so
    /// a check can tell the same file is published.
    signature: Option<Vec<u8>>,
}

fn in_use(keys: &[u8], folder: &Path) -> InUse {
    match stored(keys, folder) {
        Some((owned, signature)) if owned.version > built_version() => InUse {
            version: owned.version,
            built: owned.built,
            lists: owned.lists,
            downloaded: true,
            signature: Some(signature),
        },
        found => InUse {
            version: built_version(),
            built: String::new(),
            lists: lists::built_in().to_vec(),
            downloaded: false,
            signature: found.map(|(_, s)| s),
        },
    }
}

/// The lists to use: a downloaded file in [folder] when it is newer than
/// the built-in lists, else those. Answers (version, built, lists,
/// downloaded).
pub fn current(folder: &Path) -> (u64, String, Vec<List>, bool) {
    let used = in_use(signing::PUBLIC_KEYS, folder);
    (used.version, used.built, used.lists, used.downloaded)
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
/// lists in use from [folder], keeps both there in one file (written beside
/// it first, then renamed over the old one).
pub fn take(json: &[u8], signature: &[u8], folder: &Path) -> Result<Taken, String> {
    take_with(signing::PUBLIC_KEYS, json, signature, folder)
}

fn take_with(keys: &[u8], json: &[u8], signature: &[u8], folder: &Path) -> Result<Taken, String> {
    let owned = read_signed(keys, json, signature)?;
    let records = owned.lists.iter().map(|l| l.records.len()).sum();
    let taken = Taken {
        version: owned.version,
        lists: owned.lists.len(),
        records,
        newer: owned.version > in_use(keys, folder).version,
    };
    if !taken.newer {
        return Ok(taken);
    }
    std::fs::create_dir_all(folder).map_err(|e| e.to_string())?;
    let temporary = folder.join(format!("{KEPT}.new"));
    std::fs::write(&temporary, join(json, signature)).map_err(|e| format!("{KEPT}: {e}"))?;
    std::fs::rename(&temporary, folder.join(KEPT)).map_err(|e| format!("{KEPT}: {e}"))?;
    Ok(taken)
}

#[derive(Serialize)]
struct Bundle<'a> {
    version: u64,
    built: &'a str,
    downloaded: bool,
    /// Hex of the signature of the verified download kept, if any.
    #[serde(skip_serializing_if = "Option::is_none")]
    signature: Option<String>,
    lists: &'a [List],
}

/// The lists in use with their version, `{version, built, downloaded,
/// signature?, lists}`, [json] being `{"folder": "..."}`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_lists_in(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        folder: String,
    }
    let folder = serde_json::from_str::<Ask>(unsafe { text(json, length) })
        .map(|a| a.folder)
        .unwrap_or_default();
    let used = if folder.is_empty() {
        InUse {
            version: built_version(),
            built: String::new(),
            lists: lists::built_in().to_vec(),
            downloaded: false,
            signature: None,
        }
    } else {
        in_use(signing::PUBLIC_KEYS, Path::new(&folder))
    };
    let signature = used
        .signature
        .map(|s| s.iter().map(|b| format!("{b:02x}")).collect());
    give_json(&Bundle {
        version: used.version,
        built: &used.built,
        downloaded: used.downloaded,
        signature,
        lists: &used.lists,
    })
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
    let answer = serde_json::from_str::<Ask>(unsafe { text(json, length) })
        .map_err(|e| e.to_string())
        .and_then(|ask| {
            let file = std::fs::read(&ask.file).map_err(|e| format!("{}: {e}", ask.file))?;
            let signature =
                std::fs::read(&ask.signature).map_err(|e| format!("{}: {e}", ask.signature))?;
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
        serde_json::to_vec(&lists::Bundle {
            version,
            built: "2026-11-09T00:00:00Z",
            lists: lists::built_in(),
        })
        .unwrap()
    }

    fn signed(json: &[u8]) -> Vec<u8> {
        signing::sign(&SECRET, NAME, &sha256(json))
    }

    fn folder(name: &str) -> std::path::PathBuf {
        let folder =
            std::env::temp_dir().join(format!("lumtub-lists-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&folder);
        folder
    }

    #[test]
    fn the_compiled_lists_read_back_as_built() {
        let owned: Owned = serde_json::from_slice(&bundle(5)).unwrap();
        assert_eq!(owned.version, 5);
        assert_eq!(owned.lists, lists::built_in());
    }

    fn keys() -> Vec<u8> {
        signing::public_keys(&SECRET)
    }

    #[test]
    fn signatures_and_content_are_checked() {
        let json = bundle(u64::MAX);
        assert!(read_signed(&keys(), &json, &signed(&json)).is_ok());
        // The shipped keys are not the test key: a test signature is refused.
        assert_eq!(
            read_signed(signing::PUBLIC_KEYS, &json, &signed(&json))
                .err()
                .as_deref(),
            Some("the signature does not match")
        );
        assert!(read_signed(&keys(), &json, &[0; signing::SIGNATURE_LENGTH]).is_err());
        let mut changed = json.clone();
        changed[10] ^= 1;
        assert!(read_signed(&keys(), &changed, &signed(&json)).is_err());
    }

    #[test]
    fn a_folder_without_a_download_uses_the_built_in_lists() {
        let dir = folder("none");
        let used = in_use(&keys(), &dir);
        assert_eq!(used.version, built_version());
        assert_eq!(used.lists, lists::built_in());
        assert!(!used.downloaded && used.signature.is_none());
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn a_taken_download_is_used_after_a_restart() {
        let dir = folder("taken");
        let json = bundle(u64::MAX - 1);
        let taken = take_with(&keys(), &json, &signed(&json), &dir).unwrap();
        assert!(taken.newer);
        assert!(!dir.join(format!("{KEPT}.new")).exists());
        let used = in_use(&keys(), &dir);
        assert_eq!(used.version, u64::MAX - 1);
        assert!(used.downloaded);
        assert_eq!(used.signature, Some(signed(&json)));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn an_older_or_the_same_version_is_not_taken() {
        let dir = folder("rollback");
        let newer = bundle(u64::MAX - 1);
        take_with(&keys(), &newer, &signed(&newer), &dir).unwrap();
        for version in [u64::MAX - 1, u64::MAX - 2, 1] {
            let json = bundle(version);
            assert!(
                !take_with(&keys(), &json, &signed(&json), &dir)
                    .unwrap()
                    .newer
            );
        }
        assert_eq!(in_use(&keys(), &dir).version, u64::MAX - 1);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_damaged_or_cut_file_is_ignored() {
        let dir = folder("damaged");
        let json = bundle(u64::MAX - 1);
        take_with(&keys(), &json, &signed(&json), &dir).unwrap();
        let whole = std::fs::read(dir.join(KEPT)).unwrap();
        for bad in [
            whole[..whole.len() - 1].to_vec(),
            whole[..3].to_vec(),
            Vec::new(),
            {
                let mut flipped = whole.clone();
                let last = flipped.len() - 2;
                flipped[last] ^= 1;
                flipped
            },
            {
                let mut long = whole.clone();
                long[..4].copy_from_slice(&u32::MAX.to_le_bytes());
                long
            },
        ] {
            std::fs::write(dir.join(KEPT), &bad).unwrap();
            let used = in_use(&keys(), &dir);
            assert!(
                !used.downloaded && used.signature.is_none(),
                "a damaged file must not count"
            );
            assert_eq!(used.lists, lists::built_in());
        }
        // A write cut short leaves only the file beside it; the kept one stays.
        std::fs::write(dir.join(KEPT), &whole).unwrap();
        std::fs::write(dir.join(format!("{KEPT}.new")), &whole[..100]).unwrap();
        assert!(in_use(&keys(), &dir).downloaded);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_wrongly_signed_download_is_refused_and_nothing_written() {
        let dir = folder("refused");
        let json = bundle(u64::MAX);
        assert!(take(&json, &signed(&json), &dir).is_err());
        assert!(take_with(&keys(), &json, &[0; signing::SIGNATURE_LENGTH], &dir).is_err());
        assert!(!dir.join(KEPT).exists());
    }
}
