//! HomeKit pairing with an AirPlay receiver: pair-setup with the PIN the
//! TV shows (once), pair-verify with the keys kept from it (each time), or
//! transient pairing with the fixed PIN some receivers accept.

use super::conn::Conn;
use super::crypto::{hkdf, open, read_tlv, seal, tag, tlv};
use super::srp;
use curve25519_dalek::montgomery::MontgomeryPoint;
use ed25519_dalek::{Signer as _, Verifier as _};

const TRANSIENT_PIN: &str = "3939";

/// What pairing leaves: the device's long-term public key and identifier,
/// and ours. Written as four hex fields joined by colons, as pyatv writes
/// them: device key, our secret key, device id, our id.
#[derive(Debug, Clone, PartialEq)]
pub struct Credentials {
    pub device_key: [u8; 32],
    pub secret: [u8; 32],
    pub device_id: Vec<u8>,
    pub client_id: Vec<u8>,
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02X}")).collect()
}

fn unhex(s: &str) -> Option<Vec<u8>> {
    if !s.len().is_multiple_of(2) {
        return None;
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(s.get(i..i + 2)?, 16).ok())
        .collect()
}

impl Credentials {
    pub fn text(&self) -> String {
        format!(
            "{}:{}:{}:{}",
            hex(&self.device_key),
            hex(&self.secret),
            hex(&self.device_id),
            hex(&self.client_id)
        )
    }

    pub fn parse(text: &str) -> Option<Credentials> {
        let parts: Vec<Vec<u8>> = text.trim().split(':').map(unhex).collect::<Option<_>>()?;
        let [device_key, secret, device_id, client_id] = parts.try_into().ok()?;
        Some(Credentials {
            device_key: device_key.try_into().ok()?,
            secret: secret.try_into().ok()?,
            device_id,
            client_id,
        })
    }
}

fn random<const N: usize>() -> Result<[u8; N], String> {
    let mut out = [0u8; N];
    getrandom::fill(&mut out).map_err(|e| e.to_string())?;
    Ok(out)
}

fn headers(transient: bool) -> Vec<(&'static str, String)> {
    vec![
        ("User-Agent", "AirPlay/320.20".into()),
        ("Connection", "keep-alive".into()),
        ("X-Apple-HKP", if transient { "4" } else { "3" }.into()),
        ("Content-Type", "application/octet-stream".into()),
    ]
}

fn post(
    conn: &mut Conn,
    path: &str,
    body: &[u8],
    transient: bool,
) -> Result<std::collections::HashMap<u8, Vec<u8>>, String> {
    let answer = conn.request("POST", path, "HTTP/1.1", &headers(transient), body)?;
    if answer.code == 470 || answer.code == 401 {
        return Err("the device refused pairing".into());
    }
    if answer.code != 200 {
        return Err(format!("{path} answered {}", answer.code));
    }
    let found = read_tlv(&answer.body);
    if let Some(error) = found.get(&tag::ERROR) {
        return Err(match error.first() {
            Some(2) => "wrong PIN".to_string(),
            Some(3) => "the device asks to wait before pairing again".to_string(),
            Some(5) => "too many tries".to_string(),
            Some(6) | Some(7) => "the device is busy".to_string(),
            other => format!("pairing error {other:?}"),
        });
    }
    Ok(found)
}

/// The first step: the TV shows a PIN. Its salt and public key, for
/// [finish].
pub fn start(conn: &mut Conn) -> Result<(Vec<u8>, Vec<u8>), String> {
    conn.request("POST", "/pair-pin-start", "HTTP/1.1", &headers(false), &[])?;
    let m2 = post(
        conn,
        "/pair-setup",
        &tlv(&[(tag::METHOD, &[0]), (tag::SEQ_NO, &[1])]),
        false,
    )?;
    Ok((
        m2.get(&tag::SALT).cloned().ok_or("no salt")?,
        m2.get(&tag::PUBLIC_KEY).cloned().ok_or("no public key")?,
    ))
}

