//! Signs Lumtub's update packages for the release workflow.
//!
//! `lumtub-sign FILE...` writes FILE.sig next to each file, with the key in
//! LUMTUB_UPDATE_KEY (128 hex digits: the Ed25519 seed, then the ML-DSA-65
//! seed). `lumtub-sign --public OUT` writes that key's public keys to OUT.

use lumtub_core::{hashes::file_sha256, signing};
use std::path::Path;
use std::process::ExitCode;

fn secret() -> Result<[u8; 64], String> {
    let hex = std::env::var("LUMTUB_UPDATE_KEY").map_err(|_| "LUMTUB_UPDATE_KEY is not set".to_string())?;
    let hex = hex.trim();
    if hex.len() != 128 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("LUMTUB_UPDATE_KEY must be 128 hex digits".into());
    }
    let mut secret = [0; 64];
    for (i, byte) in secret.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16).unwrap();
    }
    Ok(secret)
}

fn run() -> Result<(), String> {
    let secret = secret()?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let [flag, out] = args.as_slice()
        && flag == "--public"
    {
        return std::fs::write(out, signing::public_keys(&secret)).map_err(|e| format!("{out}: {e}"));
    }
    if args.is_empty() {
        return Err("usage: lumtub-sign FILE... | --public OUT".into());
    }
    let keys = signing::public_keys(&secret);
    if keys != signing::PUBLIC_KEYS {
        return Err("LUMTUB_UPDATE_KEY does not match the public keys in keys/update.pub".into());
    }
    for file in &args {
        let name = Path::new(file).file_name().and_then(|n| n.to_str()).ok_or_else(|| format!("{file}: no file name"))?;
        let sha256 = file_sha256(file).map_err(|e| format!("{file}: {e}"))?;
        let signature = signing::sign(&secret, name, &sha256);
        if !signing::verify_with(signing::PUBLIC_KEYS, name, &sha256, &signature) {
            return Err(format!("{file}: the new signature does not verify"));
        }
        std::fs::write(format!("{file}.sig"), signature).map_err(|e| format!("{file}.sig: {e}"))?;
        println!("Signed {name}");
    }
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("lumtub-sign: {e}");
            ExitCode::FAILURE
        }
    }
}
