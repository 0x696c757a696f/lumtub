//! 加密 DNS: host names looked up over DNS-over-HTTPS (RFC 8484) instead of
//! the system resolver, for the app's requests and the stream relay. The
//! query goes through the same pooled client and system TLS as everything
//! else; hickory-proto only builds and reads the DNS messages. Answers are
//! cached for their TTL. When the server cannot be reached the system
//! resolver answers instead, as browsers do, so a blocked server never
//! takes the app offline. Through a proxy, names are the proxy's to look up
//! and none of this runs.

use std::collections::HashMap;
use std::ffi::c_char;
use std::net::{IpAddr, SocketAddr, ToSocketAddrs};
use std::sync::{Arc, LazyLock, Mutex, RwLock};
use std::time::{Duration, Instant};

use hickory_proto::op::{Message, Query, ResponseCode};
use hickory_proto::rr::{Name, RData, RecordType};
use serde::Deserialize;

use crate::taste::{give, text};

/// TTLs are held to this range: short ones would query on nearly every
/// request, long ones would keep an address a CDN has moved away from.
const MIN_TTL: u64 = 60;
const MAX_TTL: u64 = 3600;
const KEEP: usize = 512;

#[derive(Deserialize, Default, Clone, PartialEq, Debug)]
pub struct Settings {
    /// `https://host/dns-query`; none to use the system resolver.
    pub url: Option<String>,
    /// Addresses of the server's host, so finding the server needs no DNS.
    #[serde(default)]
    pub bootstrap: Vec<String>,
}

pub struct Doh {
    url: String,
    client: reqwest::Client,
    cache: Mutex<HashMap<String, (Vec<IpAddr>, Instant)>>,
}

/// Why a lookup failed: the name does not exist, or the server did not answer.
#[derive(Debug, PartialEq)]
pub enum Failure {
    NoSuchName,
    Server(String),
}

impl Doh {
    pub fn new(settings: &Settings) -> Option<Doh> {
        let url = settings.url.as_deref()?.trim();
        let parsed = reqwest::Url::parse(url).ok()?;
        if parsed.scheme() != "https" {
            return None;
        }
        let mut builder = reqwest::Client::builder()
            .no_proxy()
            .connect_timeout(Duration::from_secs(5))
            .timeout(Duration::from_secs(8))
            .pool_idle_timeout(Duration::from_secs(120))
            .http2_adaptive_window(true);
        if let Some(host) = parsed.host_str() {
            let addrs: Vec<SocketAddr> =
                settings.bootstrap.iter().filter_map(|a| a.trim().parse::<IpAddr>().ok()).map(|ip| SocketAddr::new(ip, parsed.port_or_known_default().unwrap_or(443))).collect();
            if !addrs.is_empty() {
                builder = builder.resolve_to_addrs(host, &addrs);
            }
        }
        Some(Doh { url: url.to_string(), client: builder.build().ok()?, cache: Mutex::new(HashMap::new()) })
    }

    async fn ask(&self, name: &Name, kind: RecordType) -> Result<(Vec<IpAddr>, u64), Failure> {
        let mut message = Message::query();
        // RFC 8484 asks for id 0, so answers can be cached by HTTP caches.
        message.metadata.id = 0;
        message.metadata.recursion_desired = true;
        message.add_query(Query::query(name.clone(), kind));
        let body = message.to_vec().map_err(|e| Failure::Server(e.to_string()))?;
        let reply = self
            .client
            .post(&self.url)
            .header("content-type", "application/dns-message")
            .header("accept", "application/dns-message")
            .body(body)
            .send()
            .await
            .map_err(|e| Failure::Server(e.to_string()))?;
        if !reply.status().is_success() {
            return Err(Failure::Server(format!("HTTP {}", reply.status().as_u16())));
        }
        let bytes = reply.bytes().await.map_err(|e| Failure::Server(e.to_string()))?;
        read_answer(&bytes)
    }

