//! Signatures on Lumtub's own update packages. Each package is signed twice,
//! with Ed25519 and with ML-DSA-65 (FIPS 204), and an update installs only
//! when both signatures hold: a break of either scheme alone is not enough
//! to push a package to users. The signature covers the file's name and
//! SHA-256, so a package cannot pass as one for another architecture.
//!
//! The release workflow signs with the private seeds in a repository
//! secret (see the `lumtub-sign` binary); the public keys ship in the core.

use ed25519_dalek::Signer as _;
use ml_dsa::{EncodedVerifyingKey, ExpandedSigningKey, MlDsa65, Signature, VerifyingKey};
use serde::{Deserialize, Serialize};
use std::os::raw::c_char;

use crate::taste::{give_json, text};

/// ML-DSA's context string; for Ed25519 the message's first line does the
/// same, keeping these signatures apart from anything else the keys sign.
const CONTEXT: &[u8] = b"lumtub update";
const ED25519_LENGTH: usize = 64;
/// An ML-DSA-65 signature's length.
const ML_DSA_LENGTH: usize = 3309;
/// A `.sig` file: the Ed25519 signature, then the ML-DSA-65 one.
pub const SIGNATURE_LENGTH: usize = ED25519_LENGTH + ML_DSA_LENGTH;
/// The public keys: Ed25519 (32 bytes), then ML-DSA-65 (1952 bytes).
pub const PUBLIC_KEYS: &[u8] = include_bytes!("../keys/update.pub");

/// What both schemes sign for the package [name] with SHA-256 [sha256].
pub fn message(name: &str, sha256: &str) -> Vec<u8> {
    format!("lumtub update v1\n{name}\n{}", sha256.to_ascii_lowercase()).into_bytes()
}

fn ml_dsa_key(seed: &[u8; 32]) -> ExpandedSigningKey<MlDsa65> {
    ExpandedSigningKey::from_seed(&(*seed).into())
}

/// The public keys of [secret], the Ed25519 seed then the ML-DSA-65 seed.
pub fn public_keys(secret: &[u8; 64]) -> Vec<u8> {
    let (ed, ml) = split(secret);
    let mut keys = ed25519_dalek::SigningKey::from_bytes(ed).verifying_key().to_bytes().to_vec();
    keys.extend_from_slice(&ml_dsa_key(ml).verifying_key().encode());
    keys
}

fn split(secret: &[u8; 64]) -> (&[u8; 32], &[u8; 32]) {
    let (ed, ml) = secret.split_at(32);
    (ed.try_into().unwrap(), ml.try_into().unwrap())
}

/// The `.sig` contents for the package [name] with SHA-256 [sha256].
pub fn sign(secret: &[u8; 64], name: &str, sha256: &str) -> Vec<u8> {
    let (ed, ml) = split(secret);
    let message = message(name, sha256);
    let mut signature = ed25519_dalek::SigningKey::from_bytes(ed).sign(&message).to_bytes().to_vec();
    signature.extend_from_slice(&ml_dsa_key(ml).sign_deterministic(&message, CONTEXT).unwrap().encode());
    signature
}

/// Whether [signature] holds for the package [name] with SHA-256 [sha256]
/// under both of [keys].
pub fn verify_with(keys: &[u8], name: &str, sha256: &str, signature: &[u8]) -> bool {
    if keys.len() != 32 + 1952 || signature.len() != SIGNATURE_LENGTH {
        return false;
    }
    let (ed_key, ml_key) = keys.split_at(32);
    let (ed_signature, ml_signature) = signature.split_at(ED25519_LENGTH);
    let message = message(name, sha256);
    let Ok(ed_key) = ed25519_dalek::VerifyingKey::from_bytes(ed_key.try_into().unwrap()) else {
        return false;
    };
    let ed_signature = ed25519_dalek::Signature::from_bytes(ed_signature.try_into().unwrap());
    let ed_ok = ed_key.verify_strict(&message, &ed_signature).is_ok();
    let Ok(ml_key) = EncodedVerifyingKey::<MlDsa65>::try_from(ml_key) else {
        return false;
    };
    let ml_ok = Signature::<MlDsa65>::try_from(ml_signature).is_ok_and(|ml_signature| VerifyingKey::<MlDsa65>::decode(&ml_key).verify_with_context(&message, CONTEXT, &ml_signature));
    ed_ok && ml_ok
}

