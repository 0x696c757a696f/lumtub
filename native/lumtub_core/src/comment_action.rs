//! A comment's like and dislike actions made from another comment's. The
//! TV app's comment lists leave the buttons out; the one comment a page is
//! about has them. An action is a base64 protobuf message naming its
//! comment by id, so the same action with the id swapped is that action
//! for another comment on the same video.

use std::os::raw::c_char;

use serde::Deserialize;

use crate::taste::{give_json, text};

const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// Standard or URL-safe base64, padded or not.
fn decode(text: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(text.len() * 3 / 4);
    let (mut bits, mut count) = (0u32, 0);
    for c in text.bytes() {
        let value = match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' | b'-' => 62,
            b'/' | b'_' => 63,
            b'=' => break,
            _ => return None,
        };
        bits = bits << 6 | value as u32;
        count += 6;
        if count >= 8 {
            count -= 8;
            out.push((bits >> count) as u8);
        }
    }
    Some(out)
}

/// Encoded like [like], the action it came from: URL-safe when that was,
/// padded when that was.
fn encode(bytes: &[u8], like: &str) -> String {
    let url = like.contains(['-', '_']);
    let mut out = String::new();
    for chunk in bytes.chunks(3) {
        let n = chunk.iter().enumerate().fold(0u32, |n, (i, b)| n | (*b as u32) << (16 - 8 * i));
        for i in 0..=chunk.len() {
            let c = ALPHABET[(n >> (18 - 6 * i) & 63) as usize];
            out.push(match (url, c) {
                (true, b'+') => '-',
                (true, b'/') => '_',
                _ => c as char,
            });
        }
    }
    if like.ends_with('=') {
        while !out.len().is_multiple_of(4) {
            out.push('=');
        }
    }
    out
}

fn varint(data: &[u8], at: &mut usize) -> Option<u64> {
    let mut value = 0u64;
    for shift in (0..64).step_by(7) {
        let byte = *data.get(*at)?;
        *at += 1;
        value |= ((byte & 0x7f) as u64) << shift;
        if byte & 0x80 == 0 {
            return Some(value);
        }
    }
    None
}

fn put_varint(mut value: u64, out: &mut Vec<u8>) {
    while value >= 0x80 {
        out.push(value as u8 | 0x80);
        value >>= 7;
    }
    out.push(value as u8);
}

/// [message] with every length-delimited field equal to [from] set to
/// [to], looking inside nested messages; None when it is not a protobuf
/// message or nothing was swapped.
fn swap(message: &[u8], from: &[u8], to: &[u8], depth: u32) -> Option<Vec<u8>> {
    if depth > 8 {
        return None;
    }
    let mut out = Vec::with_capacity(message.len() + to.len());
    let mut at = 0;
    let mut swapped = false;
    while at < message.len() {
        let key = varint(message, &mut at)?;
        if key >> 3 == 0 {
            return None;
        }
        put_varint(key, &mut out);
        match key & 7 {
            0 => put_varint(varint(message, &mut at)?, &mut out),
            1 => {
                out.extend_from_slice(message.get(at..at + 8)?);
                at += 8;
            }
            5 => {
                out.extend_from_slice(message.get(at..at + 4)?);
                at += 4;
            }
            2 => {
                let length = varint(message, &mut at)? as usize;
                let value = message.get(at..at.checked_add(length)?)?;
                at += length;
                let replaced = if value == from {
                    Some(to.to_vec())
                } else {
                    swap(value, from, to, depth + 1)
                };
                let value = match replaced {
                    Some(new) => {
                        swapped = true;
                        new
                    }
                    None => value.to_vec(),
                };
                put_varint(value.len() as u64, &mut out);
                out.extend_from_slice(&value);
            }
            _ => return None,
        }
    }
    swapped.then_some(out)
}

/// [action] of comment [from] made into the same action for comment [to].
pub fn action_for(action: &str, from: &str, to: &str) -> Option<String> {
    if from.is_empty() || from == to {
        return None;
    }
    let decoded = decode(action)?;
    let swapped = swap(&decoded, from.as_bytes(), to.as_bytes(), 0)?;
    Some(encode(&swapped, action))
}

#[derive(Deserialize)]
struct Request {
    action: String,
    from: String,
    to: String,
}

/// [action_for] of [json] `{action, from, to}`, as a JSON string or null.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_comment_action_for(json: *const u8, length: usize) -> *mut c_char {
    let Ok(request) = serde_json::from_str::<Request>(unsafe { text(json, length) }) else {
        return std::ptr::null_mut();
    };
    give_json(&action_for(&request.action, &request.from, &request.to))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn message(fields: &[(u64, &[u8])]) -> Vec<u8> {
        let mut out = Vec::new();
        for (field, value) in fields {
            put_varint(field << 3 | 2, &mut out);
            put_varint(value.len() as u64, &mut out);
            out.extend_from_slice(value);
        }
        out
    }

    #[test]
    fn round_trips_base64() {
        for text in ["", "a", "ab", "abc", "abcd", "\u{ff}\u{fe}?>"] {
            for like in ["Eg==", "Eg-_", "Eg"] {
                let encoded = encode(text.as_bytes(), like);
                assert_eq!(decode(&encoded).unwrap(), text.as_bytes());
            }
        }
        assert_eq!(encode(b"\xfb\xff", "x_"), "-_8");
        assert_eq!(encode(b"\xfb\xff", "x="), "+/8=");
    }

    #[test]
    fn swaps_the_comment_id_also_in_nested_messages() {
        let inner = message(&[(1, b"UgxAAAA"), (2, b"dQw4w9WgXcQ")]);
        let mut outer = vec![0x08, 0x05];
        outer.extend(message(&[(3, b"UgxAAAA"), (4, &inner)]));
        let action = encode(&outer, "x=");
        let made = action_for(&action, "UgxAAAA", "UgyBBBBBB.reply").unwrap();
        let bytes = decode(&made).unwrap();
        let mut wanted_inner = message(&[(1, b"UgyBBBBBB.reply"), (2, b"dQw4w9WgXcQ")]);
        let mut wanted = vec![0x08, 0x05];
        wanted.extend(message(&[(3, b"UgyBBBBBB.reply"), (4, &std::mem::take(&mut wanted_inner))]));
        assert_eq!(bytes, wanted);
        assert_eq!(action_for(&action, "nothere", "x"), None);
        assert_eq!(action_for("%%%", "a", "b"), None);
    }
}
