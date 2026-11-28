// The Sec-MS-GEC token Edge's read-aloud service asks for, as a
// `<16 hex>-<64 hex>` string (v2, required since October 2026).
//
// Taken from msedge-tts 0.4.1 (src/tts/drm.rs), https://github.com/hs-CN/msedge-tts,
// itself a port of edge-tts's drm.py (https://github.com/rany2/edge-tts/pull/492).
// msedge-tts is under the MIT License:
//
// Copyright (c) 2024 shuai.huang
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// Every operation is a wrapping 32-bit operation, as the original Python
// masks with `& 0xFFFFFFFF`.

const WIN_EPOCH: u64 = 11_644_473_600;

/// Client token embedded in the hashed string.
const TRUSTED_CLIENT_TOKEN: &str = "6A5AA1D4EAFF4E9FB37E23D68491D6F4";

// FIPS 180-4 SHA-256 constants:
// https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf
const SHA256_INITIAL: [u32; 8] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];

const SHA256_STATE: [u32; 8] = [
    0xfd9fbea2, 0x91243ce7, 0xbe499094, 0xcd2e1e0a, 0x6c006f49, 0x04bd35ab, 0xfeb0a7e4, 0x03effbd2,
];

const SHA256_SCHEDULE: [u32; 14] = [
    0xeb24bf9e, 0x1558691f, 0xa0c09ee2, 0x0cfa32ba, 0xa622ee8c, 0xd1dd9491, 0xc0dd25a0, 0xf9e70ab6,
    0xf0c31573, 0x7058ce4e, 0x7188e606, 0x00e5ab33, 0xd258b060, 0x72766564,
];

const SHA256_ROUND_CONSTANTS: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

const SHA256_ADJUSTMENT: u32 = 0xc9dc06a7;
const SHA256_SIGMA0_ADJUSTMENT: u32 = 0x059c0b80;
const SHA256_SIGMA1_ADJUSTMENT: u32 = 0x000b92c0;

/// `_SHA256_ROUND_CONSTANTS[..14] + (SHA256_ADJUSTMENT,) + [15..]`.
const SHA256_BLOCK_CONSTANTS: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0xc9dc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

const CS64_COEFFICIENTS: [(u32, u32); 14] = [
    (0xe82e91b1, 0xb32700d0),
    (0x44de24c6, 0x88dff51d),
    (0x3beb65bc, 0x29514038),
    (0xc89c5933, 0xb328cbdf),
    (0x8d1ec211, 0xd405b4d5),
    (0x314ef5d5, 0x26e55f3c),
    (0xe92491b1, 0x607801c6),
    (0xf0a5b9d5, 0x82b2c1fb),
    (0x06064cf3, 0xfa51a3da),
    (0xda79fa60, 0x207cc464),
    (0xbed20560, 0x3c3c74f3),
    (0x89f9c9f8, 0xd2d14b61),
    (0x35fa38c6, 0xbb04a2c1),
    (0xcb49e3c6, 0xc5626167),
];

const CS64_FACTOR: u32 = 0x82893933;
const CS64_ADJUSTMENT0: u32 = 0xf2f90b1a;
const CS64_ADJUSTMENT1: u32 = 0x0b1a0000;

/// Rotate a 32-bit value left by 16 bits.
#[inline]
fn rol16(value: u32) -> u32 {
    value.rotate_left(16)
}

/// SHA-256 small sigma zero, truncating the combined rotations once.
#[inline]
fn sigma0(value: u32) -> u32 {
    (value >> 7) ^ (value << 25) ^ (value >> 18) ^ (value << 14) ^ (value >> 3)
}

/// SHA-256 small sigma one, truncating the combined rotations once.
#[inline]
fn sigma1(value: u32) -> u32 {
    (value >> 17) ^ (value << 15) ^ (value >> 19) ^ (value << 13) ^ (value >> 10)
}

/// `Ch(e, f, g) = g ^ (e & (f ^ g))`.
#[inline]
fn ch(x: u32, y: u32, z: u32) -> u32 {
    z ^ (x & (y ^ z))
}

/// `Maj(a, b, c) = (a & b) | (c & (a | b))`.
#[inline]
fn maj(x: u32, y: u32, z: u32) -> u32 {
    (x & y) | (z & (x | y))
}

/// `ROTR(x, 6) ^ ROTR(x, 11) ^ ROTR(x, 25)`.
#[inline]
fn big_sigma_e(x: u32) -> u32 {
    x.rotate_right(6) ^ x.rotate_right(11) ^ x.rotate_right(25)
}

