//! Data packs: models, language data, shaders and runtimes that Lumtub
//! downloads only when a feature needs them, never inside the installer.
//!
//! What can be installed is listed in a signed `packs.json` on the `packs`
//! release, signed like the app's packages (see signing.rs) under the name
//! `packs.json`. Each pack names its files with their size and SHA-256, so
//! a file is trusted only through the signed catalog, wherever it is
//! downloaded from. Its `version` is the commit time it was built from; a
//! catalog older than the one kept is refused (no rollback).
//!
//! Packs hold data only. A runtime pack (a library the app loads) may only
//! come from Lumtub's own releases.

use std::collections::{BTreeMap, HashSet};
use std::os::raw::c_char;
use std::path::Path;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::signing;
use crate::taste::{give_json, text};

/// The name the catalog is signed under.
pub const NAME: &str = "packs.json";

/// The file a taken catalog is kept in: the signature's length (4 bytes,
/// little endian), the signature, then the json.
pub const KEPT: &str = "packs.signed";

/// The file inside an installed pack's folder that holds its catalog entry.
pub const ENTRY: &str = "pack.json";

/// Where a runtime pack's files must come from.
const OWN_RELEASES: &str = "https://github.com/0x696c757a696f/";

/// Hosts any other pack's files may come from.
const HOSTS: &[&str] = &["github.com", "huggingface.co"];