    /// The addresses of [host], A and AAAA asked for together.
    pub async fn lookup(&self, host: &str) -> Result<Vec<IpAddr>, Failure> {
        let key = host.trim_end_matches('.').to_ascii_lowercase();
        if let Some((ips, until)) = self.cache.lock().unwrap_or_else(|e| e.into_inner()).get(&key)
            && *until > Instant::now()
        {
            return Ok(ips.clone());
        }
        let name = Name::from_utf8(format!("{key}.")).map_err(|e| Failure::Server(e.to_string()))?;
        let (v4, v6) = tokio::join!(self.ask(&name, RecordType::A), self.ask(&name, RecordType::AAAA));
        let mut ips = Vec::new();
        let mut ttl = MAX_TTL;
        let mut failure = None;
        // IPv4 first: many home networks have IPv6 addresses that go nowhere.
        for answer in [v4, v6] {
            match answer {
                Ok((found, t)) => {
                    ttl = ttl.min(t);
                    ips.extend(found);
                }
                Err(e) => failure = failure.or(Some(e)),
            }
        }
        if ips.is_empty() {
            return Err(failure.unwrap_or(Failure::NoSuchName));
        }
        let mut cache = self.cache.lock().unwrap_or_else(|e| e.into_inner());
        if cache.len() >= KEEP {
            let now = Instant::now();
            cache.retain(|_, (_, until)| *until > now);
            if cache.len() >= KEEP {
                cache.clear();
            }
        }
        cache.insert(key, (ips.clone(), Instant::now() + Duration::from_secs(ttl)));
        Ok(ips)
    }
}

/// The addresses in a DNS answer and the shortest TTL among them, held to
/// [MIN_TTL]..[MAX_TTL]. An empty answer is not a failure (a host may have
/// only IPv4); a name that does not exist is.
fn read_answer(bytes: &[u8]) -> Result<(Vec<IpAddr>, u64), Failure> {
    let message = Message::from_vec(bytes).map_err(|e| Failure::Server(e.to_string()))?;
    match message.metadata.response_code {
        ResponseCode::NoError => {}
        ResponseCode::NXDomain => return Err(Failure::NoSuchName),
        code => return Err(Failure::Server(format!("{code:?}"))),
    }
    let mut ips = Vec::new();
    let mut ttl = MAX_TTL;
    for record in &message.answers {
        let ip = match &record.data {
            RData::A(a) => IpAddr::V4(a.0),
            RData::AAAA(a) => IpAddr::V6(a.0),
            _ => continue,
        };
        ttl = ttl.min(u64::from(record.ttl));
        ips.push(ip);
    }
    Ok((ips, ttl.clamp(MIN_TTL, MAX_TTL)))
}

static CURRENT: RwLock<Option<Arc<Doh>>> = RwLock::new(None);
static SETTINGS: LazyLock<Mutex<Settings>> = LazyLock::new(|| Mutex::new(Settings::default()));

pub fn current() -> Option<Arc<Doh>> {
    CURRENT.read().unwrap_or_else(|e| e.into_inner()).clone()
}

/// Switches to [settings]; returns whether anything changed.
pub fn set(settings: Settings) -> bool {
    let mut old = SETTINGS.lock().unwrap_or_else(|e| e.into_inner());
    if *old == settings {
        return false;
    }
    *CURRENT.write().unwrap_or_else(|e| e.into_inner()) = Doh::new(&settings).map(Arc::new);
    *old = settings;
    true
}

fn system(host: &str, port: u16) -> std::io::Result<Vec<SocketAddr>> {
    Ok((host, port).to_socket_addrs()?.collect())
}

/// [host] over [doh], or the system's answer when the server fails.
async fn resolve(doh: Arc<Doh>, host: String, port: u16) -> std::io::Result<Vec<SocketAddr>> {
    if let Ok(ip) = host.parse::<IpAddr>() {
        return Ok(vec![SocketAddr::new(ip, port)]);
    }
    match doh.lookup(&host).await {
        Ok(ips) => Ok(ips.into_iter().map(|ip| SocketAddr::new(ip, port)).collect()),
        Err(Failure::NoSuchName) => Err(std::io::Error::new(std::io::ErrorKind::NotFound, format!("{host} does not exist"))),
        Err(Failure::Server(_)) => tokio::task::spawn_blocking(move || system(&host, port)).await.map_err(std::io::Error::other)?,
    }
}