/// `ROTR(x, 2) ^ ROTR(x, 13) ^ ROTR(x, 22)`.
#[inline]
fn big_sigma_a(x: u32) -> u32 {
    x.rotate_right(2) ^ x.rotate_right(13) ^ x.rotate_right(22)
}

/// Split data into little-endian 32-bit words, zero-padded to an even count.
fn words_le4_even(data: &[u8]) -> Vec<u32> {
    let mut padded = data.to_vec();
    padded.resize(padded.len().div_ceil(4) * 4, 0);
    let mut words: Vec<u32> = padded
        .as_chunks::<4>()
        .0
        .iter()
        .map(|c| u32::from_le_bytes(*c))
        .collect();
    if !words.len().is_multiple_of(2) {
        words.push(0);
    }
    words
}

/// Run SHA-256 rounds, optionally resuming inside the first block.
fn sha256_rounds(state: [u32; 8], words: &[u32], first_round: usize) -> [u32; 8] {
    let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h] = state;
    let constants: &[u32; 64] = if first_round == 14 {
        &SHA256_BLOCK_CONSTANTS
    } else {
        &SHA256_ROUND_CONSTANTS
    };
    let aligned = std::cmp::min(64, first_round.div_ceil(8) * 8);

    let mut index = first_round;
    while index < aligned {
        let t1 = h
            .wrapping_add(big_sigma_e(e))
            .wrapping_add(ch(e, f, g))
            .wrapping_add(constants[index])
            .wrapping_add(words[index]);
        let t2 = big_sigma_a(a).wrapping_add(maj(a, b, c));
        (a, b, c, d, e, f, g, h) = (t1.wrapping_add(t2), a, b, c, d.wrapping_add(t1), e, f, g);
        index += 1;
    }

    // Eight rounds return the working-register names to their original order.
    while index < 64 {
        let mut t1 = h
            .wrapping_add(big_sigma_e(e))
            .wrapping_add(ch(e, f, g))
            .wrapping_add(constants[index])
            .wrapping_add(words[index]);
        d = d.wrapping_add(t1);
        h = t1.wrapping_add(big_sigma_a(a)).wrapping_add(maj(a, b, c));

        t1 = g
            .wrapping_add(big_sigma_e(d))
            .wrapping_add(ch(d, e, f))
            .wrapping_add(constants[index + 1])
            .wrapping_add(words[index + 1]);
        c = c.wrapping_add(t1);
        g = t1.wrapping_add(big_sigma_a(h)).wrapping_add(maj(h, a, b));

        t1 = f
            .wrapping_add(big_sigma_e(c))
            .wrapping_add(ch(c, d, e))
            .wrapping_add(constants[index + 2])
            .wrapping_add(words[index + 2]);
        b = b.wrapping_add(t1);
        f = t1.wrapping_add(big_sigma_a(g)).wrapping_add(maj(g, h, a));

        t1 = e
            .wrapping_add(big_sigma_e(b))
            .wrapping_add(ch(b, c, d))
            .wrapping_add(constants[index + 3])
            .wrapping_add(words[index + 3]);
        a = a.wrapping_add(t1);
        e = t1.wrapping_add(big_sigma_a(f)).wrapping_add(maj(f, g, h));

        t1 = d
            .wrapping_add(big_sigma_e(a))
            .wrapping_add(ch(a, b, c))
            .wrapping_add(constants[index + 4])
            .wrapping_add(words[index + 4]);
        h = h.wrapping_add(t1);
        d = t1.wrapping_add(big_sigma_a(e)).wrapping_add(maj(e, f, g));

        t1 = c
            .wrapping_add(big_sigma_e(h))
            .wrapping_add(ch(h, a, b))
            .wrapping_add(constants[index + 5])
            .wrapping_add(words[index + 5]);
        g = g.wrapping_add(t1);
        c = t1.wrapping_add(big_sigma_a(d)).wrapping_add(maj(d, e, f));

        t1 = b
            .wrapping_add(big_sigma_e(g))
            .wrapping_add(ch(g, h, a))
            .wrapping_add(constants[index + 6])
            .wrapping_add(words[index + 6]);
        f = f.wrapping_add(t1);
        b = t1.wrapping_add(big_sigma_a(c)).wrapping_add(maj(c, d, e));

        t1 = a
            .wrapping_add(big_sigma_e(f))
            .wrapping_add(ch(f, g, h))
            .wrapping_add(constants[index + 7])
            .wrapping_add(words[index + 7]);
        e = e.wrapping_add(t1);
        a = t1.wrapping_add(big_sigma_a(b)).wrapping_add(maj(b, c, d));

        index += 8;
    }

    [a, b, c, d, e, f, g, h]
}

