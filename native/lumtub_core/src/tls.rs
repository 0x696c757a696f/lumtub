//! The TLS of every HTTPS connection the core makes: rustls with aws-lc-rs,
//! TLS 1.2 and 1.3 only. With TLS 1.3 the key exchange offered first is
//! X25519MLKEM768, which stays secure even against a future quantum
//! computer as long as either half holds; servers that do not know it pick
//! X25519 or an elliptic curve instead. TLS 1.2 has no such exchange.
//!
//! The setting (抗量子加密) chooses: prefer the hybrid (the default), never
//! offer it, or require it, which leaves out TLS 1.2 and classic groups so
//! a server without it cannot be reached. The group each host agreed on is
//! kept and shown in the settings (lumtub_tls_seen).
//!
//! Only these connections are covered: libmpv, yt-dlp and the rest of the
//! system make their own.

use crate::roots::Roots;
use rustls::client::{
    ClientSessionMemoryCache, ClientSessionStore, Resumption, Tls12ClientSessionValue,
    Tls13ClientSessionValue,
};
use rustls::crypto::{CryptoProvider, SupportedKxGroup, aws_lc_rs};
use rustls::pki_types::ServerName;
use rustls::{ClientConfig, NamedGroup, SupportedProtocolVersion};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::os::raw::c_char;
use std::sync::{Arc, LazyLock, Mutex, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Deserialize, Clone, Copy, PartialEq, Eq, Hash, Debug, Default)]
#[serde(rename_all = "lowercase")]
pub enum Quantum {
    /// Offer the hybrid first, and classic groups and TLS 1.2 after it.
    #[default]
    Prefer,
    /// Offer only classic groups.
    Off,
    /// Offer only hybrid groups, over TLS 1.3.
    Require,
}

/// What a connection's TLS is set up from.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug, Default)]
pub struct Tls {
    pub roots: Roots,
    pub quantum: Quantum,
}

static CURRENT: RwLock<Tls> = RwLock::new(Tls {
    roots: Roots::System,
    quantum: Quantum::Prefer,
});

pub fn current() -> Tls {
    *CURRENT.read().unwrap_or_else(|e| e.into_inner())
}

pub fn set(tls: Tls) {
    *CURRENT.write().unwrap_or_else(|e| e.into_inner()) = tls;
}

/// Whether [group] is a hybrid with ML-KEM.
fn hybrid(group: NamedGroup) -> bool {
    matches!(
        group,
        NamedGroup::X25519MLKEM768 | NamedGroup::secp256r1MLKEM768
    )
}

/// The key exchange groups [quantum] offers, most wanted first.
fn groups(quantum: Quantum) -> Vec<&'static dyn SupportedKxGroup> {
    match quantum {
        Quantum::Prefer => aws_lc_rs::DEFAULT_KX_GROUPS.to_vec(),
        Quantum::Off => aws_lc_rs::DEFAULT_KX_GROUPS
            .iter()
            .filter(|g| !hybrid(g.name()))
            .copied()
            .collect(),
        Quantum::Require => aws_lc_rs::ALL_KX_GROUPS
            .iter()
            .filter(|g| hybrid(g.name()))
            .copied()
            .collect(),
    }
}

static TLS13_ONLY: &[&SupportedProtocolVersion] = &[&rustls::version::TLS13];
static TLS13_AND_12: &[&SupportedProtocolVersion] =
    &[&rustls::version::TLS13, &rustls::version::TLS12];

fn versions(quantum: Quantum) -> &'static [&'static SupportedProtocolVersion] {
    match quantum {
        Quantum::Require => TLS13_ONLY,
        _ => TLS13_AND_12,
    }
}

pub fn provider(quantum: Quantum) -> CryptoProvider {
    CryptoProvider {
        kx_groups: groups(quantum),
        ..aws_lc_rs::default_provider()
    }
}

/// What a host last agreed on.
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Seen {
    pub host: String,
    /// `X25519MLKEM768`, `X25519`, … or `TLS 1.2`, which has no hybrid.
    pub group: String,
    pub quantum: bool,
    /// Seconds since 1970.
    pub at: u64,
}

static SEEN: LazyLock<Mutex<HashMap<String, Seen>>> = LazyLock::new(Default::default);
/// More hosts than the settings would ever show.
const SEEN_LIMIT: usize = 200;

fn name(group: NamedGroup) -> String {
    match group {
        NamedGroup::X25519MLKEM768 => "X25519MLKEM768".into(),
        NamedGroup::secp256r1MLKEM768 => "SecP256r1MLKEM768".into(),
        NamedGroup::X25519 => "X25519".into(),
        NamedGroup::secp256r1 => "P-256".into(),
        NamedGroup::secp384r1 => "P-384".into(),
        other => format!("{other:?}"),
    }
}

fn host(server: &ServerName<'_>) -> String {
    match server {
        ServerName::DnsName(name) => name.as_ref().to_string(),
        ServerName::IpAddress(ip) => std::net::IpAddr::from(*ip).to_string(),
        _ => String::new(),
    }
}