/// [Doh] for reqwest.
pub struct Resolver(pub Arc<Doh>);

impl reqwest::dns::Resolve for Resolver {
    fn resolve(&self, name: reqwest::dns::Name) -> reqwest::dns::Resolving {
        let doh = self.0.clone();
        let host = name.as_str().to_string();
        Box::pin(async move {
            let addrs = resolve(doh, host, 0).await?;
            Ok(Box::new(addrs.into_iter()) as reqwest::dns::Addrs)
        })
    }
}

/// [Doh] for ureq, which the relay's threads call outside any runtime.
#[derive(Debug, Default)]
pub struct BlockingResolver;

impl ureq::unversioned::resolver::Resolver for BlockingResolver {
    fn resolve(
        &self,
        uri: &ureq::http::Uri,
        config: &ureq::config::Config,
        timeout: ureq::unversioned::transport::NextTimeout,
    ) -> Result<ureq::unversioned::resolver::ResolvedSocketAddrs, ureq::Error> {
        let fallback = || ureq::unversioned::resolver::DefaultResolver::default().resolve(uri, config, timeout);
        let (Some(doh), Some(host)) = (current(), uri.host()) else {
            return fallback();
        };
        let host = host.trim_start_matches('[').trim_end_matches(']').to_string();
        if host.parse::<IpAddr>().is_ok() {
            return fallback();
        }
        let port = uri.port_u16().unwrap_or(if uri.scheme_str() == Some("http") { 80 } else { 443 });
        match crate::http::runtime().block_on(doh.lookup(&host)) {
            Ok(ips) => {
                let mut out = BlockingResolver.empty();
                for ip in ips {
                    if out.try_push(SocketAddr::new(ip, port)).is_err() {
                        break;
                    }
                }
                Ok(out)
            }
            Err(Failure::NoSuchName) => Err(ureq::Error::HostNotFound),
            Err(Failure::Server(_)) => fallback(),
        }
    }
}

