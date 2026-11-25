//! The OpenPGP signature on yt-dlp's `SHA2-256SUMS`. yt-dlp signs that file
//! for every release, nightly builds included, with one RSA-4096 key; its
//! public key ships here (`keys/yt-dlp.pub`, the bare public-key packet) and
//! is pinned by fingerprint. A yt-dlp download is checked against the sums
//! only once their signature holds, so replacing a release's files on
//! GitHub is not enough to run other code on users' computers.
//!
//! Only what that one signature needs is read: a version 4 signature packet
//! over a binary document, made by RSA with SHA-256, SHA-384 or SHA-512, and
//! checked with ring (public-key operations only).
//!
//! Should yt-dlp move to a new key, updates stop (the installed yt-dlp keeps
//! working) until `keys/yt-dlp.pub` and [FINGERPRINT] here and in
//! `.github/scripts/ytdlp_sums_verify.py` are replaced.

use serde::{Deserialize, Serialize};
use sha1::{Digest, Sha1};
use std::os::raw::c_char;

use crate::taste::{give_json, outside};

/// The public-key packet of "Simon Sawicki (yt-dlp signing key)".
const PUBLIC_KEY: &[u8] = include_bytes!("../keys/yt-dlp.pub");
/// Its v4 fingerprint, as yt-dlp's README and public.key give it.
const FINGERPRINT: &str = "AC0CBBE6848D6A873464AF4E57CF65933B5A7581";
/// The largest signature file read; a 4096-bit one is under 600 bytes.
const MAX_SIGNATURE: usize = 4096;
/// How far a nightly's signature may be from the date in its tag.
const TAG_SLACK: i64 = 3 * 24 * 3600;

/// One OpenPGP packet's tag and body, and the rest of [data].
fn packet(data: &[u8]) -> Result<(u8, &[u8], &[u8]), String> {
    let first = *data.first().ok_or("No OpenPGP packet")?;
    if first & 0x80 == 0 {
        return Err("Not an OpenPGP packet".into());
    }
    let (tag, length, start): (u8, usize, usize) = if first & 0x40 != 0 {
        let tag = first & 0x3f;
        let b = data.get(1..).ok_or("Truncated packet")?;
        match *b.first().ok_or("Truncated packet")? {
            n @ 0..=191 => (tag, n as usize, 2),
            n @ 192..=223 => {
                let low = *b.get(1).ok_or("Truncated packet")?;
                (tag, ((n as usize - 192) << 8) + low as usize + 192, 3)
            }
            255 => {
                let bytes: [u8; 4] = b.get(1..5).ok_or("Truncated packet")?.try_into().unwrap();
                (tag, u32::from_be_bytes(bytes) as usize, 6)
            }
            _ => return Err("Partial packet lengths are not supported".into()),
        }
    } else {
        let tag = (first >> 2) & 0x0f;
        match first & 3 {
            0 => (tag, *data.get(1).ok_or("Truncated packet")? as usize, 2),
            1 => {
                let bytes: [u8; 2] = data
                    .get(1..3)
                    .ok_or("Truncated packet")?
                    .try_into()
                    .unwrap();
                (tag, u16::from_be_bytes(bytes) as usize, 3)
            }
            2 => {
                let bytes: [u8; 4] = data
                    .get(1..5)
                    .ok_or("Truncated packet")?
                    .try_into()
                    .unwrap();
                (tag, u32::from_be_bytes(bytes) as usize, 5)
            }
            _ => return Err("Indeterminate packet lengths are not supported".into()),
        }
    };
    let end = start.checked_add(length).ok_or("Packet too long")?;
    let body = data.get(start..end).ok_or("Truncated packet")?;
    Ok((tag, body, &data[end..]))
}

/// An OpenPGP multiprecision integer at the start of [data], without its
/// leading zero bytes, and the rest.
fn mpi(data: &[u8]) -> Result<(&[u8], &[u8]), String> {
    let bits: [u8; 2] = data.get(..2).ok_or("Truncated number")?.try_into().unwrap();
    let length = (u16::from_be_bytes(bits) as usize).div_ceil(8);
    let value = data.get(2..2 + length).ok_or("Truncated number")?;
    let start = value.iter().position(|&b| b != 0).unwrap_or(value.len());
    Ok((&value[start..], &data[2 + length..]))
}

/// The pinned key's RSA modulus and exponent, after checking the packet
/// is the one with [FINGERPRINT].
fn public_key() -> Result<(&'static [u8], &'static [u8]), String> {
    let (tag, body, rest) = packet(PUBLIC_KEY)?;
    if tag != 6 || !rest.is_empty() || body.first() != Some(&4) || body.get(5) != Some(&1) {
        return Err("The built-in yt-dlp key is not a v4 RSA public key".into());
    }
    let mut hasher = Sha1::new();
    hasher.update([0x99]);
    hasher.update((body.len() as u16).to_be_bytes());
    hasher.update(body);
    let fingerprint: String = hasher
        .finalize()
        .iter()
        .map(|b| format!("{b:02X}"))
        .collect();
    if fingerprint != FINGERPRINT {
        return Err("The built-in yt-dlp key has the wrong fingerprint".into());
    }
    let (n, rest) = mpi(&body[6..])?;
    let (e, rest) = mpi(rest)?;
    if !rest.is_empty() {
        return Err("The built-in yt-dlp key has extra data".into());
    }
    Ok((n, e))
}