/// Checks the downloaded package [file] (its name as the release lists it,
/// [name]) against the `.sig` file [signature].
pub fn verify_file(file: &str, name: &str, signature: &str) -> Result<(), String> {
    let signature = std::fs::read(signature).map_err(|e| format!("Could not read the signature: {e}"))?;
    let sha256 = crate::hashes::file_sha256(file).map_err(|e| format!("Could not read the package: {e}"))?;
    if verify_with(PUBLIC_KEYS, name, &sha256, &signature) { Ok(()) } else { Err("The update's signature does not match".into()) }
}

/// Checks a downloaded update, [json] being `{file, name, signature}`
/// (paths, and the package's name as the release lists it). Answers JSON
/// `{"ok": true}` or `{"error": "..."}`. It reads the whole package, so
/// call it off the UI thread.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_update_verify(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        file: String,
        name: String,
        signature: String,
    }
    #[derive(Serialize)]
    struct Answer {
        #[serde(skip_serializing_if = "Option::is_none")]
        ok: Option<bool>,
        #[serde(skip_serializing_if = "Option::is_none")]
        error: Option<String>,
    }
    let answer = match serde_json::from_str::<Ask>(unsafe { text(json, length) }) {
        Ok(ask) => match verify_file(&ask.file, &ask.name, &ask.signature) {
            Ok(()) => Answer { ok: Some(true), error: None },
            Err(error) => Answer { ok: None, error: Some(error) },
        },
        Err(e) => Answer { ok: None, error: Some(e.to_string()) },
    };
    give_json(&answer)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SECRET: [u8; 64] = [7; 64];
    const SHA: &str = "9F86D081884C7D659A2FEAA0C55AD015A3BF4F1B2B0B822CD15D6C15B0F00A08";
    const NAME: &str = "Lumtub_0.2.4-abcdef0_windows-x64-setup.exe";

    #[test]
    fn a_signature_holds_for_its_own_package() {
        let keys = public_keys(&SECRET);
        let signature = sign(&SECRET, NAME, SHA);
        assert_eq!(signature.len(), SIGNATURE_LENGTH);
        assert!(verify_with(&keys, NAME, SHA, &signature));
        assert!(verify_with(&keys, NAME, &SHA.to_lowercase(), &signature));
    }

    #[test]
    fn another_package_or_architecture_fails() {
        let keys = public_keys(&SECRET);
        let signature = sign(&SECRET, NAME, SHA);
        assert!(!verify_with(&keys, &NAME.replace("x64", "arm64"), SHA, &signature));
        assert!(!verify_with(&keys, NAME, &SHA.replace('9', "8"), &signature));
    }

    #[test]
    fn both_signatures_must_hold() {
        let keys = public_keys(&SECRET);
        let good = sign(&SECRET, NAME, SHA);
        let other = sign(&SECRET, NAME, &SHA.replace('9', "8"));
        let mut ed_only = good[..ED25519_LENGTH].to_vec();
        ed_only.extend_from_slice(&other[ED25519_LENGTH..]);
        let mut ml_only = other[..ED25519_LENGTH].to_vec();
        ml_only.extend_from_slice(&good[ED25519_LENGTH..]);
        assert!(!verify_with(&keys, NAME, SHA, &ed_only));
        assert!(!verify_with(&keys, NAME, SHA, &ml_only));
        assert!(!verify_with(&keys, NAME, SHA, &good[..SIGNATURE_LENGTH - 1]));
    }

    #[test]
    fn another_key_fails() {
        let signature = sign(&[8; 64], NAME, SHA);
        assert!(!verify_with(&public_keys(&SECRET), NAME, SHA, &signature));
    }

    #[test]
    fn the_shipped_keys_are_whole() {
        assert_eq!(PUBLIC_KEYS.len(), 32 + 1952);
        assert!(ed25519_dalek::VerifyingKey::from_bytes(PUBLIC_KEYS[..32].try_into().unwrap()).is_ok());
    }

    #[test]
    fn checks_a_file() {
        let folder = std::env::temp_dir().join(format!("lumtub-sign-{}", std::process::id()));
        std::fs::create_dir_all(&folder).unwrap();
        let file = folder.join("package.exe");
        std::fs::write(&file, b"test").unwrap();
        let signature = folder.join("package.exe.sig");
        std::fs::write(&signature, vec![0; SIGNATURE_LENGTH]).unwrap();
        let result = verify_file(file.to_str().unwrap(), NAME, signature.to_str().unwrap());
        std::fs::remove_dir_all(&folder).unwrap();
        assert_eq!(result, Err("The update's signature does not match".into()));
    }
}
