//! The app's HTTP client: one pooled connection set for every request the
//! Dart side makes (API calls, thumbnails, translations, updates), with
//! HTTP/2, compressed bodies, the system's TLS and the app's proxy.
//!
//! Dart hands each request over with an id and the native port of a
//! `ReceivePort`; the answer comes back on that port as messages:
//! `[id, 0, status, headers_json, content_length, final_url]` once the head is in,
//! `[id, 1, bytes]` for each piece of the body, `[id, 2]` at the end and
//! `[id, 3, message]` on failure. A request can be cancelled by id.

use std::collections::HashMap;
use std::ffi::{CString, c_char};
use std::sync::{LazyLock, Mutex, RwLock};
use std::time::Duration;

use serde::Deserialize;
use tokio::runtime::Runtime;
use tokio::task::AbortHandle;

use crate::taste::text;

// Dart_CObject from dart_native_api.h, only the kinds sent here.
const K_NULL: i32 = 0;
const K_INT64: i32 = 3;
const K_STRING: i32 = 5;
const K_ARRAY: i32 = 6;
const K_TYPED_DATA: i32 = 7;
const K_UINT8: i32 = 2;

#[repr(C)]
#[derive(Clone, Copy)]
struct TypedData {
    kind: i32,
    length: isize,
    values: *const u8,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct Array {
    length: isize,
    values: *mut *mut CObject,
}

#[repr(C)]
union Value {
    as_int64: i64,
    as_string: *const c_char,
    as_array: Array,
    as_typed_data: TypedData,
    // The largest member (external typed data) sets the union's size.
    _size: [u64; 5],
}

#[repr(C)]
pub struct CObject {
    kind: i32,
    value: Value,
}

pub type PostCObject = unsafe extern "C" fn(port: i64, message: *mut CObject) -> bool;

static POST: RwLock<Option<PostCObject>> = RwLock::new(None);

/// A message element; the Dart VM copies it while posting.
pub(crate) enum Item {
    Int(i64),
    Text(String),
    Bytes(Vec<u8>),
    Null,
}

pub(crate) fn post(port: i64, items: Vec<Item>) -> bool {
    let Some(send) = *POST.read().unwrap_or_else(|e| e.into_inner()) else {
        return false;
    };
    let strings: Vec<Option<CString>> =
        items.iter().map(|i| if let Item::Text(t) = i { Some(CString::new(t.replace('\0', "")).unwrap_or_default()) } else { None }).collect();
    let mut objects: Vec<CObject> = items
        .iter()
        .zip(&strings)
        .map(|(item, string)| match item {
            Item::Int(n) => CObject { kind: K_INT64, value: Value { as_int64: *n } },
            Item::Text(_) => CObject { kind: K_STRING, value: Value { as_string: string.as_ref().map_or(std::ptr::null(), |s| s.as_ptr()) } },
            Item::Bytes(b) => CObject { kind: K_TYPED_DATA, value: Value { as_typed_data: TypedData { kind: K_UINT8, length: b.len() as isize, values: b.as_ptr() } } },
            Item::Null => CObject { kind: K_NULL, value: Value { as_int64: 0 } },
        })
        .collect();
    let mut pointers: Vec<*mut CObject> = objects.iter_mut().map(|o| o as *mut CObject).collect();
    let mut message = CObject { kind: K_ARRAY, value: Value { as_array: Array { length: pointers.len() as isize, values: pointers.as_mut_ptr() } } };
    // SAFETY: every pointer stays alive until the call returns, and the VM
    // copies the message before it does.
    unsafe { send(port, &mut message) }
}

#[derive(Deserialize, Default)]
struct Settings {
    /// `http://host:port` or `socks5://…`; none for a direct connection.
    proxy: Option<String>,
    /// With no [proxy], use the system's (Windows settings, macOS settings,
    /// or the `*_PROXY` variables) instead of connecting directly.
    #[serde(default)]
    system: bool,
    /// 加密 DNS for direct connections.
    #[serde(default)]
    dns: crate::dns::Settings,
}

fn build(settings: &Settings) -> reqwest::Client {
    let mut builder = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(15))
        .read_timeout(Duration::from_secs(60))
        .pool_idle_timeout(Duration::from_secs(90))
        .pool_max_idle_per_host(8)
        .tcp_nodelay(true)
        .tcp_keepalive(Duration::from_secs(60))
        .http2_adaptive_window(true)
        .redirect(reqwest::redirect::Policy::limited(10));
    match settings.proxy.as_deref().and_then(|p| reqwest::Proxy::all(p).ok()) {
        Some(proxy) => builder = builder.proxy(proxy),
        None if !settings.system => builder = builder.no_proxy(),
        None => {}
    }
    if let Some(doh) = crate::dns::current() {
        builder = builder.dns_resolver(std::sync::Arc::new(crate::dns::Resolver(doh)));
    }
    builder.build().unwrap_or_else(|_| reqwest::Client::new())
}