/// Seconds since 1970 of the date a nightly tag such as `2026.11.24.233816`
/// starts with; None for any other tag.
fn tag_time(tag: &str) -> Option<i64> {
    let mut parts = tag.split('.');
    let year = parts.next()?;
    let month = parts.next()?;
    let day = parts.next()?;
    if year.len() != 4 || month.len() != 2 || day.len() != 2 {
        return None;
    }
    crate::update::unix_seconds(&format!("{year}-{month}-{day}T00:00:00Z"))
}

/// Checks [signature] (the binary `SHA2-256SUMS.sig`) on [sums] with the
/// pinned key. Answers the signature's creation time in seconds since 1970.
pub fn verify(sums: &[u8], signature: &[u8], tag: Option<&str>) -> Result<i64, String> {
    if signature.len() > MAX_SIGNATURE {
        return Err("The signature file is too large".into());
    }
    let (tag_number, body, rest) = packet(signature)?;
    if tag_number != 2 || !rest.is_empty() {
        return Err("The signature file holds no single signature".into());
    }
    let header = body.get(..6).ok_or("Truncated signature")?;
    let (version, class, algorithm, hash) = (header[0], header[1], header[2], header[3]);
    if version != 4 {
        return Err(format!("Unsupported signature version {version}"));
    }
    if class != 0x00 {
        return Err("The signature is not over a binary document".into());
    }
    if algorithm != 1 {
        return Err("The signature is not an RSA signature".into());
    }
    let scheme: &'static ring::signature::RsaParameters = match hash {
        8 => &ring::signature::RSA_PKCS1_2048_8192_SHA256,
        9 => &ring::signature::RSA_PKCS1_2048_8192_SHA384,
        10 => &ring::signature::RSA_PKCS1_2048_8192_SHA512,
        _ => return Err(format!("Unsupported signature hash {hash}")),
    };
    let hashed_length = u16::from_be_bytes([header[4], header[5]]) as usize;
    let hashed_end = 6 + hashed_length;
    let hashed = body.get(6..hashed_end).ok_or("Truncated signature")?;
    let unhashed_length = u16::from_be_bytes(
        body.get(hashed_end..hashed_end + 2)
            .ok_or("Truncated signature")?
            .try_into()
            .unwrap(),
    ) as usize;
    let after_unhashed = hashed_end + 2 + unhashed_length;
    // Two bytes of the digest, then the signature value.
    let (value, rest) = mpi(body
        .get(after_unhashed + 2..)
        .ok_or("Truncated signature")?)?;
    if !rest.is_empty() {
        return Err("The signature has extra data".into());
    }
    let created = created_time(hashed)?;
    if let Some(at) = tag.and_then(tag_time)
        && (created - at).abs() > TAG_SLACK + 24 * 3600
    {
        return Err("The signature was made long before or after this release".into());
    }
    let (n, e) = public_key()?;
    // The value is as long as the modulus, its leading zeros put back.
    if value.len() > n.len() {
        return Err("The signature value is too long".into());
    }
    let mut padded = vec![0u8; n.len() - value.len()];
    padded.extend_from_slice(value);
    // What was signed: the document, then the signature's own hashed part
    // and its v4 trailer.
    let signed_part = &body[..hashed_end];
    let mut message = Vec::with_capacity(sums.len() + signed_part.len() + 6);
    message.extend_from_slice(sums);
    message.extend_from_slice(signed_part);
    message.extend_from_slice(&[0x04, 0xff]);
    message.extend_from_slice(&(signed_part.len() as u32).to_be_bytes());
    ring::signature::RsaPublicKeyComponents { n, e }
        .verify(scheme, &message, &padded)
        .map_err(|_| "The yt-dlp checksums' signature does not match".to_string())?;
    Ok(created)
}

/// The creation time in the hashed subpackets (type 2), which a v4
/// signature must have. Unknown critical subpackets are refused.
fn created_time(mut subpackets: &[u8]) -> Result<i64, String> {
    let mut created = None;
    while !subpackets.is_empty() {
        let (length, start): (usize, usize) = match subpackets[0] {
            n @ 0..=191 => (n as usize, 1),
            n @ 192..=254 => {
                let low = *subpackets.get(1).ok_or("Truncated subpacket")?;
                (((n as usize - 192) << 8) + low as usize + 192, 2)
            }
            255 => {
                let bytes: [u8; 4] = subpackets
                    .get(1..5)
                    .ok_or("Truncated subpacket")?
                    .try_into()
                    .unwrap();
                (u32::from_be_bytes(bytes) as usize, 5)
            }
        };
        let end = start.checked_add(length).ok_or("Subpacket too long")?;
        let data = subpackets.get(start..end).ok_or("Truncated subpacket")?;
        let (&kind, value) = data.split_first().ok_or("Empty subpacket")?;
        match kind & 0x7f {
            2 => {
                let bytes: [u8; 4] = value.try_into().map_err(|_| "Bad creation time")?;
                created = Some(u32::from_be_bytes(bytes) as i64);
            }
            // Issuer fingerprint, issuer key id, notations and other
            // informational subpackets.
            _ if kind & 0x80 == 0 => {}
            // Signature expiration: yt-dlp's never expire; one that does is
            // refused rather than half-read.
            other => return Err(format!("Unknown critical signature subpacket {other}")),
        }
        subpackets = &subpackets[end..];
    }
    created.ok_or_else(|| "The signature has no creation time".into())
}

