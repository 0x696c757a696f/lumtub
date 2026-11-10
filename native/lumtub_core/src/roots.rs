//! Which certificate authorities the core's HTTPS trusts: the system's
//! store (the default), or only Mozilla's list (the one Firefox ships) or
//! Google's (the Chrome Root Store). With a list of its own, a root
//! certificate someone added to the system is not trusted, and neither
//! is the root a proxy or security tool that inspects HTTPS installs.

use rustls::RootCertStore;
use rustls::pki_types::CertificateDer;
use rustls::pki_types::pem::PemObject;
use serde::Deserialize;
use std::sync::{Arc, LazyLock};

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

static MOZILLA: LazyLock<Arc<RootCertStore>> =
    LazyLock::new(|| store(webpki_root_certs::TLS_SERVER_ROOT_CERTS.iter().cloned()));
static GOOGLE: LazyLock<Arc<RootCertStore>> =
    LazyLock::new(|| store(CertificateDer::pem_slice_iter(CHROME).flatten()));

/// Android's own authorities, which every app trusts: one PEM file each in
/// /system/etc/security/cacerts (and the APEX copy that replaces it from
/// Android 14). Mozilla's list when neither can be read.
#[cfg(target_os = "android")]
static ANDROID: LazyLock<Arc<RootCertStore>> = LazyLock::new(|| {
    let mut certs = Vec::new();
    for folder in [
        "/apex/com.android.conscrypt/cacerts",
        "/system/etc/security/cacerts",
    ] {
        let Ok(entries) = std::fs::read_dir(folder) else {
            continue;
        };
        for entry in entries.flatten() {
            if let Ok(bytes) = std::fs::read(entry.path()) {
                certs.extend(CertificateDer::pem_slice_iter(&bytes).flatten());
            }
        }
        if !certs.is_empty() {
            break;
        }
    }
    if certs.is_empty() {
        return MOZILLA.clone();
    }
    store(certs)
});

/// Whether Android's own certificate check has the app's context
/// (tls::Java_io_github_lumtub_lumtub_MainActivity_initTls).
#[cfg(target_os = "android")]
static ANDROID_VERIFIER: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

#[cfg(target_os = "android")]
pub(crate) fn android_verifier_ready() {
    ANDROID_VERIFIER.store(true, std::sync::atomic::Ordering::SeqCst);
}

/// The authorities [roots] names, none for the system's own check
/// (rustls-platform-verifier). On Android, before that check is ready,
/// the system's store files.
pub(crate) fn list(roots: Roots) -> Option<Arc<RootCertStore>> {
    match roots {
        #[cfg(target_os = "android")]
        Roots::System if !ANDROID_VERIFIER.load(std::sync::atomic::Ordering::SeqCst) => {
            Some(ANDROID.clone())
        }
        Roots::System => None,
        Roots::Mozilla => Some(MOZILLA.clone()),
        Roots::Google => Some(GOOGLE.clone()),
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
        assert_eq!(
            GOOGLE.len(),
            String::from_utf8_lossy(CHROME)
                .matches("BEGIN CERTIFICATE")
                .count()
        );
    }

    #[test]
    fn chrome_certificates_match_their_hashes() {
        let text = String::from_utf8_lossy(CHROME);
        let hashes: Vec<&str> = text
            .lines()
            .filter_map(|l| l.strip_prefix("# "))
            .filter(|h| h.len() == 64)
            .collect();
        let certs: Vec<CertificateDer> = CertificateDer::pem_slice_iter(CHROME).flatten().collect();
        assert_eq!(hashes.len(), certs.len());
        for (hash, cert) in hashes.iter().zip(&certs) {
            let digest: String = Sha256::digest(cert.as_ref())
                .iter()
                .map(|b| format!("{b:02x}"))
                .collect();
            assert_eq!(&digest, hash);
        }
    }

    #[test]
    fn reads_the_setting() {
        for (json, roots) in [
            (r#""system""#, Roots::System),
            (r#""mozilla""#, Roots::Mozilla),
            (r#""google""#, Roots::Google),
        ] {
            assert_eq!(serde_json::from_str::<Roots>(json).unwrap(), roots);
        }
    }
}