static RUNTIME: LazyLock<Runtime> = LazyLock::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .thread_name("lumtub-http")
        .enable_all()
        .build()
        .expect("HTTP runtime")
});
pub(crate) fn runtime() -> &'static Runtime {
    &RUNTIME
}

/// The client every request goes through, on the app's proxy and DNS.
pub(crate) fn client() -> reqwest::Client {
    CLIENT.read().unwrap_or_else(|e| e.into_inner()).clone()
}

static CLIENT: LazyLock<RwLock<reqwest::Client>> = LazyLock::new(|| RwLock::new(build(&Settings { proxy: None, system: true, dns: Default::default() })));
static RUNNING: LazyLock<Mutex<HashMap<i64, AbortHandle>>> = LazyLock::new(|| Mutex::new(HashMap::new()));

#[derive(Deserialize)]
struct Request {
    method: String,
    url: String,
    #[serde(default)]
    headers: Vec<(String, String)>,
}

/// Reads already waiting are joined into pieces of up to this size, so a
/// big download is not one message per network read.
const PIECE: usize = 64 * 1024;

async fn run(id: i64, port: i64, request: Request, body: Vec<u8>) {
    let client = CLIENT.read().unwrap_or_else(|e| e.into_inner()).clone();
    let method = reqwest::Method::from_bytes(request.method.as_bytes()).unwrap_or(reqwest::Method::GET);
    let mut builder = client.request(method, &request.url);
    for (name, value) in &request.headers {
        builder = builder.header(name.as_str(), value.as_str());
    }
    if !body.is_empty() {
        builder = builder.body(body);
    }
    let mut response = match builder.send().await {
        Ok(r) => r,
        Err(e) => {
            post(port, vec![Item::Int(id), Item::Int(3), Item::Text(describe(&e))]);
            return;
        }
    };
    let headers: Vec<(String, String)> =
        response.headers().iter().map(|(k, v)| (k.as_str().to_string(), String::from_utf8_lossy(v.as_bytes()).into_owned())).collect();
    let length = response.content_length().map_or(Item::Null, |n| Item::Int(n as i64));
    let head = vec![
        Item::Int(id),
        Item::Int(0),
        Item::Int(response.status().as_u16() as i64),
        Item::Text(serde_json::to_string(&headers).unwrap_or_default()),
        length,
        Item::Text(response.url().to_string()),
    ];
    if !post(port, head) {
        return;
    }
    // What has arrived goes on at once, so a slow stream is not held back;
    // reads already waiting are joined first, up to [PIECE].
    let mut ended = false;
    while !ended {
        let mut piece = match response.chunk().await {
            Ok(Some(bytes)) => bytes.to_vec(),
            Ok(None) => break,
            Err(e) => {
                post(port, vec![Item::Int(id), Item::Int(3), Item::Text(describe(&e))]);
                return;
            }
        };
        while piece.len() < PIECE {
            match tokio::time::timeout(Duration::ZERO, response.chunk()).await {
                Ok(Ok(Some(bytes))) => piece.extend_from_slice(&bytes),
                Ok(Ok(None)) => {
                    ended = true;
                    break;
                }
                Ok(Err(e)) => {
                    post(port, vec![Item::Int(id), Item::Int(3), Item::Text(describe(&e))]);
                    return;
                }
                Err(_) => break,
            }
        }
        if !post(port, vec![Item::Int(id), Item::Int(1), Item::Bytes(piece)]) {
            return;
        }
    }
    post(port, vec![Item::Int(id), Item::Int(2)]);
}