fn hex(text: &str) -> Option<Vec<u8>> {
    if !text.len().is_multiple_of(2) || text.len() > MAX_SIGNATURE * 2 {
        return None;
    }
    (0..text.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(text.get(i..i + 2)?, 16).ok())
        .collect()
}

/// Checks yt-dlp's `SHA2-256SUMS` against its `.sig`. [json] is
/// `{sums, signature, tag}`: the sums file's text, the signature file in
/// hex, and the release's tag. Answers `{"ok": true, "created": seconds}` or
/// `{"error": "..."}`.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_ytdlp_sums_verify(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        sums: String,
        signature: String,
        tag: Option<String>,
    }
    #[derive(Serialize)]
    struct Answer {
        #[serde(skip_serializing_if = "Option::is_none")]
        ok: Option<bool>,
        #[serde(skip_serializing_if = "Option::is_none")]
        created: Option<i64>,
        #[serde(skip_serializing_if = "Option::is_none")]
        error: Option<String>,
    }
    let result = serde_json::from_str::<Ask>(unsafe { outside(json, length) })
        .map_err(|e| e.to_string())
        .and_then(|ask| {
            let signature = hex(&ask.signature).ok_or("The signature is not hex")?;
            verify(ask.sums.as_bytes(), &signature, ask.tag.as_deref())
        });
    give_json(&match result {
        Ok(created) => Answer {
            ok: Some(true),
            created: Some(created),
            error: None,
        },
        Err(error) => Answer {
            ok: None,
            created: None,
            error: Some(error),
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const SUMS: &[u8] = include_bytes!("../testdata/yt-dlp-SHA2-256SUMS");
    const SIGNATURE: &[u8] = include_bytes!("../testdata/yt-dlp-SHA2-256SUMS.sig");

    #[test]
    fn the_built_in_key_is_yt_dlps() {
        let (n, e) = public_key().unwrap();
        assert_eq!(n.len(), 512);
        assert_eq!(e, [1, 0, 1]);
    }

    #[test]
    fn a_real_nightly_signature_holds() {
        let created = verify(SUMS, SIGNATURE, Some("2026.11.24.232900")).unwrap();
        assert_eq!(created, 1_795_563_123);
        // Without a tag, or with one that is not a date, only the signature counts.
        assert!(verify(SUMS, SIGNATURE, None).is_ok());
        assert!(verify(SUMS, SIGNATURE, Some("nightly")).is_ok());
    }

    #[test]
    fn a_changed_sums_file_fails() {
        let mut sums = SUMS.to_vec();
        sums[0] ^= 1;
        assert!(verify(&sums, SIGNATURE, None).is_err());
        let mut longer = SUMS.to_vec();
        longer.extend_from_slice(b"00  extra\n");
        assert!(verify(&longer, SIGNATURE, None).is_err());
    }

    #[test]
    fn a_changed_signature_fails() {
        for at in [10, SIGNATURE.len() / 2, SIGNATURE.len() - 1] {
            let mut signature = SIGNATURE.to_vec();
            signature[at] ^= 0x40;
            assert!(verify(SUMS, &signature, None).is_err(), "byte {at}");
        }
        assert!(verify(SUMS, &SIGNATURE[..SIGNATURE.len() - 1], None).is_err());
        assert!(verify(SUMS, &[], None).is_err());
    }

    #[test]
    fn an_old_signature_under_a_new_tag_fails() {
        assert!(verify(SUMS, SIGNATURE, Some("2026.12.20.000000")).is_err());
        assert!(verify(SUMS, SIGNATURE, Some("2026.10.01.000000")).is_err());
    }

    #[test]
    fn the_ffi_answers_json() {
        let signature: String = SIGNATURE.iter().map(|b| format!("{b:02x}")).collect();
        let ask = serde_json::json!({"sums": std::str::from_utf8(SUMS).unwrap(), "signature": signature, "tag": "2026.11.24.232900"}).to_string();
        let answer = unsafe { lumtub_ytdlp_sums_verify(ask.as_ptr(), ask.len()) };
        let text = unsafe { std::ffi::CString::from_raw(answer) }
            .into_string()
            .unwrap();
        assert_eq!(text, r#"{"ok":true,"created":1795563123}"#);
        let bad = serde_json::json!({"sums": "x", "signature": signature}).to_string();
        let answer = unsafe { lumtub_ytdlp_sums_verify(bad.as_ptr(), bad.len()) };
        let text = unsafe { std::ffi::CString::from_raw(answer) }
            .into_string()
            .unwrap();
        assert!(text.contains("error"), "{text}");
    }
}