/// Looks [host] up over the DoH server in JSON `{"url", "bootstrap"}`,
/// without the system fallback, for the settings page's test. Answers
/// `{"ok": true, "addresses": […], "ms": n}` or `{"ok": false, "error": "…"}`.
/// Blocks until the server answers or gives up.
///
/// # Safety
/// [json] and [host] must point to their lengths of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_dns_test(json: *const u8, length: usize, host: *const u8, host_length: usize) -> *mut c_char {
    let settings: Settings = serde_json::from_str(unsafe { text(json, length) }).unwrap_or_default();
    let host = unsafe { text(host, host_length) }.to_string();
    let answer = match Doh::new(&settings) {
        None => serde_json::json!({"ok": false, "error": "not an https:// address"}),
        Some(doh) => {
            let started = Instant::now();
            match crate::http::runtime().block_on(doh.lookup(&host)) {
                Ok(ips) => serde_json::json!({
                    "ok": true,
                    "addresses": ips.iter().map(|ip| ip.to_string()).collect::<Vec<_>>(),
                    "ms": started.elapsed().as_millis() as u64,
                }),
                Err(Failure::NoSuchName) => serde_json::json!({"ok": false, "error": format!("{host} does not exist")}),
                Err(Failure::Server(e)) => serde_json::json!({"ok": false, "error": e}),
            }
        }
    };
    give(answer.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    use hickory_proto::op::{MessageType, OpCode};
    use hickory_proto::rr::Record;
    use hickory_proto::rr::rdata::{A, AAAA, CNAME};

    fn reply(code: ResponseCode, answers: Vec<Record>) -> Vec<u8> {
        let mut message = Message::new(0, MessageType::Response, OpCode::Query);
        message.metadata.response_code = code;
        message.answers = answers;
        message.to_vec().unwrap()
    }

    #[test]
    fn reads_addresses_and_ttl() {
        let name = Name::from_ascii("www.youtube.com.").unwrap();
        let bytes = reply(
            ResponseCode::NoError,
            vec![
                Record::from_rdata(name.clone(), 300, RData::CNAME(CNAME(Name::from_ascii("youtube-ui.l.google.com.").unwrap()))),
                Record::from_rdata(name.clone(), 120, RData::A(A::new(142, 250, 1, 1))),
                Record::from_rdata(name.clone(), 5, RData::AAAA(AAAA::new(0x2404, 0x6800, 0, 0, 0, 0, 0, 1))),
            ],
        );
        let (ips, ttl) = read_answer(&bytes).unwrap();
        assert_eq!(ips, vec!["142.250.1.1".parse::<IpAddr>().unwrap(), "2404:6800::1".parse().unwrap()]);
        assert_eq!(ttl, MIN_TTL);
        assert_eq!(read_answer(&reply(ResponseCode::NXDomain, vec![])), Err(Failure::NoSuchName));
        assert!(matches!(read_answer(&reply(ResponseCode::ServFail, vec![])), Err(Failure::Server(_))));
        assert!(matches!(read_answer(b"junk"), Err(Failure::Server(_))));
        assert_eq!(read_answer(&reply(ResponseCode::NoError, vec![])), Ok((vec![], MAX_TTL)));
    }

    #[test]
    fn needs_an_https_address() {
        assert!(Doh::new(&Settings::default()).is_none());
        assert!(Doh::new(&Settings { url: Some("http://1.1.1.1/dns-query".into()), bootstrap: vec![] }).is_none());
        assert!(Doh::new(&Settings { url: Some("https://cloudflare-dns.com/dns-query".into()), bootstrap: vec!["1.1.1.1".into(), "bad".into()] }).is_some());
    }

    #[test]
    fn asks_the_server_and_caches() {
        use std::io::{BufRead, BufReader, Read, Write};
        // A plain-HTTP server stands in; Doh only checks the scheme in new().
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let served = Arc::new(AtomicU64::new(0));
        let count = served.clone();
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let mut stream = stream.unwrap();
                let count = count.clone();
                std::thread::spawn(move || {
                    let mut reader = BufReader::new(stream.try_clone().unwrap());
                    loop {
                        let mut length = 0;
                        loop {
                            let mut line = String::new();
                            if reader.read_line(&mut line).unwrap_or(0) == 0 {
                                return;
                            }
                            if let Some(v) = line.to_ascii_lowercase().strip_prefix("content-length:") {
                                length = v.trim().parse().unwrap();
                            }
                            if line == "\r\n" {
                                break;
                            }
                        }
                        let mut body = vec![0; length];
                        reader.read_exact(&mut body).unwrap();
                        count.fetch_add(1, Ordering::SeqCst);
                        let query = Message::from_vec(&body).unwrap();
                        let q = &query.queries[0];
                        let answers = match q.query_type() {
                            RecordType::A => vec![Record::from_rdata(q.name().clone(), 600, RData::A(A::new(10, 0, 0, 7)))],
                            _ => vec![],
                        };
                        let out = reply(ResponseCode::NoError, answers);
                        let head = format!("HTTP/1.1 200 OK\r\ncontent-type: application/dns-message\r\ncontent-length: {}\r\n\r\n", out.len());
                        stream.write_all(head.as_bytes()).unwrap();
                        stream.write_all(&out).unwrap();
                    }
                });
            }
        });
        let mut doh = Doh::new(&Settings { url: Some("https://localhost/dns-query".into()), bootstrap: vec![] }).unwrap();
        doh.url = format!("http://127.0.0.1:{port}/dns-query");
        let runtime = crate::http::runtime();
        assert_eq!(runtime.block_on(doh.lookup("Example.COM")).unwrap(), vec!["10.0.0.7".parse::<IpAddr>().unwrap()]);
        assert_eq!(served.load(Ordering::SeqCst), 2);
        assert_eq!(runtime.block_on(doh.lookup("example.com.")).unwrap().len(), 1);
        assert_eq!(served.load(Ordering::SeqCst), 2, "the second lookup is cached");
        let addrs = runtime.block_on(resolve(Arc::new(doh), "example.org".into(), 443)).unwrap();
        assert_eq!(addrs, vec!["10.0.0.7:443".parse().unwrap()]);
    }
}