fn note(server: &ServerName<'_>, group: String, quantum: bool) {
    let host = host(server);
    if host.is_empty() {
        return;
    }
    let at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    let mut seen = SEEN.lock().unwrap_or_else(|e| e.into_inner());
    if seen.len() >= SEEN_LIMIT
        && !seen.contains_key(&host)
        && let Some(oldest) = seen.values().min_by_key(|s| s.at).map(|s| s.host.clone())
    {
        seen.remove(&oldest);
    }
    seen.insert(
        host.clone(),
        Seen {
            host,
            group,
            quantum,
            at,
        },
    );
}

/// What each host agreed on, newest first.
pub fn seen() -> Vec<Seen> {
    let mut list: Vec<Seen> = SEEN
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .values()
        .cloned()
        .collect();
    list.sort_by(|a, b| b.at.cmp(&a.at).then_with(|| a.host.cmp(&b.host)));
    list
}

/// The session cache, noting the group of every finished TLS 1.3
/// handshake (rustls passes it on once the server's certificate has been
/// checked) and every TLS 1.2 session.
#[derive(Debug)]
struct Noting(ClientSessionMemoryCache);

impl ClientSessionStore for Noting {
    fn set_kx_hint(&self, server: ServerName<'static>, group: NamedGroup) {
        note(&server, name(group), hybrid(group));
        self.0.set_kx_hint(server, group);
    }

    fn kx_hint(&self, server: &ServerName<'_>) -> Option<NamedGroup> {
        self.0.kx_hint(server)
    }

    fn set_tls12_session(&self, server: ServerName<'static>, value: Tls12ClientSessionValue) {
        note(&server, "TLS 1.2".into(), false);
        self.0.set_tls12_session(server, value);
    }

    fn tls12_session(&self, server: &ServerName<'_>) -> Option<Tls12ClientSessionValue> {
        self.0.tls12_session(server)
    }

    fn remove_tls12_session(&self, server: &ServerName<'static>) {
        self.0.remove_tls12_session(server);
    }

    fn insert_tls13_ticket(&self, server: ServerName<'static>, value: Tls13ClientSessionValue) {
        self.0.insert_tls13_ticket(server, value);
    }

    fn take_tls13_ticket(&self, server: &ServerName<'static>) -> Option<Tls13ClientSessionValue> {
        self.0.take_tls13_ticket(server)
    }
}

/// The client configuration for [tls].
pub fn config(tls: Tls) -> Result<ClientConfig, rustls::Error> {
    config_trusting(tls.quantum, crate::roots::list(tls.roots))
}

/// The client configuration for [quantum], trusting [roots], or the
/// system's own check when none.
fn config_trusting(
    quantum: Quantum,
    roots: Option<Arc<rustls::RootCertStore>>,
) -> Result<ClientConfig, rustls::Error> {
    let builder = ClientConfig::builder_with_provider(Arc::new(provider(quantum)))
        .with_protocol_versions(versions(quantum))?;
    let mut config = match roots {
        Some(list) => builder.with_root_certificates(list).with_no_client_auth(),
        None => {
            use rustls_platform_verifier::BuilderVerifierExt;
            builder.with_platform_verifier()?.with_no_client_auth()
        }
    };
    config.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];
    config.resumption = Resumption::store(Arc::new(Noting(ClientSessionMemoryCache::new(256))));
    Ok(config)
}

/// [builder] with the TLS of [tls]. Should that fail, with no
/// certificate trusted, so it never connects with less.
pub fn apply(builder: reqwest::ClientBuilder, tls: Tls) -> reqwest::ClientBuilder {
    // So a client built without this still has a provider: reqwest has
    // no certificates of its own, so it trusts nothing.
    static DEFAULT: std::sync::Once = std::sync::Once::new();
    DEFAULT.call_once(|| {
        let _ = aws_lc_rs::default_provider().install_default();
    });
    match config(tls) {
        Ok(config) => builder.tls_backend_preconfigured(config),
        Err(e) => {
            eprintln!("lumtub: TLS could not be set up ({e}); HTTPS will fail");
            builder.tls_backend_rustls().tls_certs_only(Vec::new())
        }
    }
}

/// What each host agreed on, as JSON `[{"host", "group", "quantum", "at"}]`,
/// newest first. Free it with lumtub_string_free.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_tls_seen() -> *mut c_char {
    crate::taste::give_json(&seen())
}

/// Gives the Android certificate check the app's context; called once from
/// MainActivity before the core's first HTTPS request. Until then, and
/// should it fail, System reads Android's store files instead.
#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_io_github_lumtub_lumtub_MainActivity_initTls<'caller>(
    mut env: jni::EnvUnowned<'caller>,
    _activity: jni::objects::JObject<'caller>,
    context: jni::objects::JObject<'caller>,
) {
    let ready = env
        .with_env(|env| -> Result<bool, jni::errors::Error> {
            rustls_platform_verifier::android::init_with_env(env, context)?;
            Ok(true)
        })
        .resolve::<jni::errors::LogErrorAndDefault>();
    if ready {
        crate::roots::android_verifier_ready();
    }
}

#[cfg(test)]
#[path = "tls_tests.rs"]
mod tests;