/// Expand SHA-256 words, combining rotations before modular addition.
fn expand_sha256_schedule(words: &mut Vec<u32>, first_word: usize) {
    for index in first_word..64 {
        let x = words[index - 2];
        let y = words[index - 15];
        let s1 = sigma1(x);
        let s0 = sigma0(y);
        words.push(
            s1.wrapping_add(words[index - 7])
                .wrapping_add(s0)
                .wrapping_add(words[index - 16]),
        );
    }
}

/// Compute the initial SHA-256 state for token data (first seven bytes are salt).
fn sha256_init(data: &[u8]) -> [u32; 8] {
    let mut words = vec![0u32; 16];
    words[14] = (u32::from(data[0]) << 16) | (u32::from(data[1]) << 8) | u32::from(data[2]);
    words[15] = u32::from_be_bytes([data[3], data[4], data[5], data[6]]);

    for index in 16..30 {
        let mut value = SHA256_SCHEDULE[index - 16];
        if index - 2 >= 14 {
            let s = sigma1(words[index - 2]);
            value = value.wrapping_add(if index == 16 {
                s ^ SHA256_SIGMA1_ADJUSTMENT
            } else {
                s
            });
        }
        if index - 7 >= 14 {
            value = value.wrapping_add(words[index - 7]);
        }
        if index - 15 >= 14 {
            let s = sigma0(words[index - 15]);
            value = value.wrapping_add(if index == 29 {
                s ^ SHA256_SIGMA0_ADJUSTMENT
            } else {
                s
            });
        }
        words.push(value);
    }

    words.push(
        sigma1(words[28])
            .wrapping_add(words[23])
            .wrapping_add(sigma0(words[15]))
            .wrapping_add(words[14])
            .wrapping_add(SHA256_ADJUSTMENT)
            .wrapping_sub(SHA256_ROUND_CONSTANTS[14]),
    );

    expand_sha256_schedule(&mut words, 31);
    let working = sha256_rounds(SHA256_STATE, &words, 14);

    let mut state = [0u32; 8];
    for (index, item) in state.iter_mut().enumerate() {
        *item = SHA256_INITIAL[index].wrapping_add(working[index]);
    }
    state
}

/// Compute the SHA-256 digest for token data.
fn sha256_digest(data: &[u8]) -> [u8; 32] {
    let length = 57 + data.len();
    let mut padded = data[7..].to_vec();
    padded.push(0x80);
    let zeros = (((55isize - length as isize) % 64 + 64) % 64) as usize;
    padded.extend(std::iter::repeat_n(0u8, zeros));
    padded.extend_from_slice(&((length as u64) * 8).to_be_bytes());

    let mut state = sha256_init(&data[..7]);
    for chunk in padded.as_chunks::<64>().0 {
        let mut words: Vec<u32> = chunk
            .as_chunks::<4>()
            .0
            .iter()
            .map(|c| u32::from_be_bytes(*c))
            .collect();
        expand_sha256_schedule(&mut words, 16);
        let working = sha256_rounds(state, &words, 0);
        for (index, item) in state.iter_mut().enumerate() {
            *item = item.wrapping_add(working[index]);
        }
    }

    let mut digest = [0u8; 32];
    for (index, word) in state.iter().enumerate() {
        digest[index * 4..index * 4 + 4].copy_from_slice(&word.to_be_bytes());
    }
    digest
}

