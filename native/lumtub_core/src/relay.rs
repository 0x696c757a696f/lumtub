//! A loopback HTTP server libmpv reads YouTube streams through. YouTube
//! throttles a request for more than about 10 MB of a stream to a crawl,
//! and libmpv asks for the whole rest of the file at once; the relay
//! answers each libmpv request by fetching the stream in smaller pieces
//! with YouTube's own `range` parameter, as yt-dlp and the YouTube website
//! do. Only addresses the app registered are served, only on 127.0.0.1.
//!
//! Every connection runs on its own thread, so the stream's bytes never
//! pass through Dart. TLS is the operating system's (SChannel on Windows).

use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::{HashMap, VecDeque};
use std::io::{BufRead, BufReader, ErrorKind, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::os::raw::c_char;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Bytes fetched from YouTube per request.
pub const CHUNK: u64 = 9 << 20;
/// Registered streams kept; older ones stop being served.
const KEEP: usize = 16;
/// Log lines kept until the app reads them.
const LOG_KEEP: usize = 200;

#[derive(Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Target {
    pub url: String,
    pub size: u64,
    #[serde(default)]
    pub user_agent: Option<String>,
    #[serde(default)]
    pub mime: Option<String>,
    /// `http://host:port` to fetch through, none for a direct connection.
    #[serde(default)]
    pub proxy: Option<String>,
    /// Bytes fetched from YouTube per request.
    #[serde(default = "chunk")]
    pub chunk: u64,
}

fn chunk() -> u64 {
    CHUNK
}

#[derive(Default)]
struct Shared {
    targets: HashMap<String, Target>,
    order: VecDeque<String>,
    log: VecDeque<String>,
}

pub struct Relay {
    port: u16,
    shared: Arc<Mutex<Shared>>,
}

/// What the relay reads from YouTube: the reply's status and body.
pub trait Fetch: Send + Sync {
    fn get(&self, target: &Target, url: &str) -> Result<(u16, Box<dyn Read + Send>), String>;
}

/// HTTP with the operating system's TLS, one agent per proxy.
#[derive(Default)]
pub struct Web {
    agents: Mutex<HashMap<Option<String>, ureq::Agent>>,
}

impl Web {
    fn agent(&self, proxy: &Option<String>) -> Result<ureq::Agent, String> {
        let mut agents = self.agents.lock().unwrap();
        if let Some(agent) = agents.get(proxy) {
            return Ok(agent.clone());
        }
        let proxy_config = match proxy {
            Some(p) => Some(ureq::Proxy::new(p).map_err(|e| e.to_string())?),
            None => None,
        };
        let agent: ureq::Agent = ureq::Agent::config_builder()
            .http_status_as_error(false)
            .proxy(proxy_config)
            .tls_config(ureq::tls::TlsConfig::builder().provider(ureq::tls::TlsProvider::NativeTls).build())
            .timeout_connect(Some(Duration::from_secs(15)))
            .timeout_recv_response(Some(Duration::from_secs(20)))
            .build()
            .into();
        agents.insert(proxy.clone(), agent.clone());
        Ok(agent)
    }
}

impl Fetch for Web {
    fn get(&self, target: &Target, url: &str) -> Result<(u16, Box<dyn Read + Send>), String> {
        let agent = self.agent(&target.proxy)?;
        let mut request = agent.get(url);
        if let Some(ua) = &target.user_agent {
            request = request.header("User-Agent", ua);
        }
        let reply = request.call().map_err(|e| e.to_string())?;
        let status = reply.status().as_u16();
        Ok((status, Box::new(reply.into_body().into_reader())))
    }
}