const MOST_PACKS: usize = 500;
const MOST_FILES: usize = 64;
/// 8 GiB: the largest model worth offering on a computer.
const MOST_BYTES: u64 = 8 << 30;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Runtime,
    Model,
    Language,
    Shader,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PackFile {
    /// Where it goes inside the pack's folder, with `/` between folders.
    pub path: String,
    pub url: String,
    pub sha256: String,
    pub size: u64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Pack {
    pub id: String,
    pub version: String,
    pub kind: Kind,
    /// By language tag; `en` is required.
    pub title: BTreeMap<String, String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub description: BTreeMap<String, String>,
    /// An SPDX expression, such as `MIT` or `CC-BY-4.0`.
    pub license: String,
    /// Attribution the license asks to show.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub notice: String,
    /// Where the files were made from, for the settings page.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub source: String,
    /// The first app version that can use it, such as `0.2.59`.
    #[serde(default, rename = "minApp", skip_serializing_if = "String::is_empty")]
    pub min_app: String,
    /// The packages it is for, such as `windows-x64` or `macos-arm64`; empty
    /// means every one.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub platforms: Vec<String>,
    pub files: Vec<PackFile>,
}

impl Pack {
    /// What all its files take.
    pub fn size(&self) -> u64 {
        self.files.iter().map(|f| f.size).sum()
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Catalog {
    pub version: u64,
    #[serde(default)]
    pub built: String,
    pub packs: Vec<Pack>,
}

fn sha256(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

fn is_slug(text: &str, most: usize) -> bool {
    !text.is_empty()
        && text.len() <= most
        && text
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
        && !text.starts_with('-')
        && !text.ends_with('-')
}

fn is_version(text: &str) -> bool {
    !text.is_empty()
        && text.len() <= 32
        && text.as_bytes()[0].is_ascii_digit()
        && text
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"._+-".contains(&b))
        && !text.contains("..")
}

/// A relative path that stays inside the pack's folder on every system:
/// plain names joined by `/`, none hidden, reserved or `..`.
fn is_inner_path(path: &str) -> bool {
    if path.is_empty() || path.len() > 200 || path.eq_ignore_ascii_case(ENTRY) {
        return false;
    }
    path.split('/').all(|part| {
        !part.is_empty()
            && part.len() <= 100
            && !part.starts_with('.')
            && !part.ends_with('.')
            && part
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b))
            && !is_reserved_on_windows(part)
    })
}

fn is_reserved_on_windows(part: &str) -> bool {
    let stem = part.split('.').next().unwrap_or("").to_ascii_uppercase();
    matches!(stem.as_str(), "CON" | "PRN" | "AUX" | "NUL")
        || (stem.len() == 4
            && (stem.starts_with("COM") || stem.starts_with("LPT"))
            && stem.as_bytes()[3].is_ascii_digit())
}

fn host_of(url: &str) -> Option<&str> {
    let rest = url.strip_prefix("https://")?;
    let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let host = &rest[..end];
    if host.is_empty() || host.contains(['@', ':']) {
        return None;
    }
    Some(host)
}

fn is_hex64(text: &str) -> bool {
    text.len() == 64
        && text
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// What is wrong with [pack], if anything.
pub fn check_pack(pack: &Pack) -> Vec<String> {
    let mut problems = Vec::new();
    let id = &pack.id;
    if !is_slug(id, 64) {
        problems.push(format!(
            "the pack id {id:?} is not lowercase letters, digits and dashes"
        ));
    }
    if !is_version(&pack.version) {
        problems.push(format!(
            "{id}: the version {:?} is not a version",
            pack.version
        ));
    }
    if !pack.min_app.is_empty() && !is_version(&pack.min_app) {
        problems.push(format!("{id}: minApp {:?} is not a version", pack.min_app));
    }
    if pack.title.get("en").is_none_or(|t| t.trim().is_empty()) {
        problems.push(format!("{id}: no English title"));
    }
    let texts = pack.title.iter().chain(pack.description.iter());
    for (tag, value) in texts {
        if tag.is_empty() || tag.len() > 16 || value.len() > 2000 {
            problems.push(format!("{id}: a title or description is too long"));
            break;
        }
    }
    if pack.license.trim().is_empty() || pack.license.len() > 200 {
        problems.push(format!("{id}: no license"));
    }
    if pack.notice.len() > 20_000 {
        problems.push(format!("{id}: the notice is too long"));
    }
    if !pack.source.is_empty() && host_of(&pack.source).is_none() {
        problems.push(format!("{id}: the source is not an https address"));
    }
    if pack.platforms.iter().any(|p| !is_slug(p, 32)) {
        problems.push(format!("{id}: a platform is not like windows-x64"));
    }
    if pack.files.is_empty() || pack.files.len() > MOST_FILES {
        problems.push(format!("{id}: it needs 1 to {MOST_FILES} files"));
    }
    let mut paths = HashSet::new();
    for file in &pack.files {
        let path = &file.path;
        if !is_inner_path(path) {
            problems.push(format!(
                "{id}: the file path {path:?} is not a plain relative path"
            ));
        }
        // Windows and macOS folders ignore case.
        if !paths.insert(path.to_ascii_lowercase()) {
            problems.push(format!("{id}: {path} is listed twice"));
        }
        if !is_hex64(&file.sha256) {
            problems.push(format!("{id}: {path} has no lowercase SHA-256"));
        }
        if file.size == 0 || file.size > MOST_BYTES {
            problems.push(format!("{id}: {path} has no size or is over 8 GiB"));
        }
        let allowed = match pack.kind {
            Kind::Runtime => file.url.starts_with(OWN_RELEASES) && host_of(&file.url).is_some(),
            _ => host_of(&file.url).is_some_and(|h| HOSTS.contains(&h)),
        };
        if !allowed {
            problems.push(format!(
                "{id}: {path} is not downloaded from an allowed address"
            ));
        }
    }
    if pack.size() > MOST_BYTES {
        problems.push(format!("{id}: the pack is over 8 GiB"));
    }
    problems
}

/// What is wrong with [catalog], if anything.
pub fn check(catalog: &Catalog) -> Vec<String> {
    let mut problems = Vec::new();
    if catalog.packs.len() > MOST_PACKS {
        problems.push(format!("more than {MOST_PACKS} packs"));
    }
    let mut ids = HashSet::new();
    for pack in &catalog.packs {
        problems.extend(check_pack(pack));
        if !ids.insert(pack.id.as_str()) {
            problems.push(format!("{} is listed twice", pack.id));
        }
    }
    problems
}

/// Reads [json] as a catalog without a signature, for the tool that builds
/// one. Answers its problems when it does not hold together.
pub fn parse(json: &[u8]) -> Result<Catalog, Vec<String>> {
    let catalog: Catalog =
        serde_json::from_slice(json).map_err(|e| vec![format!("it does not read: {e}")])?;
    let problems = check(&catalog);
    if problems.is_empty() {
        Ok(catalog)
    } else {
        Err(problems)
    }
}

/// Reads one catalog entry, such as an installed pack's `pack.json`, and
/// answers it when it holds together.
pub fn read_entry(json: &[u8]) -> Result<Pack, String> {
    let pack: Pack = serde_json::from_slice(json).map_err(|e| e.to_string())?;
    match check_pack(&pack).into_iter().next() {
        None => Ok(pack),
        Some(problem) => Err(problem),
    }
}

/// Reads [json] after checking [signature] against it with [keys].
fn read_signed(keys: &[u8], json: &[u8], signature: &[u8]) -> Result<Catalog, String> {
    if !signing::verify_with(keys, NAME, &sha256(json), signature) {
        return Err("the signature does not match".into());
    }
    parse(json).map_err(|problems| problems.into_iter().next().unwrap_or_default())
}

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

fn kept_with(keys: &[u8], folder: &Path) -> Option<Catalog> {
    let kept = std::fs::read(folder.join(KEPT)).ok()?;
    let (json, signature) = split(&kept)?;
    read_signed(keys, json, signature).ok()
}

/// The catalog kept in [folder], when it still verifies.
pub fn current(folder: &Path) -> Option<Catalog> {
    kept_with(signing::PUBLIC_KEYS, folder)
}

/// What taking a download did.
#[derive(Debug, PartialEq, Serialize)]
pub struct Taken {
    pub version: u64,
    pub packs: usize,
    /// False when it is not newer than the catalog kept.
    pub newer: bool,
}

/// Checks the downloaded [json] and [signature] and, when newer than the
/// catalog kept in [folder], keeps both there in one file.
pub fn take(json: &[u8], signature: &[u8], folder: &Path) -> Result<Taken, String> {
    take_with(signing::PUBLIC_KEYS, json, signature, folder)
}

fn take_with(keys: &[u8], json: &[u8], signature: &[u8], folder: &Path) -> Result<Taken, String> {
    let catalog = read_signed(keys, json, signature)?;
    let kept = kept_with(keys, folder).map_or(0, |c| c.version);
    if catalog.version < kept {
        return Err(format!(
            "it is older ({}) than the catalog kept ({kept})",
            catalog.version
        ));
    }
    let taken = Taken {
        version: catalog.version,
        packs: catalog.packs.len(),
        newer: catalog.version > kept,
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

#[derive(Deserialize)]
struct FolderAsk {
    folder: String,
}

/// The catalog kept, `{version, built, packs}`, with version 0 and no
/// packs when there is none; [json] is `{"folder": "..."}`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_packs_in(json: *const u8, length: usize) -> *mut c_char {
    // SAFETY: The caller passes `json` pointing at `length` readable bytes, as this function
    // requires.
    let folder = serde_json::from_str::<FolderAsk>(unsafe { text(json, length) })
        .map(|a| a.folder)
        .unwrap_or_default();
    let catalog = (!folder.is_empty())
        .then(|| current(Path::new(&folder)))
        .flatten()
        .unwrap_or(Catalog {
            version: 0,
            built: String::new(),
            packs: Vec::new(),
        });
    give_json(&catalog)
}

/// Takes a downloaded catalog, [json] being `{file, signature, folder}`
/// (paths). Answers [Taken] or `{"error": "..."}`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_packs_take(json: *const u8, length: usize) -> *mut c_char {
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
    // SAFETY: The caller passes `json` pointing at `length` readable bytes, as this function
    // requires.
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

/// Checks one catalog entry, such as an installed pack's `pack.json`, so
/// the app never trusts a path or address from a file it did not verify.
/// Answers the pack or `{"error": "..."}`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_pack_check(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Serialize)]
    struct Failed {
        error: String,
    }
    // SAFETY: The caller passes `json` pointing at `length` readable bytes, as this function
    // requires.
    match read_entry(unsafe { text(json, length) }.as_bytes()) {
        Ok(pack) => give_json(&pack),
        Err(error) => give_json(&Failed { error }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SECRET: [u8; 64] = [9; 64];

    fn keys() -> Vec<u8> {
        signing::public_keys(&SECRET)
    }

    fn signed(json: &[u8]) -> Vec<u8> {
        signing::sign(&SECRET, NAME, &sha256(json))
    }

    fn folder(name: &str) -> std::path::PathBuf {
        let folder =
            std::env::temp_dir().join(format!("lumtub-packs-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&folder);
        folder
    }

    fn pack(id: &str) -> Pack {
        Pack {
            id: id.into(),
            version: "1.0.0".into(),
            kind: Kind::Shader,
            title: BTreeMap::from([("en".into(), "Upscaling shaders".into())]),
            description: BTreeMap::new(),
            license: "MIT".into(),
            notice: String::new(),
            source: "https://github.com/example/shaders".into(),
            min_app: "0.2.59".into(),
            platforms: Vec::new(),
            files: vec![PackFile {
                path: "glsl/FSR.glsl".into(),
                url: "https://github.com/0x696c757a696f/lumtub/releases/download/packs/FSR.glsl"
                    .into(),
                sha256: "a".repeat(64),
                size: 1234,
            }],
        }
    }

    fn catalog(version: u64, packs: Vec<Pack>) -> Vec<u8> {
        serde_json::to_vec(&Catalog {
            version,
            built: "2026-11-20T00:00:00Z".into(),
            packs,
        })
        .unwrap()
    }

    #[test]
    fn a_good_catalog_reads() {
        let json = catalog(5, vec![pack("shaders-upscale")]);
        let read = read_signed(&keys(), &json, &signed(&json)).unwrap();
        assert_eq!(read.packs[0].size(), 1234);
        assert_eq!(read.packs[0].min_app, "0.2.59");
    }

    #[test]
    fn signatures_are_checked() {
        let json = catalog(5, vec![pack("shaders-upscale")]);
        assert_eq!(
            read_signed(signing::PUBLIC_KEYS, &json, &signed(&json))
                .err()
                .as_deref(),
            Some("the signature does not match")
        );
        let mut changed = json.clone();
        changed[12] ^= 1;
        assert!(read_signed(&keys(), &changed, &signed(&json)).is_err());
    }

    #[test]
    fn paths_stay_inside_the_pack() {
        for bad in [
            "../evil.dll",
            "a/../../b",
            "/etc/passwd",
            "C:/x",
            "a\\b",
            ".hidden",
            "a//b",
            "",
            "pack.json",
            "PACK.JSON",
            "con.txt",
            "dir/NUL",
            "COM1.glsl",
            "end.",
        ] {
            assert!(!is_inner_path(bad), "{bad}");
        }
        for good in ["FSR.glsl", "models/ggml-small.bin", "a-b_c.1/d"] {
            assert!(is_inner_path(good), "{good}");
        }
    }

    #[test]
    fn addresses_are_limited() {
        let mut p = pack("x");
        p.files[0].url = "http://github.com/a".into();
        assert!(!check_pack(&p).is_empty());
        p.files[0].url = "https://evil.example/a".into();
        assert!(!check_pack(&p).is_empty());
        p.files[0].url = "https://github.com@evil.example/a".into();
        assert!(!check_pack(&p).is_empty());
        p.files[0].url = "https://huggingface.co/org/model/resolve/main/m.gguf".into();
        assert!(check_pack(&p).is_empty());
        // A runtime only from Lumtub's own releases.
        p.kind = Kind::Runtime;
        assert!(!check_pack(&p).is_empty());
        p.files[0].url =
            "https://github.com/0x696c757a696f/lumtub/releases/download/packs/lumtub_ai.dll".into();
        assert!(check_pack(&p).is_empty());
    }

    #[test]
    fn bad_entries_are_refused() {
        let mut p = pack("Bad_Id");
        assert!(!check_pack(&p).is_empty());
        p = pack("x");
        p.files[0].sha256 = "A".repeat(64);
        assert!(!check_pack(&p).is_empty());
        p = pack("x");
        p.files[0].size = 0;
        assert!(!check_pack(&p).is_empty());
        p = pack("x");
        p.files.push(p.files[0].clone());
        p.files[1].path = "GLSL/fsr.glsl".into();
        assert!(!check_pack(&p).is_empty());
        p = pack("x");
        p.title.clear();
        assert!(!check_pack(&p).is_empty());
        p = pack("x");
        p.version = "..".into();
        assert!(!check_pack(&p).is_empty());
        let twice = Catalog {
            version: 1,
            built: String::new(),
            packs: vec![pack("x"), pack("x")],
        };
        assert!(!check(&twice).is_empty());
        assert!(parse(br#"{"version":1,"packs":[],"extra":1}"#).is_err());
    }

    #[test]
    fn a_taken_catalog_is_kept_and_never_rolled_back() {
        let dir = folder("take");
        let new = catalog(10, vec![pack("a")]);
        let taken = take_with(&keys(), &new, &signed(&new), &dir).unwrap();
        assert!(taken.newer);
        assert_eq!(kept_with(&keys(), &dir).unwrap().version, 10);
        let same = take_with(&keys(), &new, &signed(&new), &dir).unwrap();
        assert!(!same.newer);
        let old = catalog(9, vec![]);
        assert!(take_with(&keys(), &old, &signed(&old), &dir).is_err());
        assert_eq!(kept_with(&keys(), &dir).unwrap().version, 10);
        let newer = catalog(11, vec![]);
        assert!(
            take_with(&keys(), &newer, &signed(&newer), &dir)
                .unwrap()
                .newer
        );
        assert!(kept_with(&keys(), &dir).unwrap().packs.is_empty());
        // The shipped keys do not accept the test signature.
        assert!(current(&dir).is_none());
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_damaged_kept_file_is_ignored() {
        let dir = folder("damaged");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join(KEPT), [255, 255, 255, 255, 1]).unwrap();
        assert!(kept_with(&keys(), &dir).is_none());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
