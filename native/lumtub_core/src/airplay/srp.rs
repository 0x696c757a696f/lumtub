//! The client side of SRP-6a as HomeKit pairing uses it: the 3072-bit
//! group with generator 5, SHA-512, user name `Pair-Setup` and the PIN as
//! password. Numbers are hashed in their shortest big-endian form, except
//! where the protocol pads them to the group's size.

use num_bigint::BigUint;
use sha2::{Digest, Sha512};

const PRIME: &str = "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA6\
3B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245\
E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F2411\
7C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F\
83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08\
CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9\
DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AAAC42DAD33170D\
04507A33A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7\
ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864D8760273\
3EC86A64521F2B18177B200CBBE117577A615D6C770988C0BAD946E208E24FA074E5AB31\
43DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF";
const USER: &str = "Pair-Setup";
const WIDTH: usize = 384;

fn hash(parts: &[&[u8]]) -> Vec<u8> {
    let mut h = Sha512::new();
    for p in parts {
        h.update(p);
    }
    h.finalize().to_vec()
}

fn pad(n: &BigUint) -> Vec<u8> {
    let b = n.to_bytes_be();
    let mut out = vec![0u8; WIDTH.saturating_sub(b.len())];
    out.extend_from_slice(&b);
    out
}

fn short(b: &[u8]) -> Vec<u8> {
    BigUint::from_bytes_be(b).to_bytes_be()
}

/// What the client sends and expects back.
pub struct Exchange {
    /// A, to send.
    pub public: Vec<u8>,
    /// M1, to send.
    pub proof: Vec<u8>,
    /// M2, which the accessory answers with when the PIN was right.
    pub expected: Vec<u8>,
    /// K, the shared key the session keys come from.
    pub key: Vec<u8>,
}

/// Answers the accessory's salt and public key `B` with the private
/// number `private` (random, 32 bytes or more).
pub fn exchange(
    pin: &str,
    salt: &[u8],
    server: &[u8],
    private: &[u8],
) -> Result<Exchange, &'static str> {
    let n = BigUint::parse_bytes(PRIME.as_bytes(), 16).expect("the group's prime");
    let g = BigUint::from(5u32);
    let b = BigUint::from_bytes_be(server);
    if (&b % &n) == BigUint::ZERO {
        return Err("bad public key from the device");
    }
    let a = BigUint::from_bytes_be(private);
    let big_a = g.modpow(&a, &n);
    let k = BigUint::from_bytes_be(&hash(&[&n.to_bytes_be(), &pad(&g)]));
    let u = BigUint::from_bytes_be(&hash(&[&pad(&big_a), &pad(&b)]));
    let inner = hash(&[format!("{USER}:{pin}").as_bytes()]);
    let x = BigUint::from_bytes_be(&hash(&[salt, &inner]));
    let kv = (&k * g.modpow(&x, &n)) % &n;
    let base = ((&b + &n) - kv) % &n;
    let s = base.modpow(&(&a + &u * &x), &n);
    let key = hash(&[&s.to_bytes_be()]);
    let hn = BigUint::from_bytes_be(&hash(&[&n.to_bytes_be()]));
    let hg = BigUint::from_bytes_be(&hash(&[&g.to_bytes_be()]));
    let xor = (hn ^ hg).to_bytes_be();
    let proof = hash(&[
        &xor,
        &hash(&[USER.as_bytes()]),
        salt,
        &big_a.to_bytes_be(),
        &short(server),
        &key,
    ]);
    let expected = hash(&[&big_a.to_bytes_be(), &proof, &key]);
    Ok(Exchange {
        public: big_a.to_bytes_be(),
        proof,
        expected,
        key,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn unhex(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    /// The numbers another implementation of the same formulas gives for a
    /// fixed salt, PIN and private numbers.
    #[test]
    fn agrees_with_a_reference() {
        let vector = include_str!("srp_vector.txt");
        let value = |name: &str| {
            unhex(
                vector
                    .lines()
                    .find_map(|l| l.strip_prefix(&format!("{name} ")))
                    .unwrap()
                    .trim(),
            )
        };
        let salt: Vec<u8> = (0..16).collect();
        let done = exchange("1234", &salt, &value("B"), &[0x11; 32]).unwrap();
        assert_eq!(done.public, value("A"));
        assert_eq!(done.key, value("K"));
        assert_eq!(done.proof, value("M1"));
        assert_eq!(done.expected, value("M2"));
        assert_ne!(
            exchange("1235", &salt, &value("B"), &[0x11; 32])
                .unwrap()
                .proof,
            value("M1")
        );
    }
}