/// Compute the CS64 digest words for token data.
fn cs64_digest(data: &[u8], digest: &[u8; 32]) -> [u32; 2] {
    let key_a = u32::from_le_bytes([digest[0], digest[1], digest[2], digest[3]]) | 1;
    let key_b = u32::from_le_bytes([digest[4], digest[5], digest[6], digest[7]]) | 1;
    let factors = [
        key_a.wrapping_mul(CS64_FACTOR),
        key_b.wrapping_mul(CS64_FACTOR),
    ];

    let mut terms: Vec<u32> = CS64_COEFFICIENTS
        .iter()
        .enumerate()
        .map(|(index, (coefficient, _))| coefficient.wrapping_mul(factors[index % 2]))
        .collect();
    let mut offsets: Vec<u32> = CS64_COEFFICIENTS
        .iter()
        .map(|(_, offset)| *offset)
        .collect();

    let mut input = Vec::with_capacity(data.len() + 1);
    input.push(0);
    input.extend_from_slice(data);

    for (index, word) in words_le4_even(&input).into_iter().enumerate() {
        let mut term = word.wrapping_mul(if index % 2 == 0 { key_a } else { key_b });
        let mut offset = rol16(word).wrapping_mul(if index % 2 == 0 {
            0xef0569fb
        } else {
            0xc31713db
        });
        if index == 0 {
            term = term.wrapping_add(CS64_ADJUSTMENT0.wrapping_mul(factors[0]));
            offset = offset.wrapping_add(CS64_ADJUSTMENT1);
        }
        terms.push(term);
        offsets.push(offset);
    }

    let mut swap_acc = 0u32;
    let mut swap_last = 0u32;
    let mut state = 0u32;
    let mut acc = 0u32;
    let mut index = 0;
    while index < terms.len() {
        let x = terms[index];
        let y = terms[index + 1];

        let mut t = rol16(offsets[index].wrapping_add(x));
        let mut q = t.wrapping_mul(0x76f50f34);
        swap_acc = swap_acc.wrapping_add(rol16(q).wrapping_mul(0xc3efea97).wrapping_add(q));
        t = rol16(offsets[index + 1].wrapping_add(y));
        q = t.wrapping_mul(0x1881ce3c);
        swap_last = rol16(q).wrapping_mul(0x35bd1ec9).wrapping_add(q);
        swap_acc = swap_acc.wrapping_add(swap_last);

        state = state.wrapping_mul(key_a).wrapping_add(x);
        state = rol16(state).wrapping_mul(0xcf98b111);
        state = rol16(state).wrapping_mul(0x87085b9f);
        state = rol16(state).wrapping_mul(0x12ceb96d);
        state = rol16(state).wrapping_mul(0x257e1d83);
        acc = acc.wrapping_add(state);

        t = state.wrapping_mul(key_b).wrapping_add(y);
        t = rol16(t).wrapping_mul(0xa27416f5);
        t = rol16(t).wrapping_mul(0xd38396ff);
        state = rol16(rol16(t).wrapping_mul(0x7c932b89)).wrapping_mul(0xbfa49f69);
        acc = acc.wrapping_add(state);

        index += 2;
    }

    [swap_last ^ state, swap_acc ^ acc]
}

fn hex_upper(bytes: &[u8]) -> String {
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        output.push_str(&format!("{byte:02X}"));
    }
    output
}

/// Compute the token hash components: `(cs64, sha256)` as upper-case hex.
fn token_hash(data: &[u8]) -> (String, String) {
    let digest = sha256_digest(data);
    let cs64 = cs64_digest(data, &digest);
    let mut cs64_bytes = [0u8; 8];
    cs64_bytes[..4].copy_from_slice(&cs64[0].to_le_bytes());
    cs64_bytes[4..].copy_from_slice(&cs64[1].to_le_bytes());
    (hex_upper(&cs64_bytes), hex_upper(&digest))
}

/// Generate a v2 `Sec-MS-GEC` token from Windows file-time ticks.
///
/// `ticks` are 100 ns intervals since 1601-01-01, already rounded down to a
/// five minute window. The result is formatted as `<16 hex>-<64 hex>`.
fn generate_sec_ms_gec_v2(ticks: u128) -> String {
    let str_to_hash = format!("{ticks}{TRUSTED_CLIENT_TOKEN}");
    let (cs64, sha256) = token_hash(str_to_hash.as_bytes());
    format!("{cs64}-{sha256}")
}

/// The token for now, with the clock moved by [skew] seconds (the server's
/// clock less this computer's), in five-minute steps.
pub(crate) fn token(skew: i64) -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
        + skew;
    generate_sec_ms_gec_v2(ticks_at(now))
}

/// Windows file-time ticks (100 ns) at Unix time [seconds], rounded down
/// to a five-minute window.
fn ticks_at(seconds: i64) -> u128 {
    let windows = (seconds.max(0) as u64 + WIN_EPOCH) as u128;
    (windows - windows % 300) * 10_000_000
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn has_the_v2_shape() {
        let token = generate_sec_ms_gec_v2(ticks_at(1_763_700_000));
        let (cs64, sha) = token.split_once('-').unwrap();
        assert_eq!((cs64.len(), sha.len()), (16, 64));
        assert!(
            token
                .chars()
                .all(|c| c == '-' || c.is_ascii_digit() || c.is_ascii_uppercase())
        );
        // The same five minutes give the same token.
        assert_eq!(token, generate_sec_ms_gec_v2(ticks_at(1_763_700_200)));
        assert_ne!(token, generate_sec_ms_gec_v2(ticks_at(1_763_700_300)));
        assert_eq!(ticks_at(0) % 3_000_000_000, 0);
    }
}