impl Relay {
    /// Listens on a random loopback port.
    pub fn start(fetch: Arc<dyn Fetch>) -> std::io::Result<Relay> {
        let listener = TcpListener::bind("127.0.0.1:0")?;
        let port = listener.local_addr()?.port();
        let shared = Arc::new(Mutex::new(Shared::default()));
        let relay = Relay { port, shared: shared.clone() };
        std::thread::Builder::new().name("relay".into()).spawn(move || {
            for client in listener.incoming().flatten() {
                let shared = shared.clone();
                let fetch = fetch.clone();
                let _ = std::thread::Builder::new().name("relay-client".into()).spawn(move || serve(client, &shared, fetch.as_ref()));
            }
        })?;
        Ok(relay)
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    /// A loopback address that serves [target], or none when its size is
    /// unknown (it is needed for seeking).
    pub fn register(&self, mut target: Target) -> Option<String> {
        if target.size == 0 || target.url.is_empty() || target.chunk == 0 {
            return None;
        }
        if target.mime.is_none() {
            target.mime = query(&target.url, "mime");
        }
        let token = token(&target.url);
        let mut shared = self.shared.lock().unwrap();
        shared.targets.insert(token.clone(), target);
        shared.order.push_back(token.clone());
        while shared.order.len() > KEEP {
            if let Some(old) = shared.order.pop_front() {
                shared.targets.remove(&old);
            }
        }
        Some(format!("http://127.0.0.1:{}/{}", self.port, token))
    }

    /// The log lines since the last call.
    pub fn take_log(&self) -> Vec<String> {
        self.shared.lock().unwrap().log.drain(..).collect()
    }
}

fn log(shared: &Mutex<Shared>, line: String) {
    let mut shared = shared.lock().unwrap();
    if shared.log.len() >= LOG_KEEP {
        shared.log.pop_front();
    }
    shared.log.push_back(line);
}

fn token(url: &str) -> String {
    static COUNT: AtomicU64 = AtomicU64::new(0);
    let mut hash = Sha256::new();
    hash.update(SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_nanos().to_le_bytes());
    hash.update(COUNT.fetch_add(1, Ordering::Relaxed).to_le_bytes());
    hash.update(std::process::id().to_le_bytes());
    hash.update(url.as_bytes());
    hash.finalize().iter().take(8).map(|b| format!("{b:02x}")).collect()
}

/// The value of [name] in [url]'s query, percent-decoded.
fn query(url: &str, name: &str) -> Option<String> {
    let query = url.split_once('?')?.1.split('#').next()?;
    query.split('&').find_map(|pair| {
        let (key, value) = pair.split_once('=')?;
        (key == name).then(|| decode(value))
    })
}

fn decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'%' if i + 2 < bytes.len() => match std::str::from_utf8(&bytes[i + 1..i + 3]).ok().and_then(|h| u8::from_str_radix(h, 16).ok()) {
                Some(b) => {
                    out.push(b);
                    i += 3;
                    continue;
                }
                None => out.push(b'%'),
            },
            b'+' => out.push(b' '),
            b => out.push(b),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// What a `Range` header asks for out of a stream's bytes.
#[derive(Debug, PartialEq)]
pub enum Range {
    Whole,
    /// The first and last byte.
    Part(u64, u64),
    Unsatisfiable,
}

pub fn byte_range(header: Option<&str>, size: u64) -> Range {
    let Some(spec) = header.and_then(|h| h.trim().strip_prefix("bytes=")) else {
        return Range::Whole;
    };
    let Some((from, to)) = spec.split_once('-') else {
        return Range::Whole;
    };
    if !from.chars().all(|c| c.is_ascii_digit()) || !to.chars().all(|c| c.is_ascii_digit()) {
        return Range::Whole;
    }
    let from: Option<u64> = from.parse().ok();
    let to: Option<u64> = to.parse().ok();
    let (start, end) = match (from, to) {
        (None, Some(suffix)) => (size.saturating_sub(suffix), size - 1),
        (start, to) => (start.unwrap_or(0), to.map_or(size - 1, |t| t.min(size - 1))),
    };
    if start >= size || start > end { Range::Unsatisfiable } else { Range::Part(start, end) }
}

/// Answers the requests on one connection from libmpv.
fn serve(client: TcpStream, shared: &Mutex<Shared>, fetch: &dyn Fetch) {
    let _ = client.set_nodelay(true);
    let Ok(writer) = client.try_clone() else { return };
    let mut reader = BufReader::new(client);
    let mut writer = writer;
    loop {
        let Some((method, path, headers)) = read_request(&mut reader) else { return };
        let keep_open = !headers.get("connection").is_some_and(|v| v.eq_ignore_ascii_case("close"));
        let target = shared.lock().unwrap().targets.get(path.trim_start_matches('/')).cloned();
        let Some(target) = target.filter(|_| method == "GET" || method == "HEAD") else {
            let _ = writer.write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
            if !keep_open {
                return;
            }
            continue;
        };
        let size = target.size;
        let (status, start, end) = match byte_range(headers.get("range").map(String::as_str), size) {
            Range::Whole => ("200 OK", 0, size - 1),
            Range::Part(s, e) => ("206 Partial Content", s, e),
            Range::Unsatisfiable => {
                let _ = write!(writer, "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */{size}\r\nContent-Length: 0\r\n\r\n");
                if !keep_open {
                    return;
                }
                continue;
            }
        };
        let mut head = format!("HTTP/1.1 {status}\r\nAccept-Ranges: bytes\r\nContent-Length: {}\r\n", end - start + 1);
        if status.starts_with("206") {
            head.push_str(&format!("Content-Range: bytes {start}-{end}/{size}\r\n"));
        }
        if let Some(mime) = &target.mime {
            head.push_str(&format!("Content-Type: {mime}\r\n"));
        }
        head.push_str(if keep_open { "Connection: keep-alive\r\n\r\n" } else { "Connection: close\r\n\r\n" });
        if writer.write_all(head.as_bytes()).is_err() {
            return;
        }
        if method == "HEAD" {
            if !keep_open {
                return;
            }
            continue;
        }
        let mut position = start;
        while position <= end {
            let last = (position + target.chunk - 1).min(end);
            match copy(fetch, &target, position, last, &mut writer, shared) {
                Ok(()) => position = last + 1,
                Err(Stop::Client) => return,
                Err(Stop::Upstream(message)) => {
                    log(shared, format!("Chunked relay stopped: {message}"));
                    return;
                }
            }
        }
        let _ = writer.flush();
        if !keep_open {
            return;
        }
    }
}

type Request = (String, String, HashMap<String, String>);

fn read_request(reader: &mut BufReader<TcpStream>) -> Option<Request> {
    let mut line = String::new();
    let mut total = 0;
    reader.read_line(&mut line).ok().filter(|&n| n > 0)?;
    let mut parts = line.split_whitespace();
    let method = parts.next()?.to_string();
    let path = parts.next()?.to_string();
    let mut headers = HashMap::new();
    loop {
        let mut header = String::new();
        let n = reader.read_line(&mut header).ok()?;
        total += n;
        if n == 0 || total > 32 << 10 {
            return None;
        }
        let header = header.trim_end();
        if header.is_empty() {
            break;
        }
        if let Some((name, value)) = header.split_once(':') {
            headers.insert(name.trim().to_ascii_lowercase(), value.trim().to_string());
        }
    }
    Some((method, path, headers))
}

enum Stop {
    /// libmpv hung up, most often to seek.
    Client,
    /// YouTube's side failed.
    Upstream(String),
}

/// Sends bytes [from] to [to] of [target]. A reply YouTube cuts short is
/// continued from the next missing byte; libmpv sees one unbroken reply.
fn copy(fetch: &dyn Fetch, target: &Target, from: u64, to: u64, into: &mut impl Write, shared: &Mutex<Shared>) -> Result<(), Stop> {
    let mut next = from;
    let mut buffer = vec![0u8; 256 << 10];
    let mut attempt = 0;
    while next <= to {
        let mut body = request(fetch, target, next, to)?;
        let mut received = 0u64;
        let mut failure = None;
        loop {
            match body.read(&mut buffer) {
                Ok(0) => break,
                Ok(n) => {
                    let wanted = (to + 1 - next - received).min(n as u64) as usize;
                    into.write_all(&buffer[..wanted]).map_err(|_| Stop::Client)?;
                    received += wanted as u64;
                    if wanted < n {
                        // More than asked for would shift every later byte.
                        return Err(Stop::Upstream(format!("YouTube sent more than bytes {next}-{to}")));
                    }
                }
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(e) => {
                    failure = Some(e.to_string());
                    break;
                }
            }
        }
        next += received;
        if next <= to {
            let why = failure.unwrap_or_else(|| "ended early".into());
            if attempt >= 2 || received == 0 {
                return Err(Stop::Upstream(format!("YouTube broke off at byte {next} ({why})")));
            }
            log(shared, format!("YouTube reply broke off at byte {next} ({why}), continuing from there"));
        }
        attempt += 1;
    }
    Ok(())
}

fn request(fetch: &dyn Fetch, target: &Target, from: u64, to: u64) -> Result<Box<dyn Read + Send>, Stop> {
    // Appended as text: rebuilding the query could re-encode signed values.
    let url = format!("{}&range={from}-{to}", target.url);
    let mut attempt = 0;
    loop {
        match fetch.get(target, &url) {
            Ok((200 | 206, body)) => return Ok(body),
            Ok((status, _)) => {
                // A 403 means the address expired; the app reopens the video.
                if status == 403 || attempt >= 1 {
                    return Err(Stop::Upstream(format!("YouTube answered {status}")));
                }
            }
            Err(e) => {
                // A connection YouTube dropped, before any byte of this reply.
                if attempt >= 1 {
                    return Err(Stop::Upstream(e));
                }
                std::thread::sleep(Duration::from_millis(500));
            }
        }
        attempt += 1;
    }
}

static RELAY: OnceLock<Relay> = OnceLock::new();

/// Starts the relay once; its port, or 0 when it could not listen.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_relay_start() -> u16 {
    if let Some(relay) = RELAY.get() {
        return relay.port();
    }
    match Relay::start(Arc::new(Web::default())) {
        Ok(relay) => RELAY.get_or_init(|| relay).port(),
        Err(_) => 0,
    }
}