fn describe(error: &reqwest::Error) -> String {
    let kind = if error.is_timeout() {
        "timed out"
    } else if error.is_connect() {
        "could not connect"
    } else if error.is_redirect() {
        "too many redirects"
    } else {
        "request failed"
    };
    let mut detail = error.to_string();
    let mut source = std::error::Error::source(error);
    while let Some(inner) = source {
        detail = format!("{detail}: {inner}");
        source = inner.source();
    }
    format!("{kind} ({detail})")
}

/// Takes Dart's `NativeApi.postCObject`, which every answer goes through.
///
/// # Safety
/// [post] must be the VM's `Dart_PostCObject`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_http_init(post: PostCObject) {
    *POST.write().unwrap_or_else(|e| e.into_inner()) = Some(post);
}

/// Sets the proxy and 加密 DNS from JSON `{"proxy": "socks5://…" | null,
/// "system": bool, "dns": {"url", "bootstrap"}}`;
/// connections already open finish on the old route.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_http_configure(json: *const u8, length: usize) {
    let settings: Settings = serde_json::from_str(unsafe { text(json, length) }).unwrap_or_default();
    crate::dns::set(settings.dns.clone());
    *CLIENT.write().unwrap_or_else(|e| e.into_inner()) = build(&settings);
}

/// Starts request [id], described by JSON `{"method", "url", "headers": [[name, value], …]}`
/// with [body], answering on [port]. Returns false when it cannot start.
///
/// # Safety
/// [json] and [body] must point to their lengths of bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_http_send(id: i64, port: i64, json: *const u8, length: usize, body: *const u8, body_length: usize) -> bool {
    if POST.read().map(|p| p.is_none()).unwrap_or(true) {
        return false;
    }
    let Ok(request) = serde_json::from_str::<Request>(unsafe { text(json, length) }) else {
        return false;
    };
    let body = if body.is_null() || body_length == 0 { Vec::new() } else { unsafe { std::slice::from_raw_parts(body, body_length) }.to_vec() };
    let task = RUNTIME.spawn(async move {
        run(id, port, request, body).await;
        RUNNING.lock().unwrap_or_else(|e| e.into_inner()).remove(&id);
    });
    let mut running = RUNNING.lock().unwrap_or_else(|e| e.into_inner());
    if !task.is_finished() {
        running.insert(id, task.abort_handle());
    }
    true
}

/// Stops request [id], such as when Dart stops reading its body.
#[unsafe(no_mangle)]
pub extern "C" fn lumtub_http_cancel(id: i64) {
    if let Some(task) = RUNNING.lock().unwrap_or_else(|e| e.into_inner()).remove(&id) {
        task.abort();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cobject_layout_matches_dart() {
        // type (4) + padding (4) + the 40-byte union, as on every 64-bit target.
        assert_eq!(std::mem::size_of::<CObject>(), 48);
        assert_eq!(std::mem::align_of::<CObject>(), 8);
    }

    #[test]
    fn settings_read_proxy_and_system() {
        let s: Settings = serde_json::from_str(r#"{"proxy":"socks5://127.0.0.1:1080","system":false}"#).unwrap();
        assert_eq!(s.proxy.as_deref(), Some("socks5://127.0.0.1:1080"));
        let _ = build(&s);
        for proxy in ["socks5h://u:p@127.0.0.1:1080", "socks4a://127.0.0.1:1080", "http://127.0.0.1:8080"] {
            assert!(reqwest::Proxy::all(proxy).is_ok(), "{proxy}");
        }
        let d: Settings = serde_json::from_str("{}").unwrap();
        assert!(d.proxy.is_none() && !d.system);
    }
}
