//! The cryptography of HomeKit pairing as AirPlay uses it: TLV8 messages,
//! HKDF-SHA512 keys, ChaCha20-Poly1305 with 8-byte nonces, and the framed
//! encryption of a connection once it is verified.

use ring::aead::{Aad, CHACHA20_POLY1305, LessSafeKey, Nonce, UnboundKey};
use ring::hmac;
use std::collections::HashMap;

pub mod tag {
    pub const METHOD: u8 = 0x00;
    pub const IDENTIFIER: u8 = 0x01;
    pub const SALT: u8 = 0x02;
    pub const PUBLIC_KEY: u8 = 0x03;
    pub const PROOF: u8 = 0x04;
    pub const ENCRYPTED_DATA: u8 = 0x05;
    pub const SEQ_NO: u8 = 0x06;
    pub const ERROR: u8 = 0x07;
    pub const SIGNATURE: u8 = 0x0A;
    pub const FLAGS: u8 = 0x13;
}

/// Writes TLV8: values longer than 255 bytes go in several items of the
/// same tag.
pub fn tlv(items: &[(u8, &[u8])]) -> Vec<u8> {
    let mut out = Vec::new();
    for &(kind, value) in items {
        if value.is_empty() {
            out.extend_from_slice(&[kind, 0]);
        }
        for chunk in value.chunks(255) {
            out.push(kind);
            out.push(chunk.len() as u8);
            out.extend_from_slice(chunk);
        }
    }
    out
}

/// Reads TLV8, joining the items of a tag.
pub fn read_tlv(data: &[u8]) -> HashMap<u8, Vec<u8>> {
    let mut found: HashMap<u8, Vec<u8>> = HashMap::new();
    let mut at = 0;
    while at + 2 <= data.len() {
        let (kind, length) = (data[at], data[at + 1] as usize);
        let end = (at + 2 + length).min(data.len());
        found.entry(kind).or_default().extend_from_slice(&data[at + 2..end]);
        at = end;
    }
    found
}

/// HKDF with SHA-512, 32 bytes out.
pub fn hkdf(salt: &str, info: &str, secret: &[u8]) -> [u8; 32] {
    let prk = hmac::sign(&hmac::Key::new(hmac::HMAC_SHA512, salt.as_bytes()), secret);
    let mut block = hmac::Context::with_key(&hmac::Key::new(hmac::HMAC_SHA512, prk.as_ref()));
    block.update(info.as_bytes());
    block.update(&[1]);
    let mut out = [0u8; 32];
    out.copy_from_slice(&block.sign().as_ref()[..32]);
    out
}

/// A nonce of four zero bytes and eight more: a label such as `PV-Msg02`,
/// or a counter in little-endian order.
fn nonce(eight: [u8; 8]) -> Nonce {
    let mut bytes = [0u8; 12];
    bytes[4..].copy_from_slice(&eight);
    Nonce::assume_unique_for_key(bytes)
}

fn key(bytes: &[u8; 32]) -> LessSafeKey {
    LessSafeKey::new(UnboundKey::new(&CHACHA20_POLY1305, bytes).expect("a 32-byte key"))
}

pub fn seal(secret: &[u8; 32], label: &[u8; 8], data: &[u8]) -> Vec<u8> {
    let mut out = data.to_vec();
    key(secret).seal_in_place_append_tag(nonce(*label), Aad::empty(), &mut out).expect("sealed");
    out
}

pub fn open(secret: &[u8; 32], label: &[u8; 8], data: &[u8]) -> Option<Vec<u8>> {
    let mut out = data.to_vec();
    let length = key(secret).open_in_place(nonce(*label), Aad::empty(), &mut out).ok()?.len();
    out.truncate(length);
    Some(out)
}

/// The encryption of a verified connection: frames of at most 1024 bytes,
/// each with its length (little-endian) as associated data and a counter
/// as nonce, one counter each way.
pub struct Framing {
    write: LessSafeKey,
    read: LessSafeKey,
    sent: u64,
    received: u64,
    pending: Vec<u8>,
}

const FRAME: usize = 1024;
const TAG: usize = 16;

impl Framing {
    pub fn new(write: &[u8; 32], read: &[u8; 32]) -> Self {
        Framing { write: key(write), read: key(read), sent: 0, received: 0, pending: Vec::new() }
    }

    pub fn encrypt(&mut self, data: &[u8]) -> Vec<u8> {
        let mut out = Vec::with_capacity(data.len() + data.len() / FRAME * 18 + 18);
        for chunk in data.chunks(FRAME) {
            let length = (chunk.len() as u16).to_le_bytes();
            let mut frame = chunk.to_vec();
            self.write.seal_in_place_append_tag(nonce(self.sent.to_le_bytes()), Aad::from(length), &mut frame).expect("sealed");
            self.sent += 1;
            out.extend_from_slice(&length);
            out.extend_from_slice(&frame);
        }
        out
    }

    /// Takes bytes as they arrive; the plain text of the frames they
    /// complete, or None when a frame fails to open.
    pub fn decrypt(&mut self, data: &[u8]) -> Option<Vec<u8>> {
        self.pending.extend_from_slice(data);
        let mut out = Vec::new();
        loop {
            if self.pending.len() < 2 {
                break;
            }
            let length = u16::from_le_bytes([self.pending[0], self.pending[1]]) as usize;
            if self.pending.len() < 2 + length + TAG {
                break;
            }
            let mut frame: Vec<u8> = self.pending[2..2 + length + TAG].to_vec();
            let aad = [self.pending[0], self.pending[1]];
            let plain = self.read.open_in_place(nonce(self.received.to_le_bytes()), Aad::from(aad), &mut frame).ok()?.len();
            self.received += 1;
            out.extend_from_slice(&frame[..plain]);
            self.pending.drain(..2 + length + TAG);
        }
        Some(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tlv_splits_and_joins_long_values() {
        let long = vec![7u8; 300];
        let data = tlv(&[(tag::SEQ_NO, &[1]), (tag::PUBLIC_KEY, &long)]);
        assert_eq!(data.len(), 3 + 2 + 255 + 2 + 45);
        let read = read_tlv(&data);
        assert_eq!(read[&tag::SEQ_NO], [1]);
        assert_eq!(read[&tag::PUBLIC_KEY], long);
    }

    #[test]
    fn hkdf_matches_another_implementation() {
        // As Python's cryptography library derives it.
        let out = hkdf("salt", "info", b"secret");
        assert_eq!(hex(&out), "90e269f053d383c4b2070be93238adf358f3d67bd7b17ca3de95f10a50a8385e");
    }

    #[test]
    fn frames_go_both_ways() {
        let (a, b) = ([1u8; 32], [2u8; 32]);
        let mut one = Framing::new(&a, &b);
        let mut two = Framing::new(&b, &a);
        let message = vec![9u8; 3000];
        let sealed = one.encrypt(&message);
        assert_eq!(sealed.len(), 3000 + 3 * 18);
        let mut got = two.decrypt(&sealed[..100]).unwrap();
        got.extend(two.decrypt(&sealed[100..]).unwrap());
        assert_eq!(got, message);
        let back = two.encrypt(b"ok");
        assert_eq!(one.decrypt(&back).unwrap(), b"ok");
        let mut broken = one.encrypt(b"x");
        broken[3] ^= 1;
        assert!(two.decrypt(&broken).is_none());
    }

    pub fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }
}