/// The rest of pair-setup with the PIN the user typed.
pub fn finish(
    conn: &mut Conn,
    salt: &[u8],
    server: &[u8],
    pin: &str,
) -> Result<Credentials, String> {
    let done = srp::exchange(pin, salt, server, &random::<32>()?)?;
    let m4 = post(
        conn,
        "/pair-setup",
        &tlv(&[
            (tag::SEQ_NO, &[3]),
            (tag::PUBLIC_KEY, &done.public),
            (tag::PROOF, &done.proof),
        ]),
        false,
    )?;
    if m4.get(&tag::PROOF) != Some(&done.expected) {
        return Err("wrong PIN".into());
    }
    let secret = random::<32>()?;
    let signing = ed25519_dalek::SigningKey::from_bytes(&secret);
    let public = signing.verifying_key().to_bytes();
    let client_id = uuid().into_bytes();
    let x = hkdf(
        "Pair-Setup-Controller-Sign-Salt",
        "Pair-Setup-Controller-Sign-Info",
        &done.key,
    );
    let signature = signing
        .sign(&[&x[..], &client_id, &public].concat())
        .to_bytes();
    let key = hkdf(
        "Pair-Setup-Encrypt-Salt",
        "Pair-Setup-Encrypt-Info",
        &done.key,
    );
    let inner = tlv(&[
        (tag::IDENTIFIER, &client_id),
        (tag::PUBLIC_KEY, &public),
        (tag::SIGNATURE, &signature),
    ]);
    let m6 = post(
        conn,
        "/pair-setup",
        &tlv(&[
            (tag::SEQ_NO, &[5]),
            (tag::ENCRYPTED_DATA, &seal(&key, b"PS-Msg05", &inner)),
        ]),
        false,
    )?;
    let sealed = m6
        .get(&tag::ENCRYPTED_DATA)
        .ok_or("no answer to the keys")?;
    let found =
        read_tlv(&open(&key, b"PS-Msg06", sealed).ok_or("the device's keys did not decrypt")?);
    let device_id = found.get(&tag::IDENTIFIER).cloned().ok_or("no device id")?;
    let device_key: [u8; 32] = found
        .get(&tag::PUBLIC_KEY)
        .and_then(|k| k.as_slice().try_into().ok())
        .ok_or("no device key")?;
    let device_signature: [u8; 64] = found
        .get(&tag::SIGNATURE)
        .and_then(|k| k.as_slice().try_into().ok())
        .ok_or("no device signature")?;
    let device_x = hkdf(
        "Pair-Setup-Accessory-Sign-Salt",
        "Pair-Setup-Accessory-Sign-Info",
        &done.key,
    );
    ed25519_dalek::VerifyingKey::from_bytes(&device_key)
        .and_then(|k| {
            k.verify(
                &[&device_x[..], &device_id, &device_key].concat(),
                &ed25519_dalek::Signature::from_bytes(&device_signature),
            )
        })
        .map_err(|_| "the device's signature is wrong")?;
    Ok(Credentials {
        device_key,
        secret,
        device_id,
        client_id,
    })
}

fn uuid() -> String {
    let b = random::<16>().unwrap_or([7; 16]);
    let h = hex(&b);
    format!(
        "{}-{}-4{}-{}-{}",
        &h[0..8],
        &h[8..12],
        &h[13..16],
        &h[16..20],
        &h[20..32]
    )
}

