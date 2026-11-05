//! Which certificate authorities the core's HTTPS trusts: the system's
//! store (the default), or only Mozilla's list (the one Firefox ships) or
//! Google's (the Chrome Root Store). With a list of its own, a root
//! certificate someone added to the system is not trusted, and neither
//! is the root a proxy or security tool that inspects HTTPS installs.

use rustls::RootCertStore;
use rustls::pki_types::CertificateDer;
use rustls::pki_types::pem::PemObject;
use serde::Deserialize;
use std::sync::{Arc, LazyLock, RwLock};

#[derive(Deserialize, Clone, Copy, PartialEq, Eq, Hash, Debug, Default)]
#[serde(rename_all = "lowercase")]
pub enum Roots {
    #[default]
    System,
    Mozilla,
    Google,
}

/// The Chrome Root Store, refreshed with the lockfiles (roots/update-chrome.sh).
const CHROME: &[u8] = include_bytes!("../roots/chrome.pem");

fn store(certs: impl IntoIterator<Item = CertificateDer<'static>>) -> Arc<RootCertStore> {
    let mut store = RootCertStore::empty();
    store.add_parsable_certificates(certs);
    Arc::new(store)
}

static MOZILLA: LazyLock<Arc<RootCertStore>> = LazyLock::new(|| store(webpki_root_certs::TLS_SERVER_ROOT_CERTS.iter().cloned()));
static GOOGLE: LazyLock<Arc<RootCertStore>> = LazyLock::new(|| store(CertificateDer::pem_slice_iter(CHROME).flatten()));

static CURRENT: RwLock<Roots> = RwLock::new(Roots::System);

pub fn current() -> Roots {
    *CURRENT.read().unwrap_or_else(|e| e.into_inner())
}

/// Switches to [roots]; returns whether it changed.
pub fn set(roots: Roots) -> bool {
    let mut current = CURRENT.write().unwrap_or_else(|e| e.into_inner());
    let changed = *current != roots;
    *current = roots;
    changed
}

/// The authorities [roots] names, none for the system's.
fn list(roots: Roots) -> Option<Arc<RootCertStore>> {
    match roots {
        Roots::System => None,
        Roots::Mozilla => Some(MOZILLA.clone()),
        Roots::Google => Some(GOOGLE.clone()),
    }
}

/// [builder] trusting [roots]: unchanged for the system's store, else
/// rustls with only that list.
pub fn apply(builder: reqwest::ClientBuilder, roots: Roots) -> reqwest::ClientBuilder {
    let Some(list) = list(roots) else { return builder };
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    match rustls::ClientConfig::builder_with_provider(provider).with_safe_default_protocol_versions() {
        Ok(config) => {
            let mut config = config.with_root_certificates(list).with_no_client_auth();
            config.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];
            builder.tls_backend_preconfigured(config)
        }
        // Never the system's store in its place: trust nothing instead.
        Err(_) => {
            let _ = rustls::crypto::ring::default_provider().install_default();
            builder.tls_backend_rustls().tls_certs_only(Vec::new())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};

    #[test]
    fn reads_both_lists() {
        assert!(MOZILLA.len() > 100, "{}", MOZILLA.len());
        assert!(GOOGLE.len() > 50, "{}", GOOGLE.len());
        assert_eq!(GOOGLE.len(), String::from_utf8_lossy(CHROME).matches("BEGIN CERTIFICATE").count());
    }

    #[test]
    fn chrome_certificates_match_their_hashes() {
        let text = String::from_utf8_lossy(CHROME);
        let hashes: Vec<&str> = text.lines().filter_map(|l| l.strip_prefix("# ")).filter(|h| h.len() == 64).collect();
        let certs: Vec<CertificateDer> = CertificateDer::pem_slice_iter(CHROME).flatten().collect();
        assert_eq!(hashes.len(), certs.len());
        for (hash, cert) in hashes.iter().zip(&certs) {
            let digest: String = Sha256::digest(cert.as_ref()).iter().map(|b| format!("{b:02x}")).collect();
            assert_eq!(&digest, hash);
        }
    }

    #[test]
    fn reads_the_setting() {
        for (json, roots) in [(r#""system""#, Roots::System), (r#""mozilla""#, Roots::Mozilla), (r#""google""#, Roots::Google)] {
            assert_eq!(serde_json::from_str::<Roots>(json).unwrap(), roots);
        }
        for roots in [Roots::System, Roots::Mozilla, Roots::Google] {
            assert!(apply(reqwest::Client::builder(), roots).build().is_ok());
        }
    }
}