/// The loopback address for the [Target] in [json], or null.
///
/// # Safety
/// [json] points at [len] readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_relay_register(json: *const u8, len: usize) -> *mut c_char {
    let Some(relay) = RELAY.get() else { return std::ptr::null_mut() };
    match serde_json::from_str::<Target>(unsafe { crate::taste::text(json, len) }).ok().and_then(|t| relay.register(t)) {
        Some(address) => crate::taste::give(address),
        None => std::ptr::null_mut(),
    }
}

/// The relay's log lines since the last call, as a JSON array.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_relay_log() -> *mut c_char {
    let lines = RELAY.get().map(Relay::take_log).unwrap_or_default();
    crate::taste::give_json(&lines)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    /// Serves [data] like googlevideo, cutting each reply after [cut] bytes.
    struct Fake {
        data: Vec<u8>,
        cut: Option<usize>,
        status: u16,
        calls: Mutex<Vec<String>>,
    }

    impl Fetch for Fake {
        fn get(&self, _: &Target, url: &str) -> Result<(u16, Box<dyn Read + Send>), String> {
            self.calls.lock().unwrap().push(url.to_string());
            let range = query(url, "range").unwrap();
            let (a, b) = range.split_once('-').unwrap();
            let (a, b): (usize, usize) = (a.parse().unwrap(), b.parse().unwrap());
            let mut slice = self.data[a..=b.min(self.data.len() - 1)].to_vec();
            if let Some(cut) = self.cut {
                slice.truncate(cut);
            }
            Ok((self.status, Box::new(Cursor::new(slice))))
        }
    }

    fn fake(size: usize, cut: Option<usize>, status: u16) -> Arc<Fake> {
        Arc::new(Fake { data: (0..size).map(|i| (i % 251) as u8).collect(), cut, status, calls: Mutex::new(vec![]) })
    }

    fn get(address: &str, range: Option<&str>) -> (String, Vec<u8>) {
        let path = address.trim_start_matches("http://");
        let (host, path) = path.split_once('/').unwrap();
        let mut stream = TcpStream::connect(host).unwrap();
        let range = range.map_or(String::new(), |r| format!("Range: {r}\r\n"));
        write!(stream, "GET /{path} HTTP/1.1\r\nHost: {host}\r\n{range}Connection: close\r\n\r\n").unwrap();
        let mut all = vec![];
        stream.read_to_end(&mut all).unwrap();
        let split = all.windows(4).position(|w| w == b"\r\n\r\n").unwrap();
        (String::from_utf8_lossy(&all[..split]).into_owned(), all[split + 4..].to_vec())
    }

    fn target(size: u64) -> Target {
        Target { url: "https://example.com/videoplayback?mime=video%2Fwebm&clen=1".into(), size, user_agent: None, mime: None, proxy: None, chunk: CHUNK }
    }

    #[test]
    fn reads_ranges() {
        assert_eq!(byte_range(None, 100), Range::Whole);
        assert_eq!(byte_range(Some("bytes=10-"), 100), Range::Part(10, 99));
        assert_eq!(byte_range(Some("bytes=10-200"), 100), Range::Part(10, 99));
        assert_eq!(byte_range(Some("bytes=-30"), 100), Range::Part(70, 99));
        assert_eq!(byte_range(Some("bytes=100-"), 100), Range::Unsatisfiable);
        assert_eq!(byte_range(Some("bytes=5-2"), 100), Range::Unsatisfiable);
        assert_eq!(query("https://x/v?a=1&mime=video%2Fmp4", "mime").as_deref(), Some("video/mp4"));
    }

    #[test]
    fn serves_a_range_in_chunks() {
        let size = (CHUNK * 2 + 1234) as usize;
        let source = fake(size, None, 200);
        let relay = Relay::start(source.clone()).unwrap();
        let address = relay.register(target(size as u64)).unwrap();
        let (head, body) = get(&address, Some("bytes=100-"));
        assert!(head.starts_with("HTTP/1.1 206"), "{head}");
        assert!(head.contains(&format!("Content-Range: bytes 100-{}/{size}", size - 1)), "{head}");
        assert!(head.contains("Content-Type: video/webm"), "{head}");
        assert_eq!(body, source.data[100..]);
        let calls = source.calls.lock().unwrap();
        assert_eq!(calls.len(), 3);
        assert!(calls[0].ends_with(&format!("&range=100-{}", 100 + CHUNK - 1)));
    }

    #[test]
    fn continues_a_reply_cut_short() {
        let source = fake(1000, Some(400), 206);
        let relay = Relay::start(source.clone()).unwrap();
        let address = relay.register(target(1000)).unwrap();
        let (head, body) = get(&address, None);
        assert!(head.starts_with("HTTP/1.1 200"), "{head}");
        assert_eq!(body, source.data);
        assert!(relay.take_log().iter().any(|l| l.contains("broke off at byte 400")));
    }

    #[test]
    fn stops_on_403_and_unknown_addresses() {
        let source = fake(1000, None, 403);
        let relay = Relay::start(source.clone()).unwrap();
        let address = relay.register(target(1000)).unwrap();
        let (_, body) = get(&address, None);
        assert!(body.is_empty());
        assert_eq!(source.calls.lock().unwrap().len(), 1);
        assert!(relay.take_log().iter().any(|l| l.contains("403")));
        let (head, _) = get(&format!("http://127.0.0.1:{}/nothing", relay.port()), None);
        assert!(head.starts_with("HTTP/1.1 404"));
        let (head, _) = get(&address, Some("bytes=5000-"));
        assert!(head.starts_with("HTTP/1.1 416"), "{head}");
        assert_eq!(relay.register(target(0)), None);
    }
}