/// Pair-verify with saved credentials; the shared secret, from which the
/// connection's keys come.
pub fn verify(conn: &mut Conn, credentials: &Credentials) -> Result<[u8; 32], String> {
    let ours = random::<32>()?;
    let public = MontgomeryPoint::mul_base_clamped(ours).to_bytes();
    let m2 = post(
        conn,
        "/pair-verify",
        &tlv(&[(tag::SEQ_NO, &[1]), (tag::PUBLIC_KEY, &public)]),
        false,
    )?;
    let theirs: [u8; 32] = m2
        .get(&tag::PUBLIC_KEY)
        .and_then(|k| k.as_slice().try_into().ok())
        .ok_or("no verify key")?;
    let shared = MontgomeryPoint(theirs).mul_clamped(ours).to_bytes();
    let key = hkdf(
        "Pair-Verify-Encrypt-Salt",
        "Pair-Verify-Encrypt-Info",
        &shared,
    );
    let sealed = m2.get(&tag::ENCRYPTED_DATA).ok_or("no verify data")?;
    let found =
        read_tlv(&open(&key, b"PV-Msg02", sealed).ok_or("the device's answer did not decrypt")?);
    let id = found.get(&tag::IDENTIFIER).ok_or("no device id")?;
    if *id != credentials.device_id {
        return Err("another device answered; pair again".into());
    }
    let signature: [u8; 64] = found
        .get(&tag::SIGNATURE)
        .and_then(|k| k.as_slice().try_into().ok())
        .ok_or("no signature")?;
    ed25519_dalek::VerifyingKey::from_bytes(&credentials.device_key)
        .and_then(|k| {
            k.verify(
                &[&theirs[..], id, &public].concat(),
                &ed25519_dalek::Signature::from_bytes(&signature),
            )
        })
        .map_err(|_| "the device is not the one paired; pair again")?;
    let signing = ed25519_dalek::SigningKey::from_bytes(&credentials.secret);
    let mine = signing
        .sign(&[&public[..], &credentials.client_id, &theirs].concat())
        .to_bytes();
    let inner = tlv(&[
        (tag::IDENTIFIER, &credentials.client_id),
        (tag::SIGNATURE, &mine),
    ]);
    post(
        conn,
        "/pair-verify",
        &tlv(&[
            (tag::SEQ_NO, &[3]),
            (tag::ENCRYPTED_DATA, &seal(&key, b"PV-Msg03", &inner)),
        ]),
        false,
    )?;
    Ok(shared)
}

/// Transient pairing, for receivers that take it without a PIN on screen;
/// the shared secret.
pub fn transient(conn: &mut Conn) -> Result<Vec<u8>, String> {
    conn.request("POST", "/pair-pin-start", "HTTP/1.1", &headers(true), &[])?;
    let m2 = post(
        conn,
        "/pair-setup",
        &tlv(&[
            (tag::METHOD, &[0]),
            (tag::SEQ_NO, &[1]),
            (tag::FLAGS, &[0x10]),
        ]),
        true,
    )?;
    let salt = m2.get(&tag::SALT).ok_or("no salt")?;
    let server = m2.get(&tag::PUBLIC_KEY).ok_or("no public key")?;
    let done = srp::exchange(TRANSIENT_PIN, salt, server, &random::<32>()?)?;
    let m4 = post(
        conn,
        "/pair-setup",
        &tlv(&[
            (tag::SEQ_NO, &[3]),
            (tag::PUBLIC_KEY, &done.public),
            (tag::PROOF, &done.proof),
        ]),
        true,
    )?;
    if m4.get(&tag::PROOF) != Some(&done.expected) {
        return Err("the device needs a PIN".into());
    }
    Ok(done.key)
}

/// The keys of the control connection from a shared secret: what we
/// write with and what we read with.
pub fn control_keys(shared: &[u8]) -> ([u8; 32], [u8; 32]) {
    (
        hkdf("Control-Salt", "Control-Write-Encryption-Key", shared),
        hkdf("Control-Salt", "Control-Read-Encryption-Key", shared),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn credentials_read_back() {
        let c = Credentials {
            device_key: [1; 32],
            secret: [2; 32],
            device_id: b"AA:BB".to_vec(),
            client_id: b"x-y".to_vec(),
        };
        assert_eq!(Credentials::parse(&c.text()), Some(c));
        assert_eq!(Credentials::parse("zz:00"), None);
    }
}
